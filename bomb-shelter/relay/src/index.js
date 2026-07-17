// Bomb Shelter internet relay.
//
// The hosting phone connects OUT to this Worker (no port forwarding) and
// gets a short room code. Remote friends open https://<worker>/r/CODE in a
// browser: the room serves them the same game page the phone serves on LAN,
// and relays their WebSocket messages to the host verbatim.
//
// Envelope protocol (host <-> relay):
//   relay -> host: {c:id, ev:"open"} | {c:id, ev:"close"} | {c:id, m:<msg>}
//                  {t:"room", code, key}  on bind (key reclaims the room)
//                  {t:"hb"}               heartbeat echo
//                  {t:"badroom"}          reclaim key mismatch: rejoin fresh
//   host -> relay: {c:id, m:<msg>}  unicast to one guest
//                  {b:1,  m:<msg>}  broadcast to every guest
//                  {t:"page", html:"..."}  store the game page for /r/CODE
//                  {t:"hb"}  heartbeat: echoed back so an idle host's socket
//                            carries traffic (NAT/edge idle timeouts) and a
//                            half-open link is detected by the missing echo
// Guests speak the plain game protocol; they never see envelopes. A guest
// joining a room with no live host gets {t:"nohost"} and is closed (4404)
// instead of having its messages silently dropped.
//
// The host may reconnect with ?code=X&key=K to reclaim the same room after
// a dropped socket (phone backgrounded, network blip), so a code that was
// already shared keeps working.

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function genFrom(len) {
  let s = "";
  const buf = new Uint8Array(len);
  crypto.getRandomValues(buf);
  for (const b of buf) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}
const genCode = () => genFrom(5);
const genKey = () => genFrom(16);

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (parts[0] === "host" && req.headers.get("Upgrade") === "websocket") {
      const reclaimCode = (url.searchParams.get("code") || "").toUpperCase();
      const reclaimKey = url.searchParams.get("key") || "";
      const fresh = !(reclaimCode && reclaimKey);
      const code = fresh ? genCode() : reclaimCode;
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      const hdrs = new Headers(req.headers);
      hdrs.set("x-room-code", code);
      hdrs.set("x-room-key", fresh ? genKey() : reclaimKey);
      hdrs.set("x-key-fresh", fresh ? "1" : "0");
      hdrs.set("x-role", "host");
      return stub.fetch(new Request(req.url, { headers: hdrs }));
    }

    if (parts[0] === "join" && parts[1] && req.headers.get("Upgrade") === "websocket") {
      const code = parts[1].toUpperCase();
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      const hdrs = new Headers(req.headers);
      hdrs.set("x-role", "guest");
      return stub.fetch(new Request(req.url, { headers: hdrs }));
    }

    if (parts[0] === "r" && parts[1]) {
      const code = parts[1].toUpperCase();
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      return stub.fetch(req);
    }

    return new Response(
      "Bomb Shelter relay. Host from the app; join at /r/CODE.",
      { headers: { "content-type": "text/plain" } });
  },
};

export class Room {
  constructor(state) {
    this.state = state;
    this.host = null;
    this.guests = new Map();
    this.nextId = 1;
    this.page = null;
  }

  // workerd's server-side WebSocket doesn't reliably expose readyState, so
  // liveness is tracked by hand: `host` is nulled on close/error and on any
  // failed send (the host's 20s heartbeats flush out half-open sockets).
  hostAlive() {
    return this.host !== null;
  }

