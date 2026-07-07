// Bomb Shelter internet relay.
//
// The hosting phone connects OUT to this Worker (no port forwarding) and
// gets a short room code. Remote friends open https://<worker>/r/CODE in a
// browser: the room serves them the same game page the phone serves on LAN,
// and relays their WebSocket messages to the host verbatim.
//
// Envelope protocol (host <-> relay):
//   relay -> host: {c:id, ev:"open"} | {c:id, ev:"close"} | {c:id, m:<msg>}
//   host -> relay: {c:id, m:<msg>}  unicast to one guest
//                  {b:1,  m:<msg>}  broadcast to every guest
//                  {t:"page", html:"..."}  store the game page for /r/CODE
// Guests speak the plain game protocol; they never see envelopes.

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I

function genCode() {
  let s = "";
  const buf = new Uint8Array(5);
  crypto.getRandomValues(buf);
  for (const b of buf) s += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return s;
}

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (parts[0] === "host" && req.headers.get("Upgrade") === "websocket") {
      const code = genCode();
      const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
      const hdrs = new Headers(req.headers);
      hdrs.set("x-room-code", code);
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

  async fetch(req) {
    const url = new URL(req.url);
    const parts = url.pathname.split("/").filter(Boolean);

    if (req.headers.get("Upgrade") === "websocket") {
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      server.accept();
      if (req.headers.get("x-role") === "host") {
        this.bindHost(server, req.headers.get("x-room-code"));
      } else {
        this.bindGuest(server);
      }
      return new Response(null, { status: 101, webSocket: client });
    }

    if (parts[0] === "r") {
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

  bindHost(ws, code) {
    if (this.host) { try { this.host.close(); } catch (e) {} }
    this.host = ws;
    ws.send(JSON.stringify({ t: "room", code }));
    ws.addEventListener("message", (ev) => {
      let m;
      try { m = JSON.parse(ev.data); } catch (e) { return; }
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
    const gone = () => { if (this.host === ws) this.host = null; };
    ws.addEventListener("close", gone);
    ws.addEventListener("error", gone);
  }

  bindGuest(ws) {
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
    if (this.host) { try { this.host.send(JSON.stringify(obj)); } catch (e) {} }
  }
}
