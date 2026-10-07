import fs from 'node:fs';
const out='build/usb_regional_audit_2026-10-06/';
const tabs=await(await fetch('http://127.0.0.1:9226/json')).json();
const tab=tabs.find(t=>t.url.startsWith('http://127.0.0.1:8096/'));
if(!tab)throw Error('Regional fixture tab missing');
const ws=new WebSocket(tab.webSocketDebuggerUrl);let id=0;const pending=new Map();const errors=[];
ws.onmessage=({data})=>{const m=JSON.parse(data);if(m.id){pending.get(m.id)?.(m);pending.delete(m.id)}else if(m.method==='Runtime.exceptionThrown')errors.push(m.params)};
await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
function send(method,params={}){return new Promise((r,j)=>{const i=++id;const timer=setTimeout(()=>j(Error(method+' timeout')),20000);pending.set(i,m=>{clearTimeout(timer);m.error?j(Error(JSON.stringify(m.error))):r(m.result)});ws.send(JSON.stringify({id:i,method,params}))})}
async function evaluate(expression){const v=await send('Runtime.evaluate',{expression,returnByValue:true});if(v.exceptionDetails)throw Error(JSON.stringify(v.exceptionDetails));return v.result?.value}
async function snapshot(name){const text=await evaluate('document.body.innerText');fs.writeFileSync(out+name+'.browser.json',JSON.stringify({text,errors,url:tab.url},null,2));const shot=await send('Page.captureScreenshot',{format:'png'});fs.writeFileSync(out+name+'.browser.png',Buffer.from(shot.data,'base64'));return text;}
try{
 await send('Page.enable');await send('Runtime.enable');await send('Page.bringToFront');
 if(process.argv[2]==='inspect'){
   console.log(await snapshot('browser_initial'));
   console.log(await evaluate(`Array.from(document.querySelectorAll('[role="button"]')).map(e=>({text:e.innerText,label:e.getAttribute('aria-label'),rect:JSON.stringify(e.getBoundingClientRect())}))`));
 }else{
   await send('Page.reload',{ignoreCache:true});await new Promise(r=>setTimeout(r,5000));
   const cases=[['en-US','Sunday','4/5/2026',0],['en-GB','Monday','05/04/2026',1],['en-ZA','Sunday','2026/04/05',0],['en-IN','Sunday','5/4/2026',0],['en-AE','Monday','4/5/2026',1],['en-PH','Sunday','4/5/2026',0],['de-DE','Montag','5.4.2026',1],['pt-BR','domingo','05/04/2026',0],['hi-IN','रविवार','5/4/2026',0],['ko','일요일','2026. 4. 5.',0]];
   const results=[];
   for(const [locale,day,date,first] of cases){
     const rect=await evaluate(`(()=>{const e=Array.from(document.querySelectorAll('[role="button"]')).find(e=>e.innerText===${JSON.stringify(locale)} || e.getAttribute('aria-label')===${JSON.stringify(locale)});if(!e)throw Error('button missing');const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})()`);
     await send('Input.dispatchMouseEvent',{type:'mousePressed',...rect,button:'left',clickCount:1});await send('Input.dispatchMouseEvent',{type:'mouseReleased',...rect,button:'left',clickCount:1});
     await new Promise(r=>setTimeout(r,1500));
     const text=await snapshot('browser_public_'+locale);
     const cells=await evaluate(`Array.from(document.querySelectorAll('[role="button"]')).map(e=>e.innerText).filter(t=>t.includes('2026'))`);
     const pass=text.includes('FORMAT '+date+' FIRST '+first)&&text.includes('Regional Audit')&&cells.length===42&&cells[0].toLowerCase().includes(day.toLowerCase())&&errors.length===0;
     const result={locale,day,date,first,text,cells,errors:[...errors],pass};results.push(result);fs.writeFileSync(out+'browser_public_results.json',JSON.stringify(results,null,2));console.log(locale,pass,cells[0],text.match(/FORMAT[^\n]*/)?.[0]);
   }
 }
}finally{ws.close()}