  async fetch(req) {
    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (req.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();
      if (req.headers.get("x-role") === "host") {
        await this.bindHost(server,
          req.headers.get("x-room-code"),
          req.headers.get("x-room-key"),
          req.headers.get("x-key-fresh") === "1");
      } else {
        this.bindGuest(server);
      }
      return new Response(null, { status: 101, webSocket: client });
    }

    if (parts[0] === "r") {
      // A live host is required: serving the stored page for a dead room
      // sends guests into a match that can never answer them ("frozen").
      // The page auto-refreshes so a returning host revives waiting guests.
      if (!this.hostAlive()) {
        return new Response(
          "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" +
          "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" +
          "<meta http-equiv=\"refresh\" content=\"5\">" +
          "<title>Bomb Shelter</title></head>" +
          "<body style=\"background:#17100a;color:#eee;font-family:sans-serif;" +
          "text-align:center;padding-top:38vh\">" +
          "<h2 style=\"color:#ffca28\">This room is closed</h2>" +
          "<p>The host isn't connected right now.<br>" +
          "Ask them for a fresh code, or keep this page open — " +
          "it retries automatically.</p></body></html>",
          { status: 200, headers: { "content-type": "text/html; charset=utf-8" } });
      }
      const page = this.page || (await this.state.storage.get("page"));
      if (!page) {
        return new Response(
          "Room not found (or the host hasn't opened it yet).",
          { status: 404, headers: { "content-type": "text/plain" } });
      }
      return new Response(page,
        { headers: { "content-type": "text/html; charset=utf-8" } });
    }

    return new Response("bad request", { status: 400 });
  }

  async bindHost(ws, code, key, fresh) {
    const stored = await this.state.storage.get("key");
    if (!fresh) {
      // Reclaim: the key must match the one this room handed out. A live
      // host with the right key replaces itself (its old socket may be
      // half-open); a wrong key means "start over with a fresh room".
      if (!stored || stored !== key) {
        try { ws.send(JSON.stringify({ t: "badroom" })); ws.close(4403, "bad key"); } catch (e) {}
        return;
      }
    } else if (stored && this.hostAlive()) {
      // Freak genCode collision with a live room: don't hijack it.
      try { ws.send(JSON.stringify({ t: "badroom" })); ws.close(4409, "taken"); } catch (e) {}
      return;
    }
    this.state.storage.put("key", key);
    if (this.host) { try { this.host.close(); } catch (e) {} }
    this.host = ws;
    ws.send(JSON.stringify({ t: "room", code, key }));
    ws.addEventListener("message", (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch (e) { return; }
      if (m.t === "hb") {
        try { ws.send('{"t":"hb"}'); } catch (e) { this.hostGone(ws); }
        return;
      }
      if (m.t === "page" && typeof m.html === "string") {
        this.page = m.html;
        this.state.storage.put("page", m.html);
        return;
      }
      if (m.b) {
        const s = JSON.stringify(m.m);
        for (const g of this.guests.values()) { try { g.send(s); } catch (e) {} }
      } else if (m.c !== undefined) {
        const g = this.guests.get(m.c);
        if (g) { try { g.send(JSON.stringify(m.m)); } catch (e) {} }
      }
    });
    ws.addEventListener("close", () => this.hostGone(ws));
    ws.addEventListener("error", () => this.hostGone(ws));
  }

  // The host's socket died: tell every guest instead of letting their
  // messages vanish into a dead room. Web guests auto-reconnect and rejoin
  // once the host reclaims the code.
  hostGone(ws) {
    if (this.host !== ws) return;
    this.host = null;
    for (const g of this.guests.values()) {
      try { g.send('{"t":"nohost"}'); g.close(4404, "host gone"); } catch (e) {}
    }
    this.guests.clear();
  }

  bindGuest(ws) {
    if (!this.hostAlive()) {
      try { ws.send('{"t":"nohost"}'); ws.close(4404, "host gone"); } catch (e) {}
      return;
    }
    const id = this.nextId++;
    this.guests.set(id, ws);
    this.toHost({ c: id, ev: "open" });
    ws.addEventListener("message", (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch (e) { return; }
      this.toHost({ c: id, m });
    });
    const bye = () => {
      if (this.guests.delete(id)) this.toHost({ c: id, ev: "close" });
    };
    ws.addEventListener("close", bye);
    ws.addEventListener("error", bye);
  }

  toHost(obj) {
    if (this.host) {
      try { this.host.send(JSON.stringify(obj)); }
      catch (e) { this.hostGone(this.host); }
    }
  }
}
