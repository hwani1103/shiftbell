import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const adb='C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe';
const serial=process.env.SHIFTBELL_AUDIT_SERIAL;
if(!serial?.startsWith('localhost:'))throw Error('Explicit SRTL serial required');
const run=(...args)=>execFileSync(adb,['-s',serial,...args],{maxBuffer:20*1024*1024});
const out='build/srtl_2026-10-03_ultra_final';
const port=process.env.SRTL_WEB_PORT || '8095';
const suffix=process.env.SRTL_SCROLL_SUFFIX || 'bottom';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const tabs=await (await fetch('http://127.0.0.1:9222/json')).json();
const tab=tabs.find(t=>t.url.startsWith(`http://127.0.0.1:${port}/`));
const ws=new WebSocket(tab.webSocketDebuggerUrl);let id=0;const pending=new Map();
ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id);}};
await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
function send(method,params={}){return new Promise((r,j)=>{const n=++id;const timer=setTimeout(()=>j(Error('timeout')),15000);pending.set(n,m=>{clearTimeout(timer);m.error?j(Error(JSON.stringify(m.error))):r(m.result)});ws.send(JSON.stringify({id:n,method,params}));});}
try{
 run('shell','cmd','device_state','state','0');await sleep(3000);
 for(const lang of ['ko','en']){
  await send('Page.bringToFront');
  await send('Page.navigate',{url:`http://127.0.0.1:${port}/?lang=${lang}&pwa=1&scale=1.3`});await sleep(7000);
  run('shell','input','swipe','530','1900','530','700','500');await sleep(1000);
  const bytes=run('exec-out','screencap','-p');
  fs.writeFileSync(`${out}/friend_web_${lang}_closed_1.3_${suffix}.png`,bytes.subarray(bytes.indexOf(Buffer.from([137,80,78,71,13,10,26,10]))));
  console.log(lang,'bottom captured; visual review required');
 }
}finally{ws.close();}
