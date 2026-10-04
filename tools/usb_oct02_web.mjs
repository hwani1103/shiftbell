import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const root='build/usb_audit_2026-10-02/';
const config=JSON.parse(fs.readFileSync(root+'web_config.json','utf8'));
const url=process.env.SHIFTBELL_WEB_URL_OVERRIDE??(process.env.SHIFTBELL_WEB_BASE
 ? config.url.replace('https://shiftbell-29f31.web.app',process.env.SHIFTBELL_WEB_BASE)
 : config.url);
const prefix=process.env.SHIFTBELL_WEB_BASE?'web_local_':'web_';
const mode=process.argv[2]??'newtab';
const oldIds=new Set((await (await fetch('http://127.0.0.1:9222/json')).json()).map(t=>t.id));
execFileSync('C:/Users/Administrator/AppData/Local/Android/sdk/platform-tools/adb.exe',
 ['-s','R5KL20DHWAE','shell','input','keycombination','KEYCODE_CTRL_LEFT','KEYCODE_T']);
let created;
for(let i=0;i<10;i++){
 await new Promise(r=>setTimeout(r,500));
 created=(await (await fetch('http://127.0.0.1:9222/json')).json()).find(t=>t.type==='page'&&!oldIds.has(t.id));
 if(created)break;
}
if(!created)throw Error('Chrome did not create a dedicated new tab');
const ws=new WebSocket(created.webSocketDebuggerUrl);
let id=0;const pending=new Map();
function send(method,params={}){return new Promise((resolve,reject)=>{
 const n=++id;const timer=setTimeout(()=>{pending.delete(n);reject(Error(method+' timed out'));},20000);
 pending.set(n,m=>{clearTimeout(timer);m.error?reject(Error(JSON.stringify(m.error))):resolve(m.result)});
 ws.send(JSON.stringify({id:n,method,params}));
});}
ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id);}};
await new Promise((resolve,reject)=>{ws.onopen=resolve;ws.onerror=reject;});
try{
 await send('Page.enable');await send('Runtime.enable');await send('Network.enable');
 if(mode==='blocked')await send('Network.setBlockedURLs',{urls:['*firestore.googleapis.com*']});
 await send('Page.navigate',{url});
 let body='';
 for(let n=0;n<25;n++){
  await new Promise(r=>setTimeout(r,1000));
  await send('Runtime.evaluate',{expression:'(()=>{function visit(r){r.querySelector("flt-semantics-placeholder")?.click();for(const e of r.querySelectorAll("*")){if(e.shadowRoot)visit(e.shadowRoot)}}visit(document)})()'});
  body=(await send('Runtime.evaluate',{expression:'(()=>{function text(r){let s=r.innerText||"";for(const e of r.querySelectorAll("*")){if(e.shadowRoot)s+="\\n"+text(e.shadowRoot)}return s}return text(document.body)})()',returnByValue:true})).result?.value??'';
  if(mode==='newtab' && body.includes('Oct02 Web Audit'))break;
  if(mode==='blocked' && /retry|다시 시도|불러올 수|연결|network/i.test(body))break;
 }
 fs.writeFileSync(root+prefix+mode+'.json',JSON.stringify({body,mode},null,2));
 const shot=await send('Page.captureScreenshot',{format:'png'});
 fs.writeFileSync(root+prefix+mode+'.png',Buffer.from(shot.data,'base64'));
 if(mode==='blocked'||mode==='reload'){
  const beforeUrl=(await send('Runtime.evaluate',{expression:'location.href',returnByValue:true})).result?.value;
  await send('Network.setBlockedURLs',{urls:[]});
  await send('Page.reload');
  await new Promise(r=>setTimeout(r,15000));
  const afterUrl=(await send('Runtime.evaluate',{expression:'location.href',returnByValue:true})).result?.value;
  fs.writeFileSync(root+prefix+mode+'_urls.json',JSON.stringify({beforeUrl,afterUrl},null,2));
  const recovered=await send('Page.captureScreenshot',{format:'png'});
  fs.writeFileSync(root+prefix+mode+'_recovered.png',Buffer.from(recovered.data,'base64'));
 }
 console.log('CAPTURED for visual verification',mode,body.slice(0,1200));
}finally{
 try{await send('Network.setBlockedURLs',{urls:[]});}catch{}
 ws.close();
 await fetch('http://127.0.0.1:9222/json/close/'+created.id);
}
