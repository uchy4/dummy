extends Node
## Autoload "NetHub" — web join. Hosts a tiny HTTP server that serves a
## phone controller page, and a WebSocket server that receives joins and
## button input. The QR code in Quick Settings encodes join_url(). Phones
## must be on the same network as the host.

const HTTP_PORT_BASE := 8910
const WS_PORT_BASE := 8920
const MAX_CLIENTS := 6
const HTTP_TIMEOUT := 6.0

## Selectable player colors (hex, no #). Joiners get the first free one by
## default and can't take one already in use.
const PALETTE: Array[String] = [
	"9575ff", "ef5350", "9ccc65", "ffca28", "ff8f2e",
	"4dd0e1", "ff6bcb", "a1887f", "eceff1", "26a69a",
]

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
<title>Bomb Shelter</title><style>
*{margin:0;padding:0;box-sizing:border-box;-webkit-user-select:none;user-select:none;touch-action:none}
body{background:#17100a;color:#eee;font-family:sans-serif;height:100vh;overflow:hidden}
#join{display:flex;flex-direction:column;gap:14px;padding:26px;max-width:420px;margin:auto;width:100%;height:100%;justify-content:center}
h1{font-size:22px;color:#ffca28;text-align:center}
input[type=text]{font-size:18px;padding:10px;border-radius:8px;border:1px solid #555;background:#222;color:#eee}
#swatches{display:flex;flex-wrap:wrap;justify-content:center}
.sw{width:42px;height:42px;border-radius:50%;margin:5px;border:3px solid transparent}
.sw.sel{border-color:#fff}
.sw.dis{opacity:.22}
button{font-size:20px;padding:14px;border-radius:10px;border:none;background:#ffca28;color:#000;font-weight:bold}
#joinfs{background:#2a2118;color:#eee;border:1px solid #5a4a2e;font-size:17px}
#status{text-align:center;padding:8px;color:#9ccc65;font-size:14px}
#game{display:none;position:fixed;inset:0}
canvas{position:absolute;inset:0;width:100%;height:100%}
.pad{position:absolute;bottom:14px;width:84px;height:84px;border-radius:50%;
background:rgba(255,255,255,.14);border:2px solid rgba(255,255,255,.35);
display:flex;align-items:center;justify-content:center;font-size:34px;color:rgba(255,255,255,.85)}
.pad.on{background:rgba(255,255,255,.35)}
#left{left:16px}#right{left:116px}#jump{right:16px}#kick{right:116px;font-size:26px}
#colorbtn{position:absolute;top:8px;right:10px;width:38px;height:38px;border-radius:50%;border:2px solid rgba(255,255,255,.6)}
#fs{position:absolute;top:8px;right:58px;width:44px;height:44px;border-radius:10px;
background:rgba(0,0,0,.45);border:2px solid rgba(255,255,255,.7);
display:flex;align-items:center;justify-content:center;font-size:26px;color:#fff}
</style></head><body>
<div id="join"><h1>BOMB SHELTER</h1>
<input id="name" type="text" maxlength="10" placeholder="Your name">
<div id="swatches"></div>
<button onclick="doJoin()">JOIN GAME</button>
<button id="joinfs" onclick="goFS()">&#x26F6; Fullscreen</button>
<div id="status">connecting…</div></div>
<div id="game"><canvas id="cv"></canvas>
<div class="pad" id="left">&#9664;</div><div class="pad" id="right">&#9654;</div>
<div class="pad" id="jump">&#9650;</div><div class="pad" id="kick">KICK</div>
<div id="colorbtn"></div><div id="fs">&#x26F6;</div></div>
<script>
var ws=null,joined=false,st={a:0,j:0,k:0},held={left:false,right:false,jump:false,kick:false};
var W=0,H=0,TS=16,SURF=20,FIN=0,grid=null,off=null,octx=null;
var roster=[],you=-1,sp=null,sc=null,tp=0,tc=0,flashes=[],sparks=[],win=null;
var opts=[],selKey=null,cycleIdx=0;
var CELL=["","#7a5230","#4b4b55","#4caf50"],CELL2=["","#5c3d22","#3a3a44","#3f9143"];
var BOMB=["#212126","#131318","#733f17","#1f5c2e"];
var cam={x:800,y:300},cv=document.getElementById("cv"),ctx=cv.getContext("2d");
function connect(){
 ws=new WebSocket("ws://"+location.hostname+":__WSPORT__");
 ws.onopen=function(){document.getElementById("status").textContent="ready — pick a name and join";
  if(joined)sendJoin();};
 ws.onclose=function(){document.getElementById("status").textContent="reconnecting…";setTimeout(connect,1500);};
 ws.onmessage=function(ev){var m=JSON.parse(ev.data);
  if(m.t==="s"){
   if(sc)for(var i=0;i<sc.p.length&&i<m.p.length;i++)
    if(sc.p[i][2]===1&&m.p[i][2]===0)burst(m.p[i][0],m.p[i][1],roster[i]?roster[i].c:"fff");
   sp=sc;tp=tc;sc=m;tc=performance.now();}
  else if(m.t==="carve"){carve(m.x,m.y,m.r);flashes.push({x:m.x,y:m.y,r:m.r,t:performance.now()});}
  else if(m.t==="init"){W=m.w;H=m.h;TS=m.ts;SURF=m.surf;FIN=m.fin;
   grid=new Uint8Array(m.grid.length);
   for(var i=0;i<m.grid.length;i++)grid[i]=m.grid.charCodeAt(i)-48;
   buildTerrain();sp=sc=null;flashes=[];sparks=[];win=null;}
  else if(m.t==="roster"){roster=m.p;updateBtn();}
  else if(m.t==="you"){you=m.i;updateBtn();}
  else if(m.t==="colors"){opts=m.opts;
   if(!joined){if(!selKey||!opts.some(function(o){return key(o)===selKey;}))
    selKey=opts.length?key(opts[0]):null;
   renderSw();}}
  else if(m.t==="win")win=m;};
}
function key(o){return o.join("|");}
function bg(o){return o.length>1?
 "repeating-linear-gradient(45deg,#"+o[0]+" 0,#"+o[0]+" 7px,#"+o[1]+" 7px,#"+o[1]+" 14px)":
 "#"+o[0];}
function renderSw(){var d=document.getElementById("swatches");d.innerHTML="";
 opts.forEach(function(o){var s=document.createElement("div");
 s.className="sw"+(key(o)===selKey?" sel":"");
 s.style.background=bg(o);
 s.addEventListener("click",function(){selKey=key(o);renderSw();});
 d.appendChild(s);});}
function selOpt(){for(var i=0;i<opts.length;i++)if(key(opts[i])===selKey)return opts[i];
 return opts.length?opts[0]:["ff8f2e"];}
function updateBtn(){var me=(you>=0&&roster[you])?roster[you]:null;
 document.getElementById("colorbtn").style.background=
  me?bg(me.c2&&me.c2!==me.c?[me.c,me.c2]:[me.c]):bg(selOpt());}
function sendJoin(){var o=selOpt();
 ws.send(JSON.stringify({t:"join",n:document.getElementById("name").value||"web",
 c:"#"+o[0],c2:"#"+(o[1]||o[0])}));}
function goFS(){try{var d=document;
 if(!(d.fullscreenElement||d.webkitFullscreenElement)){var el=d.documentElement;
  var p=(el.requestFullscreen||el.webkitRequestFullscreen).call(el);
  if(p&&p.catch)p.catch(function(){});}}catch(err){}}
function doJoin(){if(!ws||ws.readyState!==1)return;goFS();joined=true;sendJoin();
 document.getElementById("join").style.display="none";
 document.getElementById("game").style.display="block";updateBtn();}
function send(){if(ws&&ws.readyState===1&&joined)ws.send(JSON.stringify({t:"i",a:st.a,j:st.j?1:0,k:st.k?1:0}));}
function upd(){var a=0;if(held.left)a-=1;if(held.right)a+=1;
 if(a!==st.a||held.jump!==!!st.j||held.kick!==!!st.k){st.a=a;st.j=held.jump;st.k=held.kick;send();}}
["left","right","jump","kick"].forEach(function(k){var el=document.getElementById(k);
 function on(e){e.preventDefault();held[k]=true;el.classList.add("on");upd();}
 function off2(e){e.preventDefault();held[k]=false;el.classList.remove("on");upd();}
 el.addEventListener("pointerdown",on);el.addEventListener("pointerup",off2);
 el.addEventListener("pointercancel",off2);el.addEventListener("pointerleave",off2);});
document.getElementById("colorbtn").addEventListener("click",function(){
 if(!ws||ws.readyState!==1||!joined||opts.length===0)return;
 var o=opts[cycleIdx%opts.length];cycleIdx++;
 ws.send(JSON.stringify({t:"c",c:"#"+o[0],c2:"#"+(o[1]||o[0])}));});
document.getElementById("fs").addEventListener("click",function(){
 try{var d=document;
  if(d.fullscreenElement||d.webkitFullscreenElement){
   (d.exitFullscreen||d.webkitExitFullscreen).call(d);}
  else goFS();
 }catch(err){}});
setInterval(send,2000);
function buildTerrain(){off=document.createElement("canvas");off.width=W;off.height=H;
 octx=off.getContext("2d");
 for(var r=0;r<H;r++)for(var c=0;c<W;c++){var v=grid[r*W+c];if(!v)continue;
  octx.fillStyle=(Math.random()<0.3)?CELL2[v]:CELL[v];octx.fillRect(c,r,1,1);}}
function carve(x,y,rad){if(!grid)return;
 var c0=Math.floor(x/TS),r0=Math.floor(y/TS),rr=Math.ceil(rad/TS);
 for(var r=r0-rr;r<=r0+rr;r++)for(var c=c0-rr;c<=c0+rr;c++){
  if(r<0||r>=H||c<0||c>=W)continue;var v=grid[r*W+c];if(v===0||v===2)continue;
  var dx=(c+0.5)*TS-x,dy=(r+0.5)*TS-y;
  if(dx*dx+dy*dy<=rad*rad){grid[r*W+c]=0;octx.clearRect(c,r,1,1);}}}
function burst(x,y,col){for(var i=0;i<10;i++)sparks.push({x:x,y:y,c:col,
 vx:(Math.random()-0.5)*260,vy:-Math.random()*260-40,t:performance.now()});}
function shade(hex,f){hex=hex.replace("#","");
 var r=parseInt(hex.substr(0,2),16),g=parseInt(hex.substr(2,2),16),b=parseInt(hex.substr(4,2),16);
 r=Math.min(255,r*f|0);g=Math.min(255,g*f|0);b=Math.min(255,b*f|0);
 return "rgb("+r+","+g+","+b+")";}
function lerpP(i){if(!sc)return null;var cur=sc.p[i];if(!cur)return null;
 if(!sp||!sp.p[i])return{x:cur[0],y:cur[1]};
 var dt=tc-tp;var a=dt>0?Math.min((performance.now()-tc)/dt,1.3):1;
 return{x:sp.p[i][0]+(cur[0]-sp.p[i][0])*a,y:sp.p[i][1]+(cur[1]-sp.p[i][1])*a};}
function drawGuy(x,y,col,col2){ctx.fillStyle="#000";ctx.fillRect(x-7,y-18,14,33);
 ctx.fillStyle=shade(col,0.6);ctx.fillRect(x-5,y+3,4,11);ctx.fillRect(x+1,y+3,4,11);
 ctx.fillStyle=col;ctx.fillRect(x-6,y-7,12,10);
 if(col2&&col2!==col){ctx.fillStyle=col2;
  ctx.fillRect(x-6,y-5,12,2.5);ctx.fillRect(x-6,y-0.5,12,2.5);}
 ctx.fillStyle=shade(col,1.35);ctx.fillRect(x-5,y-15,10,9);
 ctx.fillStyle=shade(col,1.15);ctx.fillRect(x-6,y-17,12,4);
 ctx.fillStyle="#fff";ctx.fillRect(x-3,y-12,2,3);ctx.fillRect(x+1,y-12,2,3);}
function render(){requestAnimationFrame(render);
 var dpr=window.devicePixelRatio||1,cw=cv.clientWidth,ch=cv.clientHeight;
 if(cv.width!==cw*dpr||cv.height!==ch*dpr){cv.width=cw*dpr;cv.height=ch*dpr;}
 ctx.setTransform(dpr,0,0,dpr,0,0);
 ctx.fillStyle="#8ecae6";ctx.fillRect(0,0,cw,ch);
 if(!grid){ctx.fillStyle="#fff";ctx.font="16px sans-serif";ctx.textAlign="center";
  ctx.fillText("waiting for game…",cw/2,ch/2);return;}
 var me=you>=0?lerpP(you):null;
 if(me){cam.x+=(me.x-cam.x)*0.12;cam.y+=(me.y-cam.y)*0.12;}
 var zoom=Math.max(cw,ch)/760;var vw=cw/zoom,vh=ch/zoom;
 cam.x=Math.max(vw/2,Math.min(W*TS-vw/2,cam.x));
 cam.y=Math.max(vh/2-350,Math.min(H*TS-vh/2,cam.y));
 ctx.save();ctx.translate(cw/2,ch/2);ctx.scale(zoom,zoom);ctx.translate(-cam.x,-cam.y);
 ctx.imageSmoothingEnabled=false;
 ctx.fillStyle="#17100a";ctx.fillRect(0,SURF*TS,W*TS,(H-SURF)*TS);
 ctx.drawImage(off,0,0,W,H,0,0,W*TS,H*TS);
 for(var fx=3*TS,k=0;fx<(W-3)*TS;fx+=8,k++){
  ctx.fillStyle=(k%2===0)?"#ffd54f":"#1a1a1a";ctx.fillRect(fx,FIN,8,14);}
 var now=performance.now();
 if(sc)for(var i=0;i<sc.b.length;i++){var b=sc.b[i];
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.beginPath();ctx.arc(b[0],b[1],b[4]+1.5,0,7);ctx.fill();
  var blink=b[3]<12&&(now/100|0)%2===0;
  ctx.fillStyle=blink?"#ff5936":BOMB[b[2]]||"#212126";
  ctx.beginPath();ctx.arc(b[0],b[1],b[4],0,7);ctx.fill();
  ctx.fillStyle="rgba(255,255,255,.2)";ctx.beginPath();ctx.arc(b[0]-b[4]/3,b[1]-b[4]/3,b[4]/4,0,7);ctx.fill();
  ctx.fillStyle=b[3]<12?"#ff5936":"#fff";ctx.font="bold 11px sans-serif";ctx.textAlign="center";
  ctx.fillText((b[3]/10).toFixed(1),b[0],b[1]-b[4]-6);}
 if(sc)for(var i=0;i<sc.p.length;i++){var p=sc.p[i];if(!p||p[2]===0)continue;
  var pos=lerpP(i);var col="#"+(roster[i]?roster[i].c:"ffffff");
  var col2=roster[i]&&roster[i].c2?"#"+roster[i].c2:col;
  drawGuy(pos.x,pos.y,col,col2);
  if(i===you){ctx.fillStyle="#fff";ctx.beginPath();
   ctx.moveTo(pos.x,pos.y-26);ctx.lineTo(pos.x-5,y0(pos.y));ctx.lineTo(pos.x+5,y0(pos.y));ctx.fill();}}
 for(var i=flashes.length-1;i>=0;i--){var f=flashes[i];var a=(now-f.t)/400;
  if(a>=1){flashes.splice(i,1);continue;}
  ctx.fillStyle="rgba(255,220,120,"+(0.7*(1-a))+")";
  ctx.beginPath();ctx.arc(f.x,f.y,f.r*(0.5+0.7*a),0,7);ctx.fill();}
 for(var i=sparks.length-1;i>=0;i--){var s=sparks[i];var a=(now-s.t)/600;
  if(a>=1){sparks.splice(i,1);continue;}
  var sx=s.x+s.vx*a*0.6,sy=s.y+s.vy*a*0.6+320*a*a*0.6;
  ctx.fillStyle=s.c.startsWith("#")?s.c:"#"+s.c;ctx.globalAlpha=1-a;
  ctx.fillRect(sx-2,sy-2,4,4);ctx.globalAlpha=1;}
 ctx.restore();
 ctx.textAlign="left";ctx.font="12px sans-serif";
 for(var i=0;i<roster.length;i++){ctx.fillStyle="#"+roster[i].c;
  ctx.fillText(roster[i].n,10,18+i*15);}
 ctx.textAlign="center";
 if(sc&&you>=0&&sc.p[you]&&sc.p[you][2]===0){
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.fillRect(cw/2-110,ch*0.35-24,220,36);
  ctx.fillStyle="#ff8a80";ctx.font="bold 18px sans-serif";
  ctx.fillText("respawn in "+(sc.p[you][3]/10).toFixed(1),cw/2,ch*0.35);}
 if(win){ctx.fillStyle="rgba(0,0,0,.6)";ctx.fillRect(0,ch*0.3,cw,90);
  ctx.fillStyle="#"+win.c;ctx.font="bold 26px sans-serif";
  ctx.fillText(win.n.toUpperCase()+" WINS!",cw/2,ch*0.3+38);
  ctx.fillStyle="#ddd";ctx.font="14px sans-serif";
  ctx.fillText("waiting for host rematch…",cw/2,ch*0.3+66);}}
function y0(py){return py-20;}
connect();render();
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
			"pending_init": false, "pending_colors": true,
			"name": "", "color": Color("ff8f2e"), "color2": Color("ff8f2e"),
			"axis": 0.0, "jump": false, "kick": false,
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


## Send one message to one client (if open).
func send_to(id: int, msg: Dictionary) -> void:
	if not clients.has(id):
		return
	var c: Dictionary = clients[id]
	if not c.connected:
		return
	var ws: WebSocketPeer = c.ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))


## Send one message to every joined, connected client.
func broadcast(msg: Dictionary) -> void:
	var s := JSON.stringify(msg)
	for id in clients:
		var c: Dictionary = clients[id]
		if not c.joined or not c.connected:
			continue
		var ws: WebSocketPeer = c.ws
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(s)


## Like broadcast, but also reaches connected clients that haven't joined
## yet (the join screen needs live color availability).
func broadcast_all(msg: Dictionary) -> void:
	var s := JSON.stringify(msg)
	for id in clients:
		var c: Dictionary = clients[id]
		if not c.connected:
			continue
		var ws: WebSocketPeer = c.ws
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(s)


## True if anyone is watching (drives the snapshot stream).
func has_viewers() -> bool:
	for id in clients:
		var c: Dictionary = clients[id]
		if c.joined and c.connected:
			return true
	return false


func _handle(c: Dictionary, msg: Dictionary) -> void:
	match str(msg.get("t", "")):
		"join":
			c.joined = true
			c.pending_init = true
			c.name = str(msg.get("n", "web")).strip_edges().left(10)
			if c.name.is_empty():
				c.name = "web"
			c.color = Color.from_string(str(msg.get("c", "")), Color("ff8f2e"))
			c.color2 = Color.from_string(str(msg.get("c2", "")), c.color)
		"i":
			c.axis = clampf(float(msg.get("a", 0)), -1.0, 1.0)
			c.jump = int(msg.get("j", 0)) != 0
			c.kick = int(msg.get("k", 0)) != 0
		"c":
			c.color = Color.from_string(str(msg.get("c", "")), c.color)
			c.color2 = Color.from_string(str(msg.get("c2", "")), c.color)
