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

var http_port := 0
var ws_port := 0
var _icon_png := PackedByteArray()
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
canvas{position:absolute;top:0;left:0;display:block}
.pad{position:absolute;bottom:calc(14px + env(safe-area-inset-bottom));width:84px;height:84px;border-radius:50%;
background:rgba(255,255,255,.14);border:2px solid rgba(255,255,255,.35);
display:flex;align-items:center;justify-content:center;font-size:34px;color:rgba(255,255,255,.85)}
.pad.on{background:rgba(255,255,255,.35)}
#left{left:calc(16px + env(safe-area-inset-left))}
#right{left:calc(116px + env(safe-area-inset-left))}
#jump{right:calc(16px + env(safe-area-inset-right))}
#kick{right:calc(116px + env(safe-area-inset-right));font-size:26px}
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
<div class="pad" id="left">&#9664;</div><div class="pad" id="right">&#9654;</div>
<div class="pad" id="jump">&#9650;</div><div class="pad" id="kick">KICK</div>
<div id="colorbtn"></div><div id="fs">&#x26F6;</div></div>
<script>
var ws=null,joined=false,st={a:0,j:0,k:0},held={left:false,right:false,jump:false,kick:false};
var W=0,H=0,TS=16,SURF=20,FIN=0,grid=null,off=null,octx=null;
var roster=[],you=-1,sp=null,sc=null,tp=0,tc=0,flashes=[],sparks=[],win=null;
var opts=[],selKey=null,cycleIdx=0;
var CELL=["","#7a5230","#4b4b55","#4caf50"],CELL2=["","#5c3d22","#3a3a44","#3f9143"];
var grassCells=null;var anim={};
var BOMB=["#212126","#131318","#733f17","#1f5c2e","#80247f"];
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
function tone(freq,start,dur,vol){var t=AC.currentTime+start;
 var o=AC.createOscillator();o.type="triangle";o.frequency.value=freq;
 var g=AC.createGain();g.gain.setValueAtTime(0.0001,t);g.gain.linearRampToValueAtTime(vol,t+0.02);
 g.gain.exponentialRampToValueAtTime(0.0001,t+dur);
 o.connect(g);g.connect(AC.destination);o.start(t);o.stop(t+dur);}
