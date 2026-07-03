extends Node
## Autoload "NetHub" — web join. Hosts a tiny HTTP server that serves a
## phone controller page, and a WebSocket server that receives joins and
## button input. The QR code in Quick Settings encodes join_url(). Phones
## must be on the same network as the host.

const HTTP_PORT_BASE := 8910
const WS_PORT_BASE := 8920
const MAX_CLIENTS := 6
const HTTP_TIMEOUT := 6.0

var http_port := 0
var ws_port := 0
## id -> {ws, joined, connected, name, color, axis, jump}
var clients := {}

var _http := TCPServer.new()
var _wss := TCPServer.new()
var _pending: Array[Dictionary] = []
var _next_id := 1

const PAGE := """<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>Bomb Shelter — join</title><style>
*{margin:0;padding:0;box-sizing:border-box;-webkit-user-select:none;user-select:none;touch-action:none}
body{background:#17100a;color:#eee;font-family:sans-serif;height:100vh;overflow:hidden;display:flex;flex-direction:column}
#join{display:flex;flex-direction:column;gap:14px;padding:26px;max-width:420px;margin:auto;width:100%}
h1{font-size:22px;color:#ffca28;text-align:center}
input[type=text]{font-size:18px;padding:10px;border-radius:8px;border:1px solid #555;background:#222;color:#eee}
.row{display:flex;align-items:center;gap:12px}
input[type=color]{width:56px;height:44px;border:none;background:none}
button{font-size:20px;padding:14px;border-radius:10px;border:none;background:#ffca28;color:#000;font-weight:bold}
#pad{display:none;flex:1;flex-direction:column}
#status{text-align:center;padding:8px;color:#9ccc65;font-size:14px}
#btns{flex:1;display:flex}
.pad{flex:1;display:flex;align-items:center;justify-content:center;font-size:44px;font-weight:bold;
color:#fff;background:#2a2118;margin:6px;border-radius:16px;border:2px solid #4a3a21}
.pad:active,.pad.on{background:#5a4a2e}
#jump{background:#3a2a3a}
</style></head><body>
<div id="join"><h1>BOMB SHELTER</h1>
<input id="name" type="text" maxlength="10" placeholder="Your name">
<div class="row"><label>Color</label><input id="color" type="color" value="#ff8f2e"></div>
<button onclick="doJoin()">JOIN GAME</button><div id="status">connecting…</div></div>
<div id="pad"><div id="status2" style="text-align:center;padding:6px;font-size:13px;color:#888">
Bomb Shelter controller</div><div id="btns">
<div class="pad" id="left">&#9664;</div><div class="pad" id="jump">&#9650;</div><div class="pad" id="right">&#9654;</div>
</div></div>
<script>
var ws=null,joined=false,st={a:0,j:0},held={left:false,right:false,jump:false};
function connect(){
 ws=new WebSocket("ws://"+location.hostname+":__WSPORT__");
 ws.onopen=function(){document.getElementById("status").textContent="ready — pick a name and join";
  if(joined)sendJoin();};
 ws.onclose=function(){document.getElementById("status").textContent="reconnecting…";setTimeout(connect,1500);};
}
function sendJoin(){ws.send(JSON.stringify({t:"join",n:document.getElementById("name").value||"web",
 c:document.getElementById("color").value}));}
function doJoin(){if(!ws||ws.readyState!==1)return;joined=true;sendJoin();
 document.getElementById("join").style.display="none";document.getElementById("pad").style.display="flex";}
function send(){if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:"i",a:st.a,j:st.j?1:0}));}
function upd(){var a=0;if(held.left)a-=1;if(held.right)a+=1;
 if(a!==st.a||held.jump!==!!st.j){st.a=a;st.j=held.jump;send();}}
["left","right","jump"].forEach(function(k){var el=document.getElementById(k);
 function on(e){e.preventDefault();held[k]=true;el.classList.add("on");upd();}
 function off(e){e.preventDefault();held[k]=false;el.classList.remove("on");upd();}
 el.addEventListener("pointerdown",on);el.addEventListener("pointerup",off);
 el.addEventListener("pointercancel",off);el.addEventListener("pointerleave",off);});
document.getElementById("color").addEventListener("change",function(e){
 if(ws&&ws.readyState===1&&joined)ws.send(JSON.stringify({t:"c",c:e.target.value}));});
setInterval(send,2000);
connect();
</script></body></html>"""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for p in range(HTTP_PORT_BASE, HTTP_PORT_BASE + 5):
		if _http.listen(p) == OK:
			http_port = p
			break
	for p in range(WS_PORT_BASE, WS_PORT_BASE + 5):
		if _wss.listen(p) == OK:
			ws_port = p
			break


func join_url() -> String:
	return "http://%s:%d" % [lan_ip(), http_port]


func lan_ip() -> String:
	var fallback := "127.0.0.1"
	var candidates: Array[String] = []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.begins_with("192.168."):
			return s
		if s.begins_with("10."):
			candidates.push_front(s)
		elif s.begins_with("172."):
			var parts := s.split(".")
			if parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31:
				candidates.append(s)
	return candidates[0] if not candidates.is_empty() else fallback


func _process(delta: float) -> void:
	# --- plain HTTP: serve the controller page ---
	while _http.is_connection_available():
		_pending.append({"tcp": _http.take_connection(), "buf": "", "age": 0.0, "sent": false})
	var keep: Array[Dictionary] = []
	for p in _pending:
		var tcp: StreamPeerTCP = p.tcp
		tcp.poll()
		p.age += delta
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if p.sent:
			if p.age > 1.0:
				tcp.disconnect_from_host()
			else:
				keep.append(p)
			continue
		var n := tcp.get_available_bytes()
		if n > 0:
			p.buf += tcp.get_utf8_string(n)
		if p.buf.contains("\r\n\r\n"):
			var body := PAGE.replace("__WSPORT__", str(ws_port)).to_utf8_buffer()
			var head := ("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" +
				"Content-Length: %d\r\nConnection: close\r\n\r\n") % body.size()
			tcp.put_data(head.to_utf8_buffer())
			tcp.put_data(body)
			p.sent = true
			p.age = 0.0
			keep.append(p)
		elif p.age < HTTP_TIMEOUT:
			keep.append(p)
		else:
			tcp.disconnect_from_host()
	_pending = keep

	# --- WebSocket controllers ---
	while _wss.is_connection_available():
		var tcp := _wss.take_connection()
		if clients.size() >= MAX_CLIENTS:
			tcp.disconnect_from_host()
			continue
		var ws := WebSocketPeer.new()
		ws.accept_stream(tcp)
		clients[_next_id] = {
			"ws": ws, "joined": false, "connected": true,
			"name": "", "color": Color("ff8f2e"),
			"axis": 0.0, "jump": false,
		}
		_next_id += 1

	for id in clients.keys():
		var c: Dictionary = clients[id]
		if not c.connected:
			continue
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var state := ws.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			c.connected = false
			c.axis = 0.0
			c.jump = false
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				_handle(c, msg)


func _handle(c: Dictionary, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"join":
			c.joined = true
			c.name = str(msg.get("n", "web")).strip_edges().left(10)
			if c.name.is_empty():
				c.name = "web"
			c.color = Color.from_string(str(msg.get("c", "")), Color("ff8f2e"))
		"i":
			c.axis = clampf(float(msg.get("a", 0)), -1.0, 1.0)
			c.jump = int(msg.get("j", 0)) != 0
		"c":
			c.color = Color.from_string(str(msg.get("c", "")), c.color)
