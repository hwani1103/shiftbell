// Same dev VM assertions as usb_vm_audit.dart, without starting a Dart compiler
// for each small request. Uses Node's built-in WebSocket; no extra dependencies.
import fs from 'node:fs';
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const socket=new WebSocket(config.uri);
const pending=new Map();let next=0;
const timeout=setTimeout(()=>{console.error('VM request timed out; operation may still be running');process.exit(1);},((config.timeoutSeconds??90)+5)*1000);
socket.onmessage=({data})=>{
  const message=JSON.parse(data);
  if(message.id!==undefined){
    const task=pending.get(message.id);pending.delete(message.id);
    if(task)message.error?task.reject(Error(JSON.stringify(message.error))):task.resolve(message.result);
  }
};
function rpc(method,params={}){
  return new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});socket.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));});
}
try{
  await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject;});
  const vm=await rpc('getVM');const isolateId=vm.isolates.find(i=>i.name==='main').id;
  const isolate=await rpc('getIsolate',{isolateId});
  const targetId=isolate.libraries.find(l=>l.uri.endsWith(config.library)).id;
  let result=await rpc('evaluate',{isolateId,targetId,expression:config.expression});
  if(!['@Instance','Instance'].includes(result.type))throw Error(JSON.stringify(result));
  if(config.await && result.kind!=='String'){
    const deadline=Date.now()+(config.timeoutSeconds??90)*1000;
    while(true){
      if(Date.now()>deadline)throw Error('Remote Future timeout; operation may still be running');
      const object=await rpc('getObject',{isolateId,objectId:result.id});
      const fields=Object.fromEntries((object.fields??[]).map(f=>[f.decl?.name,f.value]));
      if(Number(fields._state?.valueAsString)>=4){
        result=fields._resultOrListeners;
        if(result?.class?.name==='_Future')continue;
        break;
      }
      await new Promise(r=>setTimeout(r,150));
    }
  }
  console.log(JSON.stringify(await rpc('getObject',{isolateId,objectId:result.id})));
}catch(error){console.error(String(error));process.exitCode=1;}
finally{clearTimeout(timeout);socket.close();}
