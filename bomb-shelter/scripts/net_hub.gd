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

const BEACON_PORT := 8930

## Web app manifest so the join page installs as a standalone home-screen app.
const MANIFEST := """{"name":"Bomb Shelter","short_name":"Bomb Shelter",
"display":"standalone","orientation":"portrait","background_color":"#17100a",
"theme_color":"#17100a","start_url":"/","icons":[
{"src":"/icon.png","sizes":"192x192","type":"image/png"},
{"src":"/icon.png","sizes":"512x512","type":"image/png"}]}"""

## Internet relay (Cloudflare Worker, see bomb-shelter/relay/). Empty until
## deployed: paste the workers.dev hostname here to enable online rooms.
const RELAY_HOST := ""

## Relay client ids live far above LAN ids so the two can share `clients`.
const RELAY_ID_BASE := 100000

signal relay_ready(code: String)

var http_port := 0
var ws_port := 0
var _icon_png := PackedByteArray()

## Online room state: an outbound WebSocket to the relay carrying enveloped
## guest traffic ({c,ev}/{c,m} in, {c,m}/{b,m} out).
var relay_code := ""
var _relay_ws: WebSocketPeer = null
var _relay_wanted := false
var _relay_retry := 0.0
## When true (hosting), broadcast a discovery beacon so other phones'
## "Join LAN game" screens can find this match.
var advertising := false
## id -> {ws, joined, connected, name, color, axis, jump}
var clients := {}

var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0

var _http := TCPServer.new()
var _wss := TCPServer.new()
var _pending: Array[Dictionary] = []
var _next_id := 1