function fanfare(){if(!AC)return;[523.25,659.25,784.0,1046.5].forEach(function(f,i){
 tone(f,i*0.16,i===3?0.6:0.2,0.28);});}
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
function connect(){
 ws=new WebSocket("ws://"+location.hostname+":__WSPORT__");
 ws.onopen=function(){document.getElementById("status").textContent="ready — pick a name and join";
  if(joined)sendJoin();};
 ws.onclose=function(){document.getElementById("status").textContent="reconnecting…";setTimeout(connect,1500);};
 ws.onmessage=function(ev){var m=JSON.parse(ev.data);
  if(m.t==="s"){
   if(sc)for(var i=0;i<sc.p.length&&i<m.p.length;i++)
    if(sc.p[i][2]===1&&m.p[i][2]===0){burst(m.p[i][0],m.p[i][1],roster[i]?roster[i].c:"fff");splat();}
   sp=sc;tp=tc;sc=m;tc=performance.now();reconcile();}
  else if(m.t==="carve"){carve(m.x,m.y,m.r);flashes.push({x:m.x,y:m.y,r:m.r,t:performance.now()});
   boom(Math.min(0.55,0.2+m.r/240));}
  else if(m.t==="init"){W=m.w;H=m.h;TS=m.ts;SURF=m.surf;FIN=m.fin;
   grid=new Uint8Array(m.grid.length);
   for(var i=0;i<m.grid.length;i++)grid[i]=m.grid.charCodeAt(i)-48;
   buildTerrain();sp=sc=null;flashes=[];sparks=[];win=null;anim={};predOK=false;}
  else if(m.t==="roster"){roster=m.p;updateBtn();}
  else if(m.t==="you"){you=m.i;updateBtn();}
  else if(m.t==="colors"){opts=m.opts;
   if(!joined){if(!selKey||!opts.some(function(o){return key(o)===selKey;}))
    selKey=opts.length?key(opts[0]):null;
   renderSw();}}
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
function doJoin(){if(!ws||ws.readyState!==1)return;goFS();joined=true;sendJoin();
 if(!AC)initAudio();
 if(AC&&AC.state==="suspended"){var pr=AC.resume();if(pr&&pr.catch)pr.catch(function(){});}
 document.getElementById("join").style.display="none";
 document.getElementById("game").style.display="block";updateBtn();
 fit();setTimeout(fit,150);setTimeout(fit,600);}
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
 octx=off.getContext("2d");grassCells=[];
 for(var r=0;r<H;r++)for(var c=0;c<W;c++){var v=grid[r*W+c];if(!v)continue;
  // Grass blocks are dirt-bodied; a thin green cap is drawn on top at render.
  var dv=(v===3)?1:v;
  octx.fillStyle=(Math.random()<0.3)?CELL2[dv]:CELL[dv];octx.fillRect(c,r,1,1);
  if(v===3)grassCells.push(r*W+c);}}
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
// --- Client-side prediction for YOUR player: simulate locally from your own
// input against the terrain the client already has, so movement is instant;
// the host stream only nudges/reconciles it. Removes the input round-trip lag.
var PX=0,PY=0,VX=0,VY=0,onG=false,predOK=false,prevJ=false,lastT=0;
function mv(a,b,d){return Math.abs(b-a)<=d?b:a+(b>a?d:-d);}
function solidBox(cx,cy){var l=cx-6,rt=cx+6,tp=cy-12,bt=cy+12;
 var c0=Math.floor(l/TS),c1=Math.floor((rt-0.01)/TS),r0=Math.floor(tp/TS),r1=Math.floor((bt-0.01)/TS);
 for(var r=r0;r<=r1;r++)for(var c=c0;c<=c1;c++){
  if(c<0||c>=W)return true;if(r<0||r>=H)continue;
  if(grid[r*W+c]!==0)return true;}return false;}
function predict(dt){if(dt>0.05)dt=0.05;
 onG=solidBox(PX,PY+1);
 var steps=Math.max(1,Math.ceil(Math.max(Math.abs(VX),Math.abs(VY))*dt/6));
 var sdt=dt/steps;
 for(var s=0;s<steps;s++){
  var dir=(held.left?-1:0)+(held.right?1:0);
  VX=mv(VX,dir*230,1900*sdt);
  VY=Math.min(VY+980*sdt,900);
  if(held.jump&&!prevJ&&onG){VY=-430;onG=false;}
  prevJ=held.jump;
  var nx=PX+VX*sdt;
  if(!solidBox(nx,PY))PX=nx;
  else{var sx=VX>0?1:-1;while(!solidBox(PX+sx,PY)&&(nx-PX)*sx>0)PX+=sx;VX=0;}
  var ny=PY+VY*sdt;
  if(!solidBox(PX,ny))PY=ny;
  else{var sy=VY>0?1:-1;if(VY>0)onG=true;while(!solidBox(PX,PY+sy)&&(ny-PY)*sy>0)PY+=sy;VY=0;}}}
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
function drawGuy(x,y,col,col2,armor,swing,face,air){
 var c=rgbOf(col),armc=mul(c,0.85),legc=mul(c,0.65);
 var ra,la,rl,ll,lx;
 if(air){ra=-2.5;la=2.5;rl=0;ll=0;lx=1.5;}
 else{ra=swing;la=-swing;rl=-swing;ll=swing;lx=3;}
 limbW(x,y,5,-6,ra,10,mul(c,0.68),face);         // back arm
 limbW(x,y,lx,2,rl,12,mul(c,0.52),face);         // back leg
 limbW(x,y,-lx,2,ll,12,legc,face);               // front leg
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
 limbW(x,y,-5,-6,la,10,armc,face);}              // front arm
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
 if(me){cam.x+=(me.x-cam.x)*0.28;cam.y+=(me.y-cam.y)*0.28;}
 var zoom=Math.max(cw,ch)/760*((sc&&sc.z)?sc.z:1);var vw=cw/zoom,vh=ch/zoom;
 cam.x=Math.max(vw/2,Math.min(W*TS-vw/2,cam.x));
 cam.y=Math.max(vh/2-350,Math.min(H*TS-vh/2,cam.y));
 ctx.save();ctx.translate(cw/2,ch/2);ctx.scale(zoom,zoom);ctx.translate(-cam.x,-cam.y);
 ctx.imageSmoothingEnabled=false;
 ctx.fillStyle="#17100a";ctx.fillRect(0,SURF*TS,W*TS,(H-SURF)*TS);
 ctx.drawImage(off,0,0,W,H,0,0,W*TS,H*TS);
 if(grassCells)for(var gi=0;gi<grassCells.length;gi++){var idx=grassCells[gi];
  if(grid[idx]!==3)continue;var gx=(idx%W)*TS,gy=((idx/W)|0)*TS;
  ctx.fillStyle="#4caf50";ctx.fillRect(gx,gy,TS,4);
  ctx.fillStyle="#3f9143";ctx.fillRect(gx,gy+4,TS,1.5);}
 for(var fx=3*TS,k=0;fx<(W-3)*TS;fx+=8,k++){
  ctx.fillStyle=(k%2===0)?"#ffd54f":"#1a1a1a";ctx.fillRect(fx,FIN,8,14);}
 var now=performance.now();
 if(sc&&sc.c)for(var i=0;i<sc.c.length;i++){var q=sc.c[i];
  ctx.fillStyle="#000";ctx.fillRect(q[0]-10,q[1]-8,20,16);
  ctx.fillStyle="#6d4c2f";ctx.fillRect(q[0]-9,q[1]-1,18,8);
  ctx.fillStyle="#8a6238";ctx.fillRect(q[0]-9,q[1]-7,18,6);
  ctx.fillStyle="#caa64a";ctx.fillRect(q[0]-9,q[1]-2,18,2);
  ctx.fillStyle="#e8c35c";ctx.fillRect(q[0]-2,q[1]-3,4,5);}
 if(sc)for(var i=0;i<sc.b.length;i++){var b=sc.b[i];
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.beginPath();ctx.arc(b[0],b[1],b[4]+1.5,0,7);ctx.fill();
  var blink=b[3]<12&&(now/100|0)%2===0;
  ctx.fillStyle=blink?"#ff5936":BOMB[b[2]]||"#212126";
  ctx.beginPath();ctx.arc(b[0],b[1],b[4],0,7);ctx.fill();
  ctx.fillStyle="rgba(255,255,255,.2)";ctx.beginPath();ctx.arc(b[0]-b[4]/3,b[1]-b[4]/3,b[4]/4,0,7);ctx.fill();
  ctx.fillStyle=b[3]<12?"#ff5936":"#fff";ctx.font="bold 11px sans-serif";ctx.textAlign="center";
  ctx.fillText((b[3]/10).toFixed(1),b[0],b[1]-b[4]-6);}
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
  a.swing+=(stg-a.swing)*0.35;
  drawGuy(pos.x,pos.y,col,col2,p[5]===1,a.swing,a.face,air);
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
  ctx.fillStyle="rgba(0,0,0,.5)";ctx.fillRect(cw/2-130,ch*0.35-24,260,36);
  ctx.fillStyle="#ff8a80";ctx.font="bold 18px sans-serif";
  var msg=sc.p[you][3]<0?"eliminated — spectating":"respawn in "+(sc.p[you][3]/10).toFixed(1);
  ctx.fillText(msg,cw/2,ch*0.35);}
 if(win){ctx.fillStyle="rgba(0,0,0,.6)";ctx.fillRect(0,ch*0.3,cw,90);
  ctx.fillStyle="#"+win.c;ctx.font="bold 26px sans-serif";
  ctx.fillText(win.n.toUpperCase()+" WINS!",cw/2,ch*0.3+38);
  ctx.fillStyle="#ddd";ctx.font="14px sans-serif";
  ctx.fillText("waiting for host rematch…",cw/2,ch*0.3+66);}}
function y0(py){return py-20;}
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


func _process(delta: float) -> void:
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
					PAGE.replace("__WSPORT__", str(ws_port)).to_utf8_buffer())
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
		"k":
			# One-shot directional charged kick from the gesture layer.
			var kd := Vector2(float(msg.get("dx", 0)), float(msg.get("dy", 0)))
			c.kick_dir = kd if kd.length_squared() > 0.001 else Vector2.ZERO
			c.kick_power = clampf(float(msg.get("p", 1.0)), 0.2, 1.0)
		"c":
			c.color = Color.from_string(str(msg.get("c", "")), c.color)
			c.color2 = Color.from_string(str(msg.get("c2", "")), c.color)
