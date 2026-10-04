import fs from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const out=(process.env.SHIFTBELL_AUDIT_OUT || 'build/srtl_2026-10-03_ultra')+'/';
const device=process.env.SRTL_DEVICE_NAME || 'Fold8Ultra';
const port=process.env.SRTL_WEB_PORT || '8094';
const base=`http://127.0.0.1:${port}/`;
const scale=process.env.SRTL_SCALE || '1.0';
const buildDir=process.env.SRTL_WEB_BUILD || 'build/srtl_web_fixture';
const dest=`${process.env.SRTL_CAPTURE_ROOT || 'artifacts/srtl_2026-10-03'}/${device}/${process.env.SRTL_CAPTURE_SET || 'numbered_v2'}/`;
const catalog=JSON.parse(fs.readFileSync('artifacts/srtl_2026-10-03/capture_catalog.json','utf8'));
const selectedNumbers=new Set((process.env.SRTL_CAPTURE_NUMBERS || '').split(',').filter(Boolean).map(n=>n.trim().padStart(3,'0')));
fs.mkdirSync(dest,{recursive:true});
const adb='C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe';
const serial=process.env.SHIFTBELL_AUDIT_SERIAL;
if(!serial?.startsWith('localhost:'))throw Error('Explicit SRTL serial required');
const run=(...args)=>execFileSync(adb,['-s',serial,...args],{maxBuffer:20*1024*1024});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const tabs=await (await fetch('http://127.0.0.1:9222/json')).json();
const tab=tabs.find(t=>t.url.startsWith(base));
if(!tab)throw Error('Local fixture tab missing');
const ws=new WebSocket(tab.webSocketDebuggerUrl);let id=0;const pending=new Map();const errors=[];
ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params);};
await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
function send(method,params={}){return new Promise((resolve,reject)=>{const n=++id;const timer=setTimeout(()=>reject(Error('Timeout '+method)),20000);pending.set(n,m=>{clearTimeout(timer);m.error?reject(Error(JSON.stringify(m.error))):resolve(m.result)});ws.send(JSON.stringify({id:n,method,params}));});}
try{
 await send('Page.enable');await send('Runtime.enable');
 for(const state of ['closed','open']){
  if(process.env.SRTL_POSTURE && process.env.SRTL_POSTURE!==state)continue;
  run('shell','cmd','device_state','state',state==='closed'?'0':'3');await sleep(2500);
  run('shell','input','keyevent','KEYCODE_WAKEUP');run('shell','wm','dismiss-keyguard');
  for(const lang of ['ko','en'])for(const pwa of [0,1]){
   const row=catalog.captures.find(r=>r.screen==='friend' && r.variant===`pwa${pwa}` && r.posture===state && r.language===(lang==='ko'?'ko-KR':'en-US'));
   if(selectedNumbers.size && !selectedNumbers.has(row.number))continue;
   const name=`friend_web_${lang}_${state}_pwa${pwa}`;
   const url=`${base}?lang=${lang}&pwa=${pwa}&scale=${scale}`;
   await send('Page.bringToFront');
   await send('Page.navigate',{url});await sleep(7000);
   await send('Input.dispatchMouseEvent',{type:'mousePressed',x:5,y:5,button:'left',clickCount:1});
   await send('Input.dispatchMouseEvent',{type:'mouseReleased',x:5,y:5,button:'left',clickCount:1});
   // Chrome's own first-run tooltip is outside the page/CDP input target.
   run('shell','input','tap','600','1000');await sleep(1000);
   const actualUrl=await send('Runtime.evaluate',{expression:'location.href',returnByValue:true});
   if(actualUrl.result.value!==url)throw Error('Capture page changed: '+actualUrl.result.value);
   const visible=await send('Runtime.evaluate',{expression:'document.visibilityState',returnByValue:true});
   if(visible.result.value!=='visible')throw Error('Capture tab is not visible');
   await send('Runtime.evaluate',{expression:'(()=>{function visit(r){r.querySelector("flt-semantics-placeholder")?.click();for(const e of r.querySelectorAll("*")){if(e.shadowRoot)visit(e.shadowRoot)}}visit(document)})()'});
   await sleep(500);
   const rendered=await send('Runtime.evaluate',{expression:'document.body.innerText',returnByValue:true});
   const renderedText=rendered.result?.value || '';
   // Mobile CanvasKit may keep semantics disabled without a screen reader.
   // Record that limitation; final PNGs still require visual language review.
   const scene=await send('Runtime.evaluate',{expression:'(()=>{let n=0;function visit(r){n+=r.querySelectorAll("canvas").length;for(const e of r.querySelectorAll("*")){if(e.shadowRoot)visit(e.shadowRoot)}}visit(document);return n})()',returnByValue:true});
   if(!scene.result?.value)throw Error('Flutter canvas not rendered');
   if(renderedText && !renderedText.includes(lang==='ko'?'교대근무 동료의 일정':'Colleague Work Schedule'))throw Error('Expected localized calendar missing: '+renderedText);
   if(lang==='en' && /개천절|한글날|대체공휴일/.test(renderedText))throw Error('Korean holiday in English calendar');
   if(errors.length)throw Error('Browser runtime exception: '+JSON.stringify(errors));
   const data=run('exec-out','screencap','-p');const start=data.indexOf(Buffer.from([137,80,78,71,13,10,26,10]));
   if(start<0)throw Error('Missing PNG');fs.writeFileSync(out+name+'.png',data.subarray(start));
   const metrics=await send('Runtime.evaluate',{expression:'JSON.stringify({url:location.href,width:innerWidth,height:innerHeight,dpr:devicePixelRatio})',returnByValue:true});
   fs.writeFileSync(out+name+'.json',JSON.stringify({metrics:metrics.result.value,errors},null,2));console.log(name,metrics.result.value);
   fs.writeFileSync(dest+row.filename,data.subarray(start));
   const manifestPath=dest+'manifest.json';
   const manifest=fs.existsSync(manifestPath)?JSON.parse(fs.readFileSync(manifestPath,'utf8')):{device,serial,captures:[]};
   manifest.captures=manifest.captures.filter(r=>r.number!==row.number);
   manifest.captures.push({...row,font_scale:scale,status:'captured',source:'local production-widget fixture; explicit MediaQuery scale; no live sharing/PWA installation claim',
     sha256:createHash('sha256').update(data.subarray(start)).digest('hex'),
     web_build_sha256:createHash('sha256').update(fs.readFileSync(buildDir+'/main.dart.js')).digest('hex'),
     metrics:JSON.parse(metrics.result.value),renderedText,textVerification:renderedText?'semantic text checked':'visual review required; semantics unavailable',errors});
   fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2));
  }
 }
}finally{ws.close();}