const PAGE := """<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
<title>Bomb Shelter</title>
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<meta name="apple-mobile-web-app-title" content="Bomb Shelter">
<meta name="theme-color" content="#17100a">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="icon" href="/icon.png">
<link rel="manifest" href="/manifest.json">
<style>
*{margin:0;padding:0;box-sizing:border-box;-webkit-user-select:none;user-select:none;touch-action:none}
html,body{width:100%;height:100%;overflow:hidden}
body{background:#17100a;color:#eee;font-family:sans-serif;position:fixed;top:0;left:0;right:0;bottom:0}
#join{display:flex;flex-direction:column;gap:14px;padding:26px;max-width:420px;margin:auto;width:100%;height:100%;justify-content:center;overflow:auto}
h1{font-size:22px;color:#ffca28;text-align:center}
input[type=text]{font-size:18px;padding:10px;border-radius:8px;border:1px solid #555;background:#222;color:#eee}
#swatches{display:flex;flex-wrap:wrap;justify-content:center}
.sw{width:42px;height:42px;border-radius:50%;margin:5px;border:3px solid transparent}
.sw.sel{border-color:#fff}
.sw.dis{opacity:.22}
button{font-size:20px;padding:14px;border-radius:10px;border:none;background:#ffca28;color:#000;font-weight:bold}
#joinfs{background:#2a2118;color:#eee;border:1px solid #5a4a2e;font-size:17px}
#status{text-align:center;padding:8px;color:#9ccc65;font-size:14px}
#game{display:none;position:fixed;top:0;left:0;right:0;bottom:0}
canvas{position:absolute;top:0;left:0;display:block;touch-action:none}
.pad{position:absolute;width:88px;height:88px;border-radius:50%;touch-action:none;
background:rgba(255,255,255,.14);border:2px solid rgba(255,255,255,.35);
display:flex;align-items:center;justify-content:center;font-size:30px;color:rgba(255,255,255,.85)}
.pad.on{background:rgba(255,255,255,.35)}
#swap{position:absolute;width:36px;height:36px;border-radius:50%;background:rgba(0,0,0,.35);
border:1px solid rgba(255,255,255,.4);color:#fff;display:flex;align-items:center;justify-content:center;font-size:19px}
#colorbtn{position:absolute;top:calc(8px + env(safe-area-inset-top));right:calc(10px + env(safe-area-inset-right));width:38px;height:38px;border-radius:50%;border:2px solid rgba(255,255,255,.6)}
#fs{position:absolute;top:calc(8px + env(safe-area-inset-top));right:calc(58px + env(safe-area-inset-right));width:44px;height:44px;border-radius:10px;
background:rgba(0,0,0,.45);border:2px solid rgba(255,255,255,.7);
display:flex;align-items:center;justify-content:center;font-size:26px;color:#fff}
</style></head><body>
<div id="join"><h1>BOMB SHELTER</h1>
<input id="name" type="text" maxlength="10" placeholder="Your name">
<div id="swatches"></div>
<button onclick="doJoin()">JOIN GAME</button>
<button id="joinfs" onclick="goFS()">&#x26F6; Fullscreen</button>
<div id="status">connecting…</div>
<div id="a2hs" style="display:none;font-size:13px;color:#9aa;text-align:center;padding:4px">
Install: tap Share then <b>Add to Home Screen</b> to play like an app.</div></div>
<div id="game"><canvas id="cv"></canvas>
<div class="pad" id="jump">&#9650;</div>
<div class="pad" id="kick" style="font-size:21px">KICK</div>
<div id="swap">&#x21C4;</div>
<div id="colorbtn"></div><div id="fs">&#x26F6;</div></div>
<script>
var ws=null,joined=false,st={a:0,j:0,k:0};
// Gesture input: AXV = analog move axis, JHELD = jump held (both fed by the
// invisible thumb-joystick + tap gestures below).
var AXV=0,JHELD=false,moveT=null,kickT=null,gestT=null,btnKickT=null,joinT=0,scrZoom=1;
// Jump/kick buttons: right side by default, swappable per device.
var padLeft=false;try{padLeft=localStorage.getItem("padside")==="L";}catch(e){}
function applySide(){
 var b="calc(90px + env(safe-area-inset-bottom))",b2="calc(150px + env(safe-area-inset-bottom))",b3="calc(265px + env(safe-area-inset-bottom))";
 var j=document.getElementById("jump"),k=document.getElementById("kick"),s=document.getElementById("swap");
 j.style.bottom=b;k.style.bottom=b2;s.style.bottom=b3;
 var els=[[j,"14px"],[k,"116px"],[s,"78px"]];
 els.forEach(function(p){p[0].style.left="";p[0].style.right="";
  p[0].style[padLeft?"left":"right"]=p[1];});}
var W=0,H=0,TS=16,SURF=20,FIN=0,grid=null,off=null,octx=null;
var roster=[],you=-1,sp=null,sc=null,tp=0,tc=0,flashes=[],sparks=[],win=null;
var opts=[],selKey=null,cycleIdx=0;
var CELL=["","#7a5230","#4b4b55","#4caf50","#2e6bc9","#a5623b","#6e7681","#553f4d"];
var CELL2=["","#5c3d22","#3a3a44","#3f9143","#2a60b5","#874e2e","#59616b","#42313c"];
var ROOMS=[];var ROOMTINT=["#54381f","#e4d3ac","#aebccd","#dcebec","#6a6f76"];
var SCORCH={};var PIPE=null;var PIPESC={};var PIPEBRK={};var WTRANS={};var HUDMSG="";var HTIME=-1;
var grassCells=null;var anim={};
// Locally-simulated bombs: velocity estimated from snapshots, integrated
// with gravity + terrain every frame, error-corrected toward host truth.
// Bombs render at 60fps and react to your kicks instantly instead of
// waiting a round-trip.
var bsim=[];
var BOMB=["#212126","#131318","#733f17","#1f5c2e","#80247f","#2952c7","#61656f","#33353d"];
var cam={x:800,y:300},cv=document.getElementById("cv"),ctx=cv.getContext("2d");
var VW=0,VH=0,DPR=1;
// --- Web Audio: procedural SFX so the web view sounds like the native app ---
var AC=null;
function initAudio(){try{AC=new (window.AudioContext||window.webkitAudioContext)();}catch(e){}}
function noiseBuf(dur){var n=Math.floor(AC.sampleRate*dur),b=AC.createBuffer(1,n,AC.sampleRate),d=b.getChannelData(0);
 for(var i=0;i<n;i++)d[i]=Math.random()*2-1;return b;}
function boom(vol){if(!AC)return;var t=AC.currentTime;
 var s=AC.createBufferSource();s.buffer=noiseBuf(0.55);
 var lp=AC.createBiquadFilter();lp.type="lowpass";lp.frequency.setValueAtTime(500,t);
 lp.frequency.exponentialRampToValueAtTime(60,t+0.4);
 var g=AC.createGain();g.gain.setValueAtTime(vol,t);g.gain.exponentialRampToValueAtTime(0.001,t+0.55);
 s.connect(lp);lp.connect(g);g.connect(AC.destination);s.start(t);s.stop(t+0.55);
 var o=AC.createOscillator();o.frequency.setValueAtTime(90,t);o.frequency.exponentialRampToValueAtTime(30,t+0.3);
 var g2=AC.createGain();g2.gain.setValueAtTime(vol*0.9,t);g2.gain.exponentialRampToValueAtTime(0.001,t+0.35);
 o.connect(g2);g2.connect(AC.destination);o.start(t);o.stop(t+0.35);}
function splat(){if(!AC)return;var t=AC.currentTime;
 var s=AC.createBufferSource();s.buffer=noiseBuf(0.25);
 var lp=AC.createBiquadFilter();lp.type="lowpass";lp.frequency.setValueAtTime(900,t);
 lp.frequency.exponentialRampToValueAtTime(120,t+0.2);
 var g=AC.createGain();g.gain.setValueAtTime(0.5,t);g.gain.exponentialRampToValueAtTime(0.001,t+0.25);
 s.connect(lp);lp.connect(g);g.connect(AC.destination);s.start(t);s.stop(t+0.25);}
function tone(freq,start,dur,vol){if(!AC)return;var t=AC.currentTime+start;
 var o=AC.createOscillator();o.type="triangle";o.frequency.value=freq;
 var g=AC.createGain();g.gain.setValueAtTime(0.0001,t);g.gain.linearRampToValueAtTime(vol,t+0.02);
 g.gain.exponentialRampToValueAtTime(0.0001,t+dur);
 o.connect(g);g.connect(AC.destination);o.start(t);o.stop(t+dur);}
function fanfare(){if(!AC)return;[523.25,659.25,784.0,1046.5].forEach(function(f,i){
 tone(f,i*0.16,i===3?0.6:0.2,0.28);});}
function crunch(vol,pitch){if(!AC)return;var t=AC.currentTime;
 var s=AC.createBufferSource();s.buffer=noiseBuf(0.06);s.playbackRate.value=pitch||1;
 var hp=AC.createBiquadFilter();hp.type="highpass";hp.frequency.value=800;
 var g=AC.createGain();g.gain.setValueAtTime(vol,t);g.gain.exponentialRampToValueAtTime(0.001,t+0.07);
 s.connect(hp);hp.connect(g);g.connect(AC.destination);s.start(t);s.stop(t+0.08);}
// Generic host fx events: one table row per effect kind = parity for free.
// 0 jump 1 kick 2 land 3 step 4 snap 5 armor 6 pickup 8 spray 9 dust
// 11 plank debris 12 critter death 13 gunshot.
function puffAt(x,y,col,n,spd){for(var i=0;i<n;i++)sparks.push({x:x,y:y,c:col,
 vx:(Math.random()-0.5)*spd*2,vy:-Math.random()*spd,t:performance.now()});}
function fxPlay(m){var k=m.k,x=m.x,y=m.y;
 if(k===0){tone(620,0,0.1,0.14);puffAt(x,y+10,"#a1866a",3,80);}
 else if(k===1)tone(170,0,0.16,0.24);
 else if(k===2){crunch(0.28,0.6);puffAt(x,y+10,"#a1866a",5,100);}
 else if(k===3)crunch(0.09,1.1);
 else if(k===4)tone(1250,0,0.05,0.13);
 else if(k===5){tone(330,0,0.22,0.28);tone(215,0.07,0.3,0.26);}
 else if(k===6){tone(540,0,0.09,0.2);tone(810,0.09,0.12,0.2);}
 else if(k===8){var n=m.a||10;for(var i=0;i<n;i++)sparks.push({x:x,y:y,c:"#7fd4ff",
  vx:(m.dx||0)*170+(Math.random()-0.5)*90,vy:(m.dy||-1)*170+(Math.random()-0.5)*70,
  t:performance.now()});}
 else if(k===9)puffAt(x,y,m.c||"#a1866a",m.a||6,110);
 else if(k===11){crunch(0.4,0.5);puffAt(x,y,"#6d4c2f",12,190);}
 else if(k===12){splat();puffAt(x,y,m.c==="p"?"#f4a7b9":"#f5f5f0",10,160);}
 else if(k===13){crunch(0.5,1.7);tone(75,0,0.12,0.3);puffAt(x,y,"#ffe082",4,130);}
 else if(k===17){if(RIPPLES.length<24)RIPPLES.push({x:x,y:y,p:m.p||0.5,t:performance.now()});}}
// Size the canvas from the *visual* viewport in real pixels. CSS 100vh/100%
// is unreliable on iOS Safari (collapsing URL bar, stale post-rotation
// layout) and produced a broken "slice" — this is the robust fix.
function fit(){
 var vv=window.visualViewport;
 VW=Math.round(vv?vv.width:window.innerWidth);
 VH=Math.round(vv?vv.height:window.innerHeight);
 DPR=window.devicePixelRatio||1;
 cv.style.width=VW+"px";cv.style.height=VH+"px";
 cv.width=Math.round(VW*DPR);cv.height=Math.round(VH*DPR);
}
window.addEventListener("resize",fit);
window.addEventListener("orientationchange",function(){setTimeout(fit,250);});
if(window.visualViewport)window.visualViewport.addEventListener("resize",fit);
// LAN serving fills this with ws://HOSTNAME:port; the internet relay fills
// it with its own wss://... room URL. HOSTNAME resolves at load time.
var WSURL="__WSURL__".replace("HOSTNAME",location.hostname);
function connect(){
 ws=new WebSocket(WSURL);
 ws.onopen=function(){document.getElementById("status").textContent="ready — pick a name and join";
  if(joined)sendJoin();};
 ws.onclose=function(){document.getElementById("status").textContent="reconnecting…";setTimeout(connect,1500);};
 ws.onmessage=function(ev){var m=JSON.parse(ev.data);
  if(m.t==="s"){
   if(sc)for(var i=0;i<sc.p.length&&i<m.p.length;i++)
    if(sc.p[i][2]===1&&m.p[i][2]===0){var dc="#"+(roster[i]?roster[i].c:"ffffff");
     burst(m.p[i][0],m.p[i][1],roster[i]?roster[i].c:"fff");splat();
     var da=anim[i]||{};spawnRag(m.p[i][0],m.p[i][1],dc,
      Math.max(-500,Math.min(500,da.vx||0)),Math.max(-500,Math.min(500,da.vy||-160)));}
   sp=sc;tp=tc;sc=m;tc=performance.now();reconcile();syncBombs(m);}
  else if(m.t==="carve"){carve(m.x,m.y,m.r);flashes.push({x:m.x,y:m.y,r:m.r,t:performance.now()});
   boom(Math.min(0.55,0.2+m.r/240));}
  else if(m.t==="w"){if(grid){var nt={};
   // Neighbor repaint: land chamfers, water wedges and empty-cell fills
   // all depend on what sits beside a changed cell.
   var pcN=function(ii){var rr4=(ii/W)|0,cc4=ii%W;
    if(rr4>0)paintCell(rr4-1,cc4);if(rr4<H-1)paintCell(rr4+1,cc4);
    if(cc4>0)paintCell(rr4,cc4-1);if(cc4<W-1)paintCell(rr4,cc4+1);};
   var mm=m.m||[];for(var i=0;i<mm.length;i++){var f=mm[i][0],t2=mm[i][1];
    // Traveling water splashes like the well spray: a couple of falling
    // droplet sparks flung from the cell toward where it's headed.
    if(f>=0&&f<grid.length&&sparks.length<260){
     var fx2=(f%W)*TS+TS/2,fy2=((f/W)|0)*TS+TS/2;
     var tx2=t2>=0?(t2%W)*TS+TS/2:fx2,ty2=t2>=0?((t2/W)|0)*TS+TS/2:fy2+TS;
     var ddx=tx2-fx2,ddy=ty2-fy2,dl=Math.hypot(ddx,ddy)||1;
     for(var si2=0;si2<2;si2++)sparks.push({x:fx2+(Math.random()-0.5)*8,
      y:fy2+(Math.random()-0.5)*8,c:"#7fd4ff",
      vx:ddx/dl*95+(Math.random()-0.5)*60,vy:ddy/dl*95-Math.random()*40,
      t:performance.now()});}
    if(f>=0&&f<grid.length){grid[f]=0;paintCell((f/W)|0,f%W);pcN(f);}
    if(t2>=0&&t2<grid.length){grid[t2]=4;nt[t2]=1;paintCell((t2/W)|0,t2%W);pcN(t2);}}
   var qq=m.q||[];for(var i=0;i<qq.length;i++){var f=qq[i][0],t2=qq[i][1];
    if(f>=0&&f<grid.length){grid[f]=0;paintCell((f/W)|0,f%W);pcN(f);}
    if(t2>=0&&t2<grid.length){grid[t2]=4;paintCell((t2/W)|0,t2%W);pcN(t2);}}
   WTRANS=nt;}}
  else if(m.t==="init"){W=m.w;H=m.h;TS=m.ts;SURF=m.surf;FIN=m.fin;ROOMS=m.rooms||[];PIPE=m.pipe||null;
   grid=new Uint8Array(m.grid.length);
   for(var i=0;i<m.grid.length;i++)grid[i]=m.grid.charCodeAt(i)-48;
   TSCORCH={};buildTerrain();sp=sc=null;flashes=[];sparks=[];win=null;anim={};bsim=[];rags=[];SCORCH={};PIPESC={};PIPEBRK={};WTRANS={};HUDMSG="";HTIME=-1;predOK=false;}
  else if(m.t==="roster"){roster=m.p;updateBtn();}
  else if(m.t==="you"){you=m.i;updateBtn();}
  else if(m.t==="colors"){opts=m.opts;
   if(!joined){if(!selKey||!opts.some(function(o){return key(o)===selKey;}))
    selKey=opts.length?key(opts[0]):null;
   renderSw();}}
  else if(m.t==="fx"){fxPlay(m);}
  else if(m.t==="hud"){HUDMSG=m.m||"";HTIME=(m.tm!=null)?m.tm:-1;}
  else if(m.t==="win"){win=m;fanfare();}};
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
function doJoin(){if(!ws||ws.readyState!==1)return;goFS();joined=true;joinT=performance.now();sendJoin();
 if(!AC)initAudio();
 if(AC&&AC.state==="suspended"){var pr=AC.resume();if(pr&&pr.catch)pr.catch(function(){});}
 document.getElementById("join").style.display="none";
 document.getElementById("game").style.display="block";updateBtn();
 fit();setTimeout(fit,150);setTimeout(fit,600);}
function send(){if(ws&&ws.readyState===1&&joined)ws.send(JSON.stringify({t:"i",a:st.a,j:st.j?1:0,k:0}));}
function upd(){var a=Math.round(AXV*100)/100;
 if(a!==st.a||JHELD!==!!st.j){st.a=a;st.j=JHELD;send();}}
// --- Invisible joystick + tap-jump + press-your-character charged kick ---
function myScreen(){if(you<0||!sc||!sc.p[you]||sc.p[you][2]!==1)return null;
 var m=(predOK)?{x:PX,y:PY}:lerpP(you);
 return{x:(m.x-cam.x)*scrZoom+VW/2,y:(m.y-cam.y)*scrZoom+VH/2};}
function jumpPulse(){JHELD=true;upd();setTimeout(function(){JHELD=false;upd();},90);}
function mkTouch(e){return{id:e.pointerId,ox:e.clientX,oy:e.clientY,x:e.clientX,y:e.clientY,t0:performance.now(),jarm:true};}
var lastTap={t:-1e9,x:0,y:0};
// A tap jumps; a second tap within 300ms fires an instant full-power kick
// in the facing direction. Enables one-thumb jump-kick play.
function sendKick(dx,dy,p){
 if(ws&&ws.readyState===1&&joined)
  KANIM=performance.now();
  ws.send(JSON.stringify({t:"k",dx:Math.round(dx*100)/100,dy:Math.round(dy*100)/100,p:p}));
 predictKick(dx,dy,p);}
function tap(x,y){var now=performance.now();
 if(now-lastTap.t<300&&Math.hypot(x-lastTap.x,y-lastTap.y)<60){
  lastTap.t=-1e9;
  var f=(anim[you]&&anim[you].face)||1;
  sendKick(f*0.707,-0.707,1);
  return;}
 lastTap={t:now,x:x,y:y};jumpPulse();}
cv.addEventListener("pointerdown",function(e){e.preventDefault();
 if(!joined||!grid)return;
 var ms=myScreen();
 if(ms&&!kickT&&!gestT&&Math.hypot(e.clientX-ms.x,e.clientY-ms.y)<52){
  kickT=mkTouch(e);return;}
 if(!moveT)moveT=mkTouch(e);
 // Second finger while the joystick is held: tap = jump, swipe = kick.
 else if(!gestT)gestT=mkTouch(e);});
cv.addEventListener("pointermove",function(e){e.preventDefault();
 if(moveT&&e.pointerId===moveT.id){moveT.x=e.clientX;moveT.y=e.clientY;
  var dx=moveT.x-moveT.ox;
  AXV=Math.abs(dx)<8?0:Math.max(-1,Math.min(1,dx/44));upd();
  // One-thumb jump: push the stick up; re-arms when it drops back.
  var dy=moveT.y-moveT.oy;
  if(moveT.jarm&&dy<-45){moveT.jarm=false;jumpPulse();}
  else if(dy>-25)moveT.jarm=true;}
 else if(kickT&&e.pointerId===kickT.id){kickT.x=e.clientX;kickT.y=e.clientY;}
 else if(gestT&&e.pointerId===gestT.id){gestT.x=e.clientX;gestT.y=e.clientY;}});
function tapOrKick(t){var dx=t.x-t.ox,dy=t.y-t.oy,d=Math.hypot(dx,dy);
 var held=performance.now()-t.t0;
 if(d<12){if(held<220)tap(t.x,t.y);return;}
 sendKick(dx/d,dy/d,Math.round(Math.max(0.25,Math.min(1,d/90))*100)/100);}
function endPtr(e){
 if(moveT&&e.pointerId===moveT.id){
  var quick=performance.now()-moveT.t0<220&&Math.hypot(moveT.x-moveT.ox,moveT.y-moveT.oy)<12;
  var tx=moveT.x,ty=moveT.y;moveT=null;AXV=0;upd();if(quick)tap(tx,ty);}
 else if(kickT&&e.pointerId===kickT.id){var t=kickT;kickT=null;tapOrKick(t);}
 else if(gestT&&e.pointerId===gestT.id){var t=gestT;gestT=null;tapOrKick(t);}}
cv.addEventListener("pointerup",endPtr);cv.addEventListener("pointercancel",endPtr);
// Jump button: hold for a higher jump. Kick button: tap = instant preset
// kick in the facing direction; hold + pull = aimed charged kick.
(function(){var j=document.getElementById("jump"),k=document.getElementById("kick");
 function jd(e){e.preventDefault();JHELD=true;upd();j.classList.add("on");}
 function ju(e){e.preventDefault();JHELD=false;upd();j.classList.remove("on");}
 j.addEventListener("pointerdown",jd);j.addEventListener("pointerup",ju);
 j.addEventListener("pointercancel",ju);
 k.addEventListener("pointerdown",function(e){e.preventDefault();
  btnKickT=mkTouch(e);k.classList.add("on");});
 k.addEventListener("pointermove",function(e){
  if(btnKickT&&e.pointerId===btnKickT.id){btnKickT.x=e.clientX;btnKickT.y=e.clientY;}});
 function ku(e){e.preventDefault();k.classList.remove("on");
  if(!btnKickT||e.pointerId!==btnKickT.id)return;
  var t=btnKickT;btnKickT=null;
  var dx=t.x-t.ox,dy=t.y-t.oy,d=Math.hypot(dx,dy);
  if(d<12){var f=(anim[you]&&anim[you].face)||1;sendKick(f*0.707,-0.707,1);}
  else sendKick(dx/d,dy/d,Math.round(Math.max(0.25,Math.min(1,d/90))*100)/100);}
 k.addEventListener("pointerup",ku);k.addEventListener("pointercancel",ku);
 document.getElementById("swap").addEventListener("click",function(){
  padLeft=!padLeft;try{localStorage.setItem("padside",padLeft?"L":"R");}catch(err){}
  applySide();});
 applySide();})();
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
// Offscreen pixels per cell: room to chamfer corners (3 subpx = 6 world px).
var PXC=8;var TSCORCH={};var RIPPLES=[];var KANIM=0;
function openC(r,c){if(r<0||r>=H||c<0||c>=W)return false;var v=grid[r*W+c];return v===0||v===4;}
// (Re)paint one cell: deterministic light/dark speckle, blast-scorch
// darkening (25%), 45-degree chamfered corners wherever both adjacent
// sides are open, and anti-bevel fills in empty inside corners — matches
// the native tiles.
function paintCell(r,c){var i=r*W+c,v=grid[i];
 octx.clearRect(c*PXC,r*PXC,PXC,PXC);
 if(v===4)return;// water renders live each frame (merged liquid body)
 if(!v){
  // Anti-bevel: where two solid sides meet at a corner, fill the wedge so
  // the neighbors' chamfers join into one continuous slant. Chips inside
  // blast range char to 50% like the blocks around them.
  var fu=!openC(r-1,c),fd2=!openC(r+1,c),fl=!openC(r,c-1),fr2=!openC(r,c+1);
  if(!((fu||fd2)&&(fl||fr2)))return;
  var sc2=TSCORCH[i];
  var colFor=function(rr2,cc2){var cf;
   if(rr2<0||rr2>=H||cc2<0||cc2>=W)cf=CELL[2];
   else{var vv=grid[rr2*W+cc2];vv=(vv===3)?1:vv;cf=CELL[vv]||CELL[1];}
   return sc2?shade(cf,0.75):cf;};
  var tri=function(a,b,c3){octx.beginPath();octx.moveTo(a[0],a[1]);
   octx.lineTo(b[0],b[1]);octx.lineTo(c3[0],c3[1]);octx.closePath();octx.fill();};
  var fb=3,fx3=c*PXC,fy3=r*PXC,fs=PXC;
  if(fu&&fl){octx.fillStyle=colFor(r-1,c);
   tri([fx3,fy3],[fx3+fb,fy3],[fx3,fy3+fb]);}
  if(fu&&fr2){octx.fillStyle=colFor(r-1,c);
   tri([fx3+fs,fy3],[fx3+fs,fy3+fb],[fx3+fs-fb,fy3]);}
  if(fd2&&fr2){octx.fillStyle=colFor(r+1,c);
   tri([fx3+fs,fy3+fs],[fx3+fs-fb,fy3+fs],[fx3+fs,fy3+fs-fb]);}
  if(fd2&&fl){octx.fillStyle=colFor(r+1,c);
   tri([fx3,fy3+fs],[fx3,fy3+fs-fb],[fx3+fb,fy3+fs]);}
  return;}
 var dv=(v===3)?1:v,hh=(i*2654435761)>>>0;
 var col=(hh%100<30)?CELL2[dv]:CELL[dv];
 octx.fillStyle=TSCORCH[i]?shade(col,0.75):col;
 var up=openC(r-1,c),dn=openC(r+1,c),lf=openC(r,c-1),rt=openC(r,c+1);
 var bd=3,bnw=up&&lf?bd:0,bne=up&&rt?bd:0,bse=dn&&rt?bd:0,bsw=dn&&lf?bd:0;
 var bx=c*PXC,by=r*PXC,s=PXC;
 octx.beginPath();
 octx.moveTo(bx+bnw,by);octx.lineTo(bx+s-bne,by);
 if(bne)octx.lineTo(bx+s,by+bne);
 octx.lineTo(bx+s,by+s-bse);
 if(bse)octx.lineTo(bx+s-bse,by+s);
 octx.lineTo(bx+bsw,by+s);
 if(bsw)octx.lineTo(bx,by+s-bsw);
 octx.lineTo(bx,by+bnw);
 octx.closePath();octx.fill();}
function buildTerrain(){off=document.createElement("canvas");off.width=W*PXC;off.height=H*PXC;
 octx=off.getContext("2d");grassCells=[];
 // Grass blocks are dirt-bodied; a thin green cap is drawn on top at render.
 for(var r=0;r<H;r++)for(var c=0;c<W;c++){paintCell(r,c);
  if(grid[r*W+c]===3)grassCells.push(r*W+c);}}
function carve(x,y,rad){if(!grid)return;
 // Well pipe: segments in the blast core break clean off (gray metal
 // sparks); near misses scorch survivors to the carved-earth brown.
 if(PIPE){var ppx=(PIPE[0]+0.5)*TS,pdx=Math.abs(ppx-x);
  if(pdx<rad*1.6+8){var pdir=pdx<=rad+4;
   var pr0=Math.max(Math.floor((y-rad*1.6)/TS),PIPE[1]),pr1=Math.min(Math.floor((y+rad*1.6)/TS),PIPE[2]);
   for(var pr=pr0;pr<=pr1;pr++){var dseg=Math.hypot(ppx-x,pr*TS+8-y);
    if(pdir&&dseg<=rad){if(!PIPEBRK[pr]){PIPEBRK[pr]=1;delete PIPESC[pr];
     if(sparks.length<280)for(var pb=0;pb<2;pb++)sparks.push({x:ppx,y:pr*TS+8,
      c:"#41525f",vx:(Math.random()-0.5)*220,vy:-Math.random()*200,t:performance.now()});}}
    else if(dseg<=rad*1.6&&!PIPEBRK[pr])PIPESC[pr]=1;}}}
 var c0=Math.floor(x/TS),r0=Math.floor(y/TS),rr=Math.ceil(rad/TS);
 for(var r=r0-rr;r<=r0+rr;r++)for(var c=c0-rr;c<=c0+rr;c++){
  if(r<0||r>=H||c<0||c>=W)continue;
  var dx=(c+0.5)*TS-x,dy=(r+0.5)*TS-y;
  if(dx*dx+dy*dy>rad*rad)continue;
  // Wallpaper squares caught in the blast scorch 50% darker.
  for(var ri=0;ri<ROOMS.length;ri++){var q=ROOMS[ri];
   if(c>=q[0]&&c<q[0]+q[2]&&r>=q[1]&&r<q[1]+q[3]){SCORCH[r*W+c]=1;break;}}
  var v=grid[r*W+c];if(v===0||v===2)continue;
  grid[r*W+c]=0;}
 // Everything the blast touched (one tile past the carve edge) scorches
 // to 50%, permanently — empty cells included, so fill chips char too.
 var r3=rr+1;
 for(var r=r0-r3;r<=r0+r3;r++)for(var c=c0-r3;c<=c0+r3;c++){
  if(r<0||r>=H||c<0||c>=W)continue;
  if(grid[r*W+c]===4)continue;
  if(Math.hypot((c+0.5)*TS-x,(r+0.5)*TS-y)<=rad+TS)TSCORCH[r*W+c]=1;}
 // Repaint the touched region so chamfers, fills and scorch update.
 for(var r=r0-r3-1;r<=r0+r3+1;r++)for(var c=c0-r3-1;c<=c0+r3+1;c++){
  if(r<0||r>=H||c<0||c>=W)continue;paintCell(r,c);}}
function burst(x,y,col){for(var i=0;i<10;i++)sparks.push({x:x,y:y,c:col,
 vx:(Math.random()-0.5)*260,vy:-Math.random()*260-40,t:performance.now()});}
// Cosmetic death ragdolls, simulated locally: six body parts flung with the
// player's last velocity, tumbling off terrain, fading out — parity with
// the native Ragdoll rig.
var rags=[];
function spawnRag(x,y,col,vx,vy){
 var defs=[[0,-2,12,10,col],[0,-11,10,9,shade(col,1.45)],
  [-7,0,4,10,shade(col,0.85)],[7,0,4,10,shade(col,0.85)],
  [-3,9,4,12,shade(col,0.65)],[3,9,4,12,shade(col,0.65)]];
 var p=[];
 for(var j=0;j<defs.length;j++){var d=defs[j];
  p.push({x:x+d[0],y:y+d[1],w:d[2],h:d[3],c:d[4],
   vx:vx*(0.7+Math.random()*0.6)+(Math.random()-0.5)*150,
   vy:vy*(0.7+Math.random()*0.6)-Math.random()*150,
   ang:0,av:(Math.random()-0.5)*22});}
 rags.push({p:p,age:0});}
function stepRags(dt){for(var i=rags.length-1;i>=0;i--){var g=rags[i];
 g.age+=dt;if(g.age>4.5){rags.splice(i,1);continue;}
 for(var j=0;j<g.p.length;j++){var q=g.p[j];
  q.vy=Math.min(q.vy+980*dt,900);
  var nx=q.x+q.vx*dt,ny=q.y+q.vy*dt;
  if(!solidR(nx,q.y,3))q.x=nx;else q.vx*=-0.4;
  if(!solidR(q.x,ny,3))q.y=ny;
  else{if(q.vy>0){q.vy*=-0.3;q.vx*=0.72;}else q.vy=0;}
  q.ang+=q.av*dt;q.av*=Math.pow(0.5,dt);}}}
function drawRags(){for(var i=0;i<rags.length;i++){var g=rags[i];
 ctx.globalAlpha=g.age>3.2?Math.max(0,1-(g.age-3.2)/1.3):1;
 for(var j=0;j<g.p.length;j++){var q=g.p[j];
  ctx.save();ctx.translate(q.x,q.y);ctx.rotate(q.ang);
  ctx.fillStyle="#000";ctx.fillRect(-q.w/2-1,-q.h/2-1,q.w+2,q.h+2);
  ctx.fillStyle=q.c;ctx.fillRect(-q.w/2,-q.h/2,q.w,q.h);ctx.restore();}
 ctx.globalAlpha=1;}}
function shade(hex,f){hex=hex.replace("#","");
 var r=parseInt(hex.substr(0,2),16),g=parseInt(hex.substr(2,2),16),b=parseInt(hex.substr(4,2),16);
 r=Math.min(255,r*f|0);g=Math.min(255,g*f|0);b=Math.min(255,b*f|0);
 return "rgb("+r+","+g+","+b+")";}
function lerpP(i){if(!sc)return null;var cur=sc.p[i];if(!cur)return null;
 if(!sp||!sp.p[i])return{x:cur[0],y:cur[1]};
 var dt=tc-tp;var a=dt>0?Math.min((performance.now()-tc)/dt,1.3):1;
 return{x:sp.p[i][0]+(cur[0]-sp.p[i][0])*a,y:sp.p[i][1]+(cur[1]-sp.p[i][1])*a};}
// --- Client-side prediction for YOUR player: simulate locally from your own
// input against the terrain the client already has, so movement is instant;
// the host stream only nudges/reconciles it. Removes the input round-trip lag.
var PX=0,PY=0,VX=0,VY=0,onG=false,predOK=false,prevJ=false,lastT=0;
function mv(a,b,d){return Math.abs(b-a)<=d?b:a+(b>a?d:-d);}
function solidBox(cx,cy){var l=cx-6,rt=cx+6,tp=cy-12,bt=cy+12;
 var c0=Math.floor(l/TS),c1=Math.floor((rt-0.01)/TS),r0=Math.floor(tp/TS),r1=Math.floor((bt-0.01)/TS);
 for(var r=r0;r<=r1;r++)for(var c=c0;c<=c1;c++){
  if(c<0||c>=W)return true;if(r<0||r>=H)continue;
  var g=grid[r*W+c];if(g!==0&&g!==4)return true;}return false;}
function waterAt(px,py){if(!grid)return false;
 var c=Math.floor(px/TS),r=Math.floor(py/TS);
 if(c<0||c>=W||r<0||r>=H)return false;return grid[r*W+c]===4;}
function predict(dt){if(dt>0.05)dt=0.05;
 onG=solidBox(PX,PY+1);
 var steps=Math.max(1,Math.ceil(Math.max(Math.abs(VX),Math.abs(VY))*dt/6));
 var sdt=dt/steps;
 for(var s=0;s<steps;s++){
  var dir=AXV;
  var hw=waterAt(PX,PY-8),fw=waterAt(PX,PY+10);
  VX=mv(VX,dir*230*(fw?0.65:1),1900*sdt);
  if(hw)VY=mv(VY,-110,2200*sdt);
  else if(fw)VY=mv(VY,35,1500*sdt);
  else VY=Math.min(VY+980*sdt,900);
  if(JHELD&&!prevJ&&(onG||fw)){VY=fw?-300:-430;onG=false;}
  prevJ=JHELD;
  var nx=PX+VX*sdt;
  if(!solidBox(nx,PY))PX=nx;
  // Stair assist (parity with the native player): a one-tile ledge is
  // walkable — lift over it instead of stopping, taller still blocks.
  else if(onG&&Math.abs(dir)>0.2&&!solidBox(PX,PY-17)&&!solidBox(nx,PY-17)){PY-=17;PX=nx;}
  else{var sx=VX>0?1:-1;while(!solidBox(PX+sx,PY)&&(nx-PX)*sx>0)PX+=sx;VX=0;}
  var ny=PY+VY*sdt;
  if(!solidBox(PX,ny))PY=ny;
  else{var sy=VY>0?1:-1;if(VY>0)onG=true;while(!solidBox(PX,PY+sy)&&(ny-PY)*sy>0)PY+=sy;VY=0;}}}
// --- Local bomb simulation ---
// Match each snapshot bomb to a simulated one (same type, nearest), derive
// velocity from successive snapshot positions, and nudge the local pos
// toward host truth (snap on big error: an explosion moved it).
function syncBombs(m){if(!m.b){bsim=[];return;}
 var dt=Math.max((tc-tp)/1000,0.016),used={},out=[];
 for(var i=0;i<m.b.length;i++){var b=m.b[i],best=-1,bd=8100,e=null;
  for(var j=0;j<bsim.length;j++){if(used[j])continue;var s=bsim[j];
   if(s.type!==b[2])continue;
   var dx=s.sx-b[0],dy=s.sy-b[1],d2=dx*dx+dy*dy;
   if(d2<bd){bd=d2;best=j;}}
  if(best>=0){e=bsim[best];used[best]=1;
   var vx=(b[0]-e.sx)/dt,vy=(b[1]-e.sy)/dt,vm=Math.hypot(vx,vy);
   if(vm>900){vx*=900/vm;vy*=900/vm;}
   e.vx=vx;e.vy=vy;
   var ex=b[0]-e.x,ey=b[1]-e.y;
   if(ex*ex+ey*ey>4900){e.x=b[0];e.y=b[1];}
   else{e.x+=ex*0.3;e.y+=ey*0.3;}}
  else e={x:b[0],y:b[1],vx:0,vy:0};
  e.sx=b[0];e.sy=b[1];e.type=b[2];e.r=b[4];
  e.fuse=b[3]/10;e.ft=tc;e.dud=b.length>5&&b[5]===1;
  out.push(e);}
 bsim=out;}
function solidR(cx,cy,r){if(!grid)return false;
 var c0=Math.floor((cx-r)/TS),c1=Math.floor((cx+r-0.01)/TS);
 var r0=Math.floor((cy-r)/TS),r1=Math.floor((cy+r-0.01)/TS);
 for(var rr=r0;rr<=r1;rr++)for(var cc=c0;cc<=c1;cc++){
  if(cc<0||cc>=W)return true;if(rr<0||rr>=H)continue;
  var g=grid[rr*W+cc];if(g!==0&&g!==4)return true;}return false;}
function ptSolid(px,py){if(!grid)return false;
 var c=Math.floor(px/TS),r=Math.floor(py/TS);
 if(c<0||c>=W)return true;if(r<0||r>=H)return false;
 var g=grid[r*W+c];return g!==0&&g!==4;}
function stepBombs(dt){if(dt>0.05)dt=0.05;
 for(var i=0;i<bsim.length;i++){var e=bsim[i];
  var below=e.y+e.r+2;
  var rest=ptSolid(e.x,below)||ptSolid(e.x-e.r*0.6,below)||ptSolid(e.x+e.r*0.6,below);
  if(rest){e.vx*=Math.pow(0.05,dt);if(e.vy>0)e.vy=0;}
  else if(waterAt(e.x,e.y)){e.vy=Math.min(e.vy+390*dt,95);e.vx*=Math.pow(0.15,dt);}
  else e.vy=Math.min(e.vy+980*dt,900);
  var nx=e.x+e.vx*dt,ny=e.y+e.vy*dt;
  if(!solidR(nx,e.y,e.r))e.x=nx;else e.vx*=-0.3;
  if(!solidR(e.x,ny,e.r))e.y=ny;
  else{if(e.vy>0)e.vy*=-0.2;else e.vy=0;}}}
// Predicted kick: fling nearby simulated bombs the instant you swipe —
// the host snapshot corrects any difference a beat later.
function predictKick(dx,dy,p){if(!predOK)return;
 var f=(anim[you]&&anim[you].face)||1,cx=PX+f*10,cy=PY;
 for(var i=0;i<bsim.length;i++){var e=bsim[i];
  if(Math.hypot(e.x-cx,e.y-cy)<=30+e.r){e.vx=dx*430*p;e.vy=dy*430*p;}}}
function reconcile(){if(you<0||!sc||!sc.p[you])return;var hp=sc.p[you];
 if(hp[2]!==1){predOK=false;return;}
 var hx=hp[0],hy=hp[1];
 if(!predOK){PX=hx;PY=hy;VX=0;VY=0;predOK=true;return;}
 var ex=hx-PX,ey=hy-PY;
 if(ex*ex+ey*ey>3600){PX=hx;PY=hy;VX=0;VY=0;}  // snap on blast/respawn
 else{PX+=ex*0.2;PY+=ey*0.2;}}
// Animated humanoid matching the native Android character: mirrored limbs by
// facing, walk swing, and a Y-shape jump pose. All derived client-side.
function rgbOf(h){h=h.replace("#","");
 return [parseInt(h.substr(0,2),16),parseInt(h.substr(2,2),16),parseInt(h.substr(4,2),16)];}
function mul(c,f){return "rgb("+(c[0]*f|0)+","+(c[1]*f|0)+","+(c[2]*f|0)+")";}
function lw(c,f){return "rgb("+((c[0]+(255-c[0])*f)|0)+","+((c[1]+(255-c[1])*f)|0)+","+((c[2]+(255-c[2])*f)|0)+")";}
function limbW(x,y,ax,ay,ang,len,col,f){ctx.save();ctx.translate(x+ax*f,y+ay);ctx.rotate(ang*f);
 ctx.fillStyle="#000";ctx.fillRect(-3,-1,6,len+2);
 ctx.fillStyle=col;ctx.fillRect(-2,0,4,len);ctx.restore();}
function drawGuy(x,y,col,col2,armor,swing,face,air,stun,stAng,kick){
 var c=rgbOf(col),armc=mul(c,0.85),legc=mul(c,0.65);
 var ra,la,rl,ll,lx,llen=12;
 if(stun){ctx.save();ctx.translate(x,y);ctx.rotate(stAng||1.1*face);ctx.translate(-x,-y);
  var wb=Math.sin(performance.now()/95)*0.45,wb2=Math.cos(performance.now()/120)*0.4;
  ra=-2.0+wb;la=1.4+wb2;rl=-0.9-wb2;ll=0.5+wb;lx=2;}
 else if(kick){ra=-0.6;la=0.6;rl=0;ll=-0.79;lx=3;llen=14;}// support straight, kick leg 45deg
 else if(air){ra=-2.5;la=2.5;rl=0;ll=0;lx=1.5;}
 else{ra=swing;la=-swing;rl=-swing;ll=swing;lx=3;}
 limbW(x,y,5,-6,ra,10,mul(c,0.68),face);         // back arm
 limbW(x,y,lx,2,rl,12,mul(c,0.52),face);         // back leg
 if(!kick)limbW(x,y,-lx,2,ll,llen,legc,face);    // front leg
 ctx.fillStyle="#000";                            // torso/head silhouette
 ctx.fillRect(x-7,y-8,14,12);ctx.fillRect(x-6,y-16,12,11);ctx.fillRect(x-7,y-18,14,6);
 ctx.fillStyle=col;ctx.fillRect(x-6,y-7,12,10);
 if(col2&&col2!==col){ctx.fillStyle=col2;ctx.fillRect(x-6,y-5,12,2.5);ctx.fillRect(x-6,y-0.5,12,2.5);}
 if(armor){ctx.fillStyle="#d1d9e6";ctx.fillRect(x-6,y-7,12,4);ctx.fillStyle="#99a2b3";ctx.fillRect(x-6,y-3.2,12,1.2);}
 ctx.fillStyle=lw(c,0.35);ctx.fillRect(x-5,y-15,10,9);      // head
 ctx.fillStyle=lw(c,0.15);ctx.fillRect(x-6,y-17,12,4);      // hat
 var fx=face;
 ctx.fillStyle="#fff";ctx.fillRect(x-3+fx,y-12,2,3);ctx.fillRect(x+1+fx,y-12,2,3);
 ctx.fillStyle="#000";ctx.fillRect(x-2.5+fx,y-11,1,1.5);ctx.fillRect(x+1.5+fx,y-11,1,1.5);
 limbW(x,y,-5,-6,la,10,armc,face);               // front arm
 if(kick)limbW(x,y,-lx,2,ll,llen,legc,face);     // kicking leg tops the stack
 if(stun){ctx.restore();                          // dizzy stars, drawn upright
  var ph=performance.now()/180;
  ctx.fillStyle="rgba(255,255,255,.9)";
  ctx.beginPath();ctx.arc(x+Math.cos(ph)*10,y-24+Math.sin(ph)*3,1.6,0,7);ctx.fill();
  ctx.beginPath();ctx.arc(x+Math.cos(ph+3.1)*10,y-24+Math.sin(ph+3.1)*3,1.6,0,7);ctx.fill();}}
function render(){requestAnimationFrame(render);
 if(VW===0)fit();
 var cw=VW,ch=VH;
 ctx.setTransform(DPR,0,0,DPR,0,0);
 ctx.fillStyle="#8ecae6";ctx.fillRect(0,0,cw,ch);
 if(!grid){ctx.fillStyle="#fff";ctx.font="16px sans-serif";ctx.textAlign="center";
  ctx.fillText("waiting for game…",cw/2,ch/2);return;}
 var t0=performance.now();var pdt=lastT?(t0-lastT)/1000:0;lastT=t0;
 var myAlive=you>=0&&sc&&sc.p[you]&&sc.p[you][2]===1;
 if(myAlive&&predOK)predict(pdt);
 var me=(myAlive&&predOK)?{x:PX,y:PY}:(you>=0?lerpP(you):null);
 // Game over: the camera glides down into the finish hall for the ceremony.
 var finq=null;if(win)for(var fi=0;fi<ROOMS.length;fi++)if(ROOMS[fi][4]===5){finq=ROOMS[fi];break;}
 if(finq)me={x:(finq[0]+finq[2]/2)*TS,y:(finq[1]+finq[3]/2)*TS};
 if(me){cam.x+=(me.x-cam.x)*0.28;cam.y+=(me.y-cam.y)*0.28;}
 var zoom=Math.max(cw,ch)/760*((sc&&sc.z)?sc.z:1);
 if(finq)zoom=Math.max(zoom,Math.min(cw,ch)/(finq[2]*TS+60));
 scrZoom=zoom;var vw=cw/zoom,vh=ch/zoom;
 cam.x=Math.max(vw/2,Math.min(W*TS-vw/2,cam.x));
 cam.y=Math.max(vh/2-350,Math.min(H*TS-vh/2,cam.y));
 ctx.save();ctx.translate(cw/2,ch/2);ctx.scale(zoom,zoom);ctx.translate(-cam.x,-cam.y);
 ctx.imageSmoothingEnabled=false;
 ctx.fillStyle="#2b1a0c";ctx.fillRect(0,SURF*TS,W*TS,(H-SURF)*TS);
 // Room wallpaper tints from the host's dynamic layout; kind 4 gets the
 // arsenal's hazard stripe, kind 5 = the finish hall: pale cyan walls in a
 // checkered border, with the winners' podium on the floor.
 for(var i=0;i<ROOMS.length;i++){var q=ROOMS[i];
  if(q[4]===5){var frx=q[0]*TS,fry=q[1]*TS,frw=q[2]*TS,frh=q[3]*TS;
   ctx.fillStyle="#553f4d";ctx.fillRect(frx,fry,frw,frh);
   var nc=Math.round(frw/8),nr2=Math.round(frh/8);
   for(var rr=0;rr<nr2;rr++)for(var cc=0;cc<nc;cc++){
    if(rr>1&&rr<nr2-2&&cc>1&&cc<nc-2)continue;
    ctx.fillStyle=((rr+cc)%2===0)?"#f0f0f0":"#1a1a1e";
    ctx.fillRect(frx+cc*8,fry+rr*8,8,8);}
   var pcx=frx+frw/2,pbase=fry+frh;
   var PODW=[[pcx-12,36,"#c9a227"],[pcx-38,24,"#b7bec9"],[pcx+14,12,"#a06a3d"]];
   for(var pi=0;pi<3;pi++){var s3=PODW[pi];
    ctx.fillStyle="#1a1a1e";ctx.fillRect(s3[0]-1,pbase-s3[1]-1,26,s3[1]+1);
    ctx.fillStyle=s3[2];ctx.fillRect(s3[0],pbase-s3[1],24,s3[1]);}}
  else{ctx.fillStyle=ROOMTINT[q[4]]||"#54381f";
   ctx.fillRect(q[0]*TS,q[1]*TS,q[2]*TS,q[3]*TS);
   if(q[4]===4){var hz=0;for(var hx=q[0]*TS;hx<(q[0]+q[2])*TS;hx+=8,hz++){
    ctx.fillStyle=hz%2===0?"#e0b73c":"#2c2c30";
    ctx.fillRect(hx,q[1]*TS,Math.min(8,(q[0]+q[2])*TS-hx),5);}}}}
 ctx.fillStyle="rgba(43,26,12,0.9)";
 for(var sk in SCORCH){var si=+sk;ctx.fillRect((si%W)*TS,((si/W)|0)*TS,TS,TS);}
 ctx.drawImage(off,0,0,W*PXC,H*PXC,0,0,W*TS,H*TS);
 // Well pipe: cutaway art from the pump down to the reservoir.
 if(PIPE){var px2=(PIPE[0]+0.5)*TS;
  for(var prw=PIPE[1];prw<=PIPE[2];prw++){if(PIPEBRK[prw])continue;
   var psy=prw*TS,psh=Math.min(prw*TS+TS,PIPE[2]*TS+4)-psy;
   if(psh<=0)continue;
   ctx.fillStyle="#23303a";ctx.fillRect(px2-3,psy,6,psh);
   ctx.fillStyle="#41525f";ctx.fillRect(px2-1.5,psy,3,psh);
   if(PIPESC[prw]){ctx.fillStyle="rgba(43,26,12,0.9)";ctx.fillRect(px2-3,psy,6,psh);}}}
 if(grassCells)for(var gi=0;gi<grassCells.length;gi++){var idx=grassCells[gi];
  if(grid[idx]!==3)continue;var gx=(idx%W)*TS,gy=((idx/W)|0)*TS;
  ctx.fillStyle="#4caf50";ctx.fillRect(gx,gy,TS,4);
  ctx.fillStyle="#3f9143";ctx.fillRect(gx,gy+4,TS,1.5);}
 // Water: one flat translucent color, drawn live; surface cells start 5px
 // down so pools show a waterline.
 if(grid){ctx.fillStyle="rgba(61,128,224,0.55)";
  // Surface ripples (fx 17) age out over 1.2s.
  var nw3=performance.now();
  for(var ri2=RIPPLES.length-1;ri2>=0;ri2--)
   if(nw3-RIPPLES[ri2].t>1200)RIPPLES.splice(ri2,1);
  // The liquid body: every settled water cell as a rounded quad grown by
  // a third of a tile toward NON-water sides only (water-water edges abut
  // flush), all in ONE path so nothing double-darkens. Outer corners
  // round; the body slops over the land and air around it.
  var WG=TS/3;
  ctx.beginPath();
  for(var wi=W;wi<grid.length;wi++){if(grid[wi]!==4)continue;
   if(WTRANS[wi])continue;// in flight: rendered as splash sparks
   var wc=wi%W,wr=(wi/W)|0;
   var iu=grid[wi-W]===4,idn=wi+W<grid.length&&grid[wi+W]===4,
    il=wc>0&&grid[wi-1]===4,ir=wc<W-1&&grid[wi+1]===4;
   // an open surface dips below its row (waterline); buried tops overlap up
   var upAir=!iu&&grid[wi-W]===0;
   var x0=wc*TS-(il?0:WG),y0=wr*TS+(upAir?4:(iu?0:-WG)),
    x1=wc*TS+TS+(ir?0:WG),y1=wr*TS+TS+(idn?0:WG);
   var rr5=[(iu||il)?0:5,(iu||ir)?0:5,(idn||ir)?0:5,(idn||il)?0:5];
   if(ctx.roundRect)ctx.roundRect(x0,y0,x1-x0,y1-y0,rr5);
   else ctx.rect(x0,y0,x1-x0,y1-y0);}
  // Rolling waterlines join the same fill: wave humps above the raised
  // surface near each active ripple.
  for(var ri3=0;ri3<RIPPLES.length;ri3++){var rp2=RIPPLES[ri3];
   var age2=(nw3-rp2.t)/1000,env2=(1-age2/1.2)*rp2.p*4;
   if(env2<=0)continue;
   var oc2=Math.floor(rp2.x/TS),or2=Math.floor(rp2.y/TS);
   for(var dc2=-4;dc2<=4;dc2++){var cx2=oc2+dc2;
    if(cx2<0||cx2>=W)continue;
    var sy2=-1;
    for(var dy2=-3;dy2<=3;dy2++){var cy2=or2+dy2;
     if(cy2<1||cy2>=H)continue;
     if(grid[cy2*W+cx2]===4&&grid[(cy2-1)*W+cx2]!==4){sy2=cy2;break;}}
    if(sy2<0)continue;
    var wl2=sy2*TS+4;
    for(var sb=0;sb<4;sb++){var pxb=cx2*TS+sb*4+2,dxp2=pxb-rp2.x;
     var a2=env2*Math.exp(-Math.abs(dxp2)*0.03)
      *(0.5+0.5*Math.cos(Math.abs(dxp2)*0.26-age2*9));
     if(a2>0.6)ctx.rect(pxb-2,wl2-a2,4,a2);}}}
  ctx.fill();}
 var now=performance.now();
 if(sc&&sc.c)for(var i=0;i<sc.c.length;i++){var q=sc.c[i];
  ctx.fillStyle="#000";ctx.fillRect(q[0]-10,q[1]-8,20,16);
  ctx.fillStyle="#6d4c2f";ctx.fillRect(q[0]-9,q[1]-1,18,8);
  ctx.fillStyle="#8a6238";ctx.fillRect(q[0]-9,q[1]-7,18,6);
  ctx.fillStyle="#caa64a";ctx.fillRect(q[0]-9,q[1]-2,18,2);
  ctx.fillStyle="#e8c35c";ctx.fillRect(q[0]-2,q[1]-3,4,5);}
 if(sc&&sc.e)for(var i=0;i<sc.e.length;i++){var q=sc.e[i];
  ctx.save();ctx.translate(q[0],q[1]);ctx.rotate((q[3]||0)/10);drawProp(q[2]);ctx.restore();}
 stepRags(pdt);drawRags();
 stepBombs(pdt);
 for(var i=0;i<bsim.length;i++){var e=bsim[i];
  var fu=e.dud?0:Math.max(e.fuse-(now-e.ft)/1000,0);
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.beginPath();ctx.arc(e.x,e.y,e.r+1.5,0,7);ctx.fill();
  var blink=!e.dud&&fu<1.2&&(now/100|0)%2===0;
  ctx.fillStyle=blink?"#ff5936":BOMB[e.type]||"#212126";
  ctx.beginPath();ctx.arc(e.x,e.y,e.r,0,7);ctx.fill();
  ctx.fillStyle="rgba(255,255,255,.2)";ctx.beginPath();ctx.arc(e.x-e.r/3,e.y-e.r/3,e.r/4,0,7);ctx.fill();
  // Per-type detailing to match the native bombs.
  if(e.type===1){ctx.fillStyle="rgba(204,38,25,.85)";ctx.fillRect(e.x-e.r,e.y-2.5,e.r*2,5);}
  else if(e.type===2&&e.r>6){ctx.fillStyle="rgba(255,178,76,.85)";
   for(var a3=0;a3<3;a3++){var an=2.094*a3+0.5;
    ctx.beginPath();ctx.arc(e.x+Math.cos(an)*e.r*0.45,e.y+Math.sin(an)*e.r*0.45,1.8,0,7);ctx.fill();}}
  else if(e.type===4){ctx.fillStyle="rgba(217,89,242,.9)";
   ctx.beginPath();ctx.arc(e.x-e.r*0.6,e.y+e.r*0.45,2.6,0,7);ctx.fill();
   ctx.beginPath();ctx.arc(e.x+e.r*0.55,e.y+e.r*0.5,2.2,0,7);ctx.fill();
   ctx.beginPath();ctx.arc(e.x,e.y+e.r*0.85,1.8,0,7);ctx.fill();}
  else if(e.type===5){ctx.strokeStyle="rgba(230,240,255,.95)";ctx.lineWidth=2.4;
   ctx.beginPath();ctx.arc(e.x,e.y,e.r-1.2,-2.7,-0.5);ctx.stroke();}
  else if(e.type===6){ctx.fillStyle="#a9adb8";
   ctx.beginPath();ctx.moveTo(e.x-e.r*0.7,e.y+e.r*0.6);ctx.lineTo(e.x+e.r*0.7,e.y+e.r*0.6);
   ctx.lineTo(e.x,e.y+e.r+7);ctx.closePath();ctx.fill();
   ctx.strokeStyle="#8c909c";ctx.lineWidth=1.6;
   ctx.beginPath();ctx.moveTo(e.x-e.r*0.55,e.y);ctx.lineTo(e.x+e.r*0.55,e.y-3);ctx.stroke();}
  else if(e.type===7){ctx.fillStyle="#8c909c";ctx.fillRect(e.x-e.r,e.y-e.r*0.75,e.r*2,4);
   ctx.fillStyle="#6a6e79";ctx.fillRect(e.x-3,e.y-e.r*0.75+4,6,e.r*0.8);}
  ctx.fillStyle=e.dud?"#9a9a9a":(fu<1.2?"#ff5936":"#fff");ctx.font="bold 11px sans-serif";ctx.textAlign="center";
  ctx.fillText(e.dud?"DUD":fu.toFixed(1),e.x,e.y-e.r-6);}
 if(sc)for(var i=0;i<sc.p.length;i++){var p=sc.p[i];if(!p||p[2]===0)continue;
  var pos=(i===you&&predOK)?{x:PX,y:PY}:lerpP(i);var col="#"+(roster[i]?roster[i].c:"ffffff");
  var col2=roster[i]&&roster[i].c2?"#"+roster[i].c2:col;
  // Derive facing/walk-swing/airborne locally from motion (no extra network data).
  var a=anim[i]||(anim[i]={face:1,phase:0,swing:0,px:pos.x,py:pos.y});
  var vpx,vpy,grnd;
  if(i===you&&predOK){vpx=VX;vpy=VY;grnd=onG;}
  else{var dd=Math.max(pdt,0.001);vpx=(pos.x-a.px)/dd;vpy=(pos.y-a.py)/dd;grnd=Math.abs(vpy)<80;}
  a.px=pos.x;a.py=pos.y;
  if(Math.abs(vpx)>20)a.face=vpx>0?1:-1;
  var air=!grnd,stg=0;
  if(!air&&Math.abs(vpx)>20){a.phase+=vpx*pdt*0.055;stg=Math.sin(a.phase)*0.6;}
  a.swing+=(stg-a.swing)*0.35;a.vx=vpx;a.vy=vpy;
  // Stunned = tumbling ragdoll: spin speed follows how hard they're
  // flying; near-still bodies lie flat instead of freezing mid-pose.
  var stn=p.length>6&&p[6]===1,stAng=0;
  if(stn){var spd=Math.hypot(vpx,vpy);
   a.tum=(a.tum||0)+pdt*(2.5+Math.min(spd*0.03,9))*(a.face||1);
   stAng=spd>50?a.tum:1.1*(a.face||1);}
  else a.tum=0;
  var kck=(p.length>7&&p[7]===1)||(i===you&&t0-KANIM<250);
  drawGuy(pos.x,pos.y,col,col2,p[5]===1,a.swing,a.face,air,stn,stAng,kck);
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
 if(win&&finq)drawCeremony(finq,now);
 // Charged-kick trajectory preview (world space): dotted arc along the path
 // a kicked bomb would fly at the current charge.
 var chT=kickT||gestT||btnKickT;
 if(chT){var kdx=chT.x-chT.ox,kdy=chT.y-chT.oy,kd=Math.hypot(kdx,kdy);
  var meW=(you>=0&&predOK)?{x:PX,y:PY}:(you>=0&&sc&&sc.p[you]?lerpP(you):null);
  if(meW&&kd>=12){var kp=Math.max(0.25,Math.min(1,kd/90));
   var kvx=kdx/kd*430*kp,kvy=kdy/kd*430*kp;
   for(var ti=1;ti<=9;ti++){var tt=ti*0.055;
    var qx=meW.x+kvx*tt,qy=meW.y+kvy*tt+490*tt*tt;
    ctx.fillStyle="rgba(255,255,255,"+(0.85-ti*0.08).toFixed(2)+")";
    ctx.beginPath();ctx.arc(qx,qy,2.2,0,7);ctx.fill();}}}
 ctx.restore();
 // Gesture overlays (screen space): thumb joystick + kick charge bar + hint.
 if(moveT){ctx.strokeStyle="rgba(255,255,255,.5)";ctx.lineWidth=2;
  ctx.beginPath();ctx.arc(moveT.ox,moveT.oy,40,0,7);ctx.stroke();
  var knx=Math.max(-40,Math.min(40,moveT.x-moveT.ox));
  ctx.fillStyle="rgba(255,255,255,.3)";
  ctx.beginPath();ctx.arc(moveT.ox+knx,moveT.oy,20,0,7);ctx.fill();}
 if(chT){var bdx=chT.x-chT.ox,bdy=chT.y-chT.oy,bd=Math.hypot(bdx,bdy);
  if(bd>=12){var bp=Math.max(0.25,Math.min(1,bd/90));var ms2=myScreen();
   if(ms2){ctx.fillStyle="rgba(0,0,0,.55)";ctx.fillRect(ms2.x-26,ms2.y-56,52,9);
    ctx.fillStyle=bp>0.8?"#ff5252":(bp>0.5?"#ffca28":"#9ccc65");
    ctx.fillRect(ms2.x-24,ms2.y-54,48*bp,5);}}}
 if(joinT&&now-joinT<8000){ctx.fillStyle="rgba(0,0,0,.45)";
  ctx.fillRect(cw/2-170,ch-96,340,46);
  ctx.fillStyle="#fff";ctx.font="12px sans-serif";ctx.textAlign="center";
  ctx.fillText("drag = move  •  tap/stick-up/button = jump",cw/2,ch-78);
  ctx.fillText("KICK: tap = quick kick, hold + pull = aimed charge",cw/2,ch-60);}
 ctx.textAlign="left";ctx.font="12px sans-serif";
 for(var i=0;i<roster.length;i++){ctx.fillStyle="#"+roster[i].c;
  ctx.fillText(roster[i].n,10,18+i*15);}
 if(HTIME>=0){ctx.textAlign="right";ctx.font="bold 13px sans-serif";
  ctx.fillStyle="#fff";var hs=HTIME%60;
  ctx.fillText(Math.floor(HTIME/60)+":"+(hs<10?"0":"")+hs,cw-10,18);}
 if(HUDMSG){ctx.textAlign="center";ctx.font="bold 15px sans-serif";
  ctx.fillStyle="rgba(0,0,0,.45)";ctx.fillRect(cw/2-160,34,320,24);
  ctx.fillStyle="#ffe9a8";ctx.fillText(HUDMSG,cw/2,51);}
 ctx.textAlign="center";
 if(sc&&you>=0&&sc.p[you]&&sc.p[you][2]===0){
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.fillRect(cw/2-130,ch*0.35-24,260,36);
  ctx.fillStyle="#ff8a80";ctx.font="bold 18px sans-serif";
  var msg=sc.p[you][3]<0?"eliminated — spectating":"respawn in "+(sc.p[you][3]/10).toFixed(1);
  ctx.fillText(msg,cw/2,ch*0.35);}
 // Slim top banner only: the celebration itself plays out in the world —
 // the camera glides into the finish hall where the top three jump on the
 // podium (drawCeremony).
 if(win){ctx.fillStyle="rgba(0,0,0,.45)";ctx.fillRect(0,34,cw,62);
  ctx.fillStyle="#"+win.c;ctx.font="bold 24px sans-serif";
  ctx.fillText(win.n.toUpperCase()+" WINS!",cw/2,60);
  ctx.fillStyle="#ddd";ctx.font="12px sans-serif";
  ctx.fillText("waiting for host rematch…",cw/2,84);}}
function y0(py){return py-20;}
// World-space podium ceremony in the finish hall (q = the kind-5 room):
// confetti + the win message's top three jumping on the drawn podium steps.
function drawCeremony(q,now){if(!win.podium)return;
 var rx=q[0]*TS,ry=q[1]*TS,rw=q[2]*TS,rh=q[3]*TS;
 var pcx=rx+rw/2,pb=ry+rh,t=now/1000;
 var CF=["#ef5350","#ffca28","#9ccc65","#64b5f6","#ba68c8"];
 for(var i=0;i<26;i++){var hh=(i*7349*2654435761)>>>0;
  var fx=rx+6+(hh%1000)/1000*(rw-12);
  var fy=ry+((((hh>>10)%1000)/1000*rh)+t*(16+(i%5)*5))%(rh-6);
  ctx.fillStyle=CF[i%CF.length];
  ctx.fillRect(fx+Math.sin(t*3+i)*2.5,fy,2.2,1.4);}
 var SPOT=[[pcx,36],[pcx-26,24],[pcx+26,12]];
 for(var i=0;i<Math.min(3,win.podium.length);i++){var e=win.podium[i];
  var jump=Math.abs(Math.sin(t*4+i*0.9))*(i===0?8:5);
  var gx=SPOT[i][0],gy=pb-SPOT[i][1]-14-jump;
  drawGuy(gx,gy,"#"+e[1],"#"+e[1],false,Math.sin(t*9+i*1.7)*0.4,1,true,false,0);
  ctx.textAlign="center";ctx.fillStyle="#fff";ctx.font="bold 8px sans-serif";
  ctx.fillText(e[0],gx,gy-22);
  ctx.fillStyle="rgba(0,0,0,.7)";ctx.font="7px sans-serif";
  ctx.fillText(e[2]+" deep",gx,pb-SPOT[i][1]/2+2);}
 ctx.textAlign="left";}
// Homestead props by kind id: 0 table 1 chair 2 bed 3 pillow 4 toilet
// 5 shower 6 chicken 7 pig 8 fence 9 outhouse 10 pump 13 corn stalk
// 14 wall gun 15 bullet 16 cave-mouth rocks. Drawn centered (corn/cave:
// base at origin).
function drawProp(k){
 if(k===0){ctx.fillStyle="#000";ctx.fillRect(-19,-11,38,22);
  ctx.fillStyle="#8a5a2b";ctx.fillRect(-18,-10,36,5);
  ctx.fillRect(-15,-5,4,15);ctx.fillRect(11,-5,4,15);}
 else if(k===1){ctx.fillStyle="#000";ctx.fillRect(-9,-12,18,24);
  ctx.fillStyle="#a06a33";ctx.fillRect(-8,-2,14,4);ctx.fillRect(-8,-11,4,13);
  ctx.fillRect(-8,2,3,9);ctx.fillRect(3,2,3,9);}
 else if(k===2){ctx.fillStyle="#000";ctx.fillRect(-23,-9,46,18);
  ctx.fillStyle="#6d4c2f";ctx.fillRect(-22,-2,44,10);
  ctx.fillStyle="#d9d4c8";ctx.fillRect(-22,-8,44,7);
  ctx.fillStyle="#8a5a2b";ctx.fillRect(-22,-8,5,16);}
 else if(k===3){ctx.fillStyle="#000";ctx.beginPath();ctx.ellipse(0,0,10,6,0,0,7);ctx.fill();
  ctx.fillStyle="#f4efe2";ctx.beginPath();ctx.ellipse(0,0,9,5,0,0,7);ctx.fill();}
 else if(k===4){ctx.fillStyle="#000";ctx.fillRect(-9,-10,18,20);
  ctx.fillStyle="#e8ecf1";ctx.fillRect(-8,-9,7,16);ctx.fillRect(-8,3,16,6);
  ctx.beginPath();ctx.ellipse(3,0,6,4,0,0,7);ctx.fill();}
 else if(k===5){ctx.fillStyle="#000";ctx.fillRect(-5,-15,10,30);
  ctx.fillStyle="#9aa5b1";ctx.fillRect(-2,-14,4,28);ctx.fillRect(-8,-14,12,4);
  ctx.fillStyle="#c9d2dc";ctx.fillRect(2,-2,5,3);}
 else if(k===6){ctx.fillStyle="#000";ctx.beginPath();ctx.ellipse(0,0,6.5,6,0,0,7);ctx.fill();
  ctx.fillStyle="#f2f2ee";ctx.beginPath();ctx.ellipse(0,0,5.5,5,0,0,7);ctx.fill();
  ctx.fillStyle="#e53935";ctx.fillRect(-1,-7,3,3);
  ctx.fillStyle="#fbc02d";ctx.fillRect(4,-2,4,2);
  ctx.fillStyle="#c98d29";ctx.fillRect(-2,5,2,3);ctx.fillRect(1,5,2,3);}
 else if(k===7){ctx.fillStyle="#000";ctx.beginPath();ctx.ellipse(0,0,9.5,6.5,0,0,7);ctx.fill();
  ctx.fillStyle="#f2a3b3";ctx.beginPath();ctx.ellipse(0,0,8.5,5.5,0,0,7);ctx.fill();
  ctx.fillStyle="#d98795";ctx.fillRect(6,-2,4,4);
  ctx.fillStyle="#c9868f";ctx.fillRect(-6,4,2,3);ctx.fillRect(4,4,2,3);}
 else if(k===8){ctx.fillStyle="#000";ctx.fillRect(-3,-12,6,24);
  ctx.fillStyle="#8a6238";ctx.fillRect(-2,-11,4,22);
  ctx.fillStyle="#000";ctx.fillRect(-11,-6.5,22,6);ctx.fillRect(-11,1.5,22,6);
  ctx.fillStyle="#5e3d22";ctx.fillRect(-10,-5.5,20,3);ctx.fillRect(-10,2.5,20,3);}
 else if(k===9){ctx.fillStyle="#000";ctx.fillRect(-19,-24,38,48);
  ctx.fillStyle="#8a5a2b";ctx.fillRect(-18,-18,36,42);
  ctx.fillStyle="#6d4423";ctx.fillRect(-19,-24,38,7);
  ctx.fillStyle="#241a10";ctx.fillRect(-7,-6,14,30);
  ctx.fillStyle="#f4e6b0";ctx.beginPath();ctx.arc(0,-11,2.5,0,7);ctx.fill();}
 else if(k===10){ctx.fillStyle="#000";ctx.fillRect(-4,-10,8,20);
  ctx.fillStyle="#3e6b4f";ctx.fillRect(-3,-9,6,18);
  ctx.fillStyle="#2f523c";ctx.fillRect(-8,-7,6,3);ctx.fillRect(-8,-4,2.5,2);
  ctx.strokeStyle="#263e2e";ctx.lineWidth=2.5;
  ctx.beginPath();ctx.moveTo(2,-9);ctx.lineTo(8,-13);ctx.stroke();}
 else if(k===13){ctx.strokeStyle="#3f8f3a";ctx.lineWidth=2.5;
  ctx.beginPath();ctx.moveTo(0,0);ctx.lineTo(0,-30);ctx.stroke();
  ctx.fillStyle="#57a84f";
  ctx.beginPath();ctx.moveTo(0,-12);ctx.lineTo(-3,-14);ctx.lineTo(-9,-18);ctx.closePath();ctx.fill();
  ctx.beginPath();ctx.moveTo(0,-20);ctx.lineTo(3,-22);ctx.lineTo(9,-26);ctx.closePath();ctx.fill();
  ctx.strokeStyle="#e8c35c";ctx.lineWidth=1.6;
  ctx.beginPath();ctx.moveTo(0,-30);ctx.lineTo(0,-35);ctx.stroke();}
 else if(k===14){ctx.fillStyle="#000";ctx.fillRect(-8,-4.5,8,9);ctx.fillRect(-3,-3,24,6);
  ctx.fillStyle="#454049";ctx.fillRect(-7,-3.5,6,7);
  ctx.fillStyle="#2e2e34";ctx.fillRect(10,-2,10,4);
  ctx.fillStyle="#6d4c2f";ctx.fillRect(-2,-2.5,12,5);
  ctx.fillStyle="#2e2e34";ctx.fillRect(3,2,2,3);}
 else if(k===15){ctx.fillStyle="#ffd54f";ctx.fillRect(-3,-1,6,2);
  ctx.fillStyle="#fff";ctx.fillRect(-1,-0.5,2,1);}
 else if(k===16){
  // one continuous lumpy rock mound with a dark maw (matches native art)
  var MD=[[-24,2],[-23,-6],[-18,-12],[-14,-12],[-9,-18],[-3,-22],[4,-21],
   [9,-17],[14,-15],[18,-10],[22,-7],[24,2]];
  ctx.fillStyle="#000";
  fillPoly(MD.map(function(p){return [p[0]*1.1,(p[1]+8)*1.1-8];}));
  ctx.fillStyle="#6e7681";fillPoly(MD);
  ctx.fillStyle="#59616b";
  fillPoly([[4,-21],[9,-17],[14,-15],[18,-10],[22,-7],[24,2],[10,2],[6,-12]]);
  ctx.fillStyle="#777d86";
  fillPoly([[-23,-6],[-18,-12],[-14,-12],[-16,-2],[-24,2]]);
  ctx.strokeStyle="#4d545c";ctx.lineWidth=1.2;ctx.beginPath();
  ctx.moveTo(-6,-17);ctx.lineTo(-9,-8);ctx.moveTo(11,-13);ctx.lineTo(8,-5);ctx.stroke();
  ctx.fillStyle="#1c1310";
  fillPoly([[-11,4],[-10,-6],[-6,-12],[0,-14],[6,-12],[10,-6],[11,4]]);
  ctx.fillRect(-11,2,22,16);}}
function fillPoly(pts){ctx.beginPath();
 for(var i=0;i<pts.length;i++){if(i)ctx.lineTo(pts[i][0],pts[i][1]);
  else ctx.moveTo(pts[i][0],pts[i][1]);}
 ctx.closePath();ctx.fill();}
// Show the "Add to Home Screen" hint only in a normal browser tab, not when
// already launched as an installed home-screen app.
(function(){try{var standalone=window.navigator.standalone===true||
 (window.matchMedia&&window.matchMedia("(display-mode: standalone)").matches);
 if(!standalone)document.getElementById("a2hs").style.display="block";}catch(e){}})();
fit();connect();render();
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
	_beacon.set_broadcast_enabled(true)
	_icon_png = _make_icon_png()


## Write a small HTTP/1.1 response with the given content type and body.
func _send_http(tcp: StreamPeerTCP, content_type: String, body: PackedByteArray) -> void:
	var head := ("HTTP/1.1 200 OK\r\nContent-Type: %s\r\n" +
		"Content-Length: %d\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n") \
		% [content_type, body.size()]
	tcp.put_data(head.to_utf8_buffer())
	tcp.put_data(body)


## A 256x256 bomb icon PNG for the home-screen app.
func _make_icon_png() -> PackedByteArray:
	var s := 256
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color("8ecae6"))
	var ground := int(s * 0.72)
	for y in range(ground, s):
		for x in s:
			img.set_pixel(x, y, Color("7a5230"))
	for y in range(ground, ground + 14):
		for x in s:
			img.set_pixel(x, y, Color("4caf50"))
	var cx := s / 2
	var cy := int(s * 0.52)
	var r := int(s * 0.27)
	for y in range(cy - r - 4, cy + r + 4):
		for x in range(cx - r - 4, cx + r + 4):
			var d := Vector2(x - cx, y - cy).length()
			if d <= r:
				img.set_pixel(x, y, Color("212126"))
			elif d <= r + 3:
				img.set_pixel(x, y, Color(0, 0, 0, 0.5))
	# highlight + fuse spark
	for y in range(cy - r / 2, cy - r / 5):
		for x in range(cx - r / 2, cx - r / 5):
			if Vector2(x - (cx - r / 3), y - (cy - r / 3)).length() <= r / 5:
				img.set_pixel(x, y, Color(1, 1, 1, 0.25))
	var fx := cx + int(r * 0.5)
	var fy := cy - r - 6
	for y in range(fy - 8, fy + 8):
		for x in range(fx - 8, fx + 8):
			if x >= 0 and y >= 0 and x < s and y < s and Vector2(x - fx, y - fy).length() <= 7:
				img.set_pixel(x, y, Color("ffb300"))
	return img.save_png_to_buffer()


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


## Open an internet room via the relay Worker. Safe to call repeatedly.
func start_relay() -> void:
	if RELAY_HOST.is_empty() or _relay_ws != null:
		_relay_wanted = true
		return
	_relay_wanted = true
	_relay_ws = WebSocketPeer.new()
	if _relay_ws.connect_to_url("wss://%s/host" % RELAY_HOST) != OK:
		_relay_ws = null
		_relay_retry = 4.0


func relay_page_url() -> String:
	if relay_code.is_empty():
		return ""
	return "https://%s/r/%s" % [RELAY_HOST, relay_code]


func _relay_key(cid: int) -> int:
	return RELAY_ID_BASE + cid


func _relay_send(obj: Dictionary) -> void:
	if _relay_ws != null and _relay_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_relay_ws.send_text(JSON.stringify(obj))


func _poll_relay(delta: float) -> void:
	if _relay_ws == null:
		if _relay_wanted and not RELAY_HOST.is_empty():
			_relay_retry -= delta
			if _relay_retry <= 0.0:
				_relay_retry = 5.0
				start_relay()
		return
	_relay_ws.poll()
	var state := _relay_ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		# Relay dropped: every remote guest is gone; retry soon.
		for id in clients.keys():
			if int(id) >= RELAY_ID_BASE:
				clients[id].connected = false
				clients[id].axis = 0.0
				clients[id].jump = false
		relay_code = ""
		_relay_ws = null
		_relay_retry = 4.0
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	while _relay_ws.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(_relay_ws.get_packet().get_string_from_utf8())
		if not (msg is Dictionary):
			continue
		var env := msg as Dictionary
		if str(env.get("t", "")) == "room":
			relay_code = str(env.get("code", ""))
			# Ship the game page so the relay can serve it to guests.
			var html := PAGE.replace("__WSURL__",
				"wss://%s/join/%s" % [RELAY_HOST, relay_code])
			_relay_send({"t": "page", "html": html})
			relay_ready.emit(relay_code)
			continue
		if not env.has("c"):
			continue
		var key := _relay_key(int(env.get("c", 0)))
		match str(env.get("ev", "")):
			"open":
				clients[key] = {
					"ws": null, "relay": true, "joined": false, "connected": true,
					"pending_init": false, "pending_colors": true,
					"name": "", "color": Color("ff8f2e"), "color2": Color("ff8f2e"),
					"axis": 0.0, "jump": false, "kick": false,
					"kick_dir": Vector2.ZERO, "kick_power": 1.0,
				}
			"close":
				if clients.has(key):
					clients[key].connected = false
					clients[key].axis = 0.0
					clients[key].jump = false
			_:
				if clients.has(key) and env.get("m") is Dictionary:
					_handle(clients[key], env.get("m") as Dictionary)


func _process(delta: float) -> void:
	_poll_relay(delta)
	# --- LAN discovery beacon (hosting only) ---
	if advertising:
		_beacon_t -= delta
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var label := OS.get_model_name()
			if label.is_empty() or label == "GenericDevice":
				label = "Host"
			_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
			_beacon.put_packet(JSON.stringify({
				"g": "bombshelter", "n": label, "ws": ws_port, "http": http_port,
			}).to_utf8_buffer())

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
			# Route by request path: the home-screen icon (iOS auto-fetches
			# /apple-touch-icon*.png), the web manifest (Android install), or
			# the page itself.
			var path := "/"
			var line: String = p.buf.split("\r\n")[0]
			var parts := line.split(" ")
			if parts.size() >= 2:
				path = parts[1]
			if path.contains("icon") or path.contains("favicon") or path.contains("apple-touch"):
				_send_http(tcp, "image/png", _icon_png)
			elif path.contains("manifest"):
				_send_http(tcp, "application/manifest+json", MANIFEST.to_utf8_buffer())
			else:
				_send_http(tcp, "text/html; charset=utf-8",
					PAGE.replace("__WSURL__", "ws://HOSTNAME:%d" % ws_port).to_utf8_buffer())
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
			"kick_dir": Vector2.ZERO, "kick_power": 1.0,
		}
		_next_id += 1

	for id in clients.keys():
		var c: Dictionary = clients[id]
		if not c.connected or c.get("relay", false):
			continue  # relay guests are pumped by _poll_relay
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
	if c.get("relay", false):
		_relay_send({"c": int(id) - RELAY_ID_BASE, "m": msg})
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
		if c.get("relay", false):
			_relay_send({"c": int(id) - RELAY_ID_BASE, "m": msg})
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
		if c.get("relay", false):
			_relay_send({"c": int(id) - RELAY_ID_BASE, "m": msg})
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
		"k":
			# One-shot directional charged kick from the gesture layer.
			var kd := Vector2(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
			c.kick_dir = kd if kd.length_squared() > 0.001 else Vector2.ZERO
			c.kick_power = clampf(float(msg.get("p", 1.0)), 0.2, 1.0)
		"c":
			c.color = Color.from_string(str(msg.get("c", "")), c.color)
			c.color2 = Color.from_string(str(msg.get("c2", "")), c.color)
