import fs from 'node:fs';
const root = 'build/usb_audit_2026-09-30/';
const {url} = JSON.parse(fs.readFileSync(root+'r3_web_config.json','utf8'));
const tabs = await (await fetch('http://127.0.0.1:9222/json')).json();
const tab = tabs.find(t => t.type==='page' && t.url===url) ?? tabs.find(t=>t.type==='page' && t.url.includes('shiftbell-29f31.web.app'));
if (!tab) throw Error('Audit tab missing');
const ws = new WebSocket(tab.webSocketDebuggerUrl);
let id=0;const pending=new Map();const errors=[];
function send(method,params={}) {return new Promise((resolve,reject)=>{
 const i=++id;const timer=setTimeout(()=>{pending.delete(i);reject(Error(method+' timeout'));},20000);
 pending.set(i,m=>{clearTimeout(timer);m.error?reject(Error(JSON.stringify(m.error))):resolve(m.result)});
 ws.send(JSON.stringify({id:i,method,params}));
});}
ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id);}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails);};
await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('CDP socket timeout')),10000);ws.onopen=()=>{clearTimeout(timer);resolve()};ws.onerror=()=>{clearTimeout(timer);reject(Error('CDP socket failed'))};});
await send('Page.bringToFront');await send('Runtime.enable');await send('Page.enable');
const mode=process.argv[2]??'first';
try {
 if(mode==='invalid') await send('Page.navigate',{url:'https://shiftbell-29f31.web.app/?code=SB2:a%2Fb'});
 else if(mode==='missing') await send('Page.navigate',{url:'https://shiftbell-29f31.web.app/'});
 else await send('Page.navigate',{url});
 let body='';
 for(let i=0;i<20;i++) {
  await new Promise(r=>setTimeout(r,1000));
  await send('Runtime.evaluate',{expression:'(()=>{function visit(r){r.querySelector("flt-semantics-placeholder")?.click();for(const e of r.querySelectorAll("*")){if(e.shadowRoot)visit(e.shadowRoot)}}visit(document)})()'});
  body=(await send('Runtime.evaluate',{expression:'(()=>{function text(r){let s=r.innerText||"";for(const e of r.querySelectorAll("*")){if(e.shadowRoot)s+="\\n"+text(e.shadowRoot)}return s}return text(document.body)})()',returnByValue:true})).result?.value??'';
  if(body.includes('USB Web Audit') || body.includes('공유 코드를') || body.includes('불러올 수') || body.includes('link') || body.includes('링크'))break;
 }
 fs.writeFileSync(root+'r3_web_'+mode+'.json',JSON.stringify({body,errors},null,2));
 const shot=await send('Page.captureScreenshot',{format:'png'});
 fs.writeFileSync(root+'r3_web_'+mode+'.png',Buffer.from(shot.data,'base64'));
 console.log(mode,JSON.stringify({body:body.slice(0,1600),errors:errors.length}));
} finally {ws.close();}
