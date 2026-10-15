'use strict';
// Private data is stored only after explicit device opt-in. Never store credentials.
const OFFLINE_DB = 'ecc-offline-v1';
const OFFLINE_PREFIX = 'ecc-private-v1-';
const MODULES = '(contacts|deals|tasks|schools|students|agents|leads|cases|partners|invoices)';
const READ_RECORDS = new RegExp('^/api/' + MODULES + '(?:/[^/]+)?$');
const EDIT_RECORDS = /^\/api\/(contacts|deals|tasks|schools|students|agents|leads|cases|partners)\/([^/]+)(?:\/(stage|status))?$/;
const PLAN_RECORDS = /^\/api\/work-plans\/(leads|deals|cases|students)\/([^/]+)$/;
function editMatch(path) { const plan=path.match(PLAN_RECORDS);return plan?[plan[0],plan[1],plan[2],'plan']:path.match(EDIT_RECORDS) }
let offlineMode = null;
let offlineLock = Promise.resolve(), syncInProgress = null;
async function offlineFetch(request,options={}) {
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),12000);
 try{return await fetch(request,{...options,signal:controller.signal})}finally{clearTimeout(timer)}
}
function offlineDB() {
  return new Promise((resolve,reject)=>{const request=indexedDB.open(OFFLINE_DB,1);request.onupgradeneeded=()=>request.result.createObjectStore('state');request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error)});
}
async function offlineState(value) {
  const db=await offlineDB();
  return new Promise((resolve,reject)=>{const tx=db.transaction('state',value===undefined?'readonly':'readwrite'),store=tx.objectStore('state');let result;const request=value===undefined?store.get('current'):store.put(value,'current');request.onsuccess=()=>{result=request.result};tx.oncomplete=()=>{db.close();const state=value===undefined?(result||{enabled:false,jobs:[]}):value;offlineMode=!!state.enabled||!!state.logoutPending;resolve(state)};tx.onerror=()=>{db.close();reject(tx.error)}});
}
function offlineExclusive(fn) { const result=offlineLock.then(fn,fn);offlineLock=result.catch(()=>{});return result }
function privateCacheName(state) { return OFFLINE_PREFIX+encodeURIComponent(state.user.orgId)+':'+encodeURIComponent(state.user.id) }
function jsonResponse(body,status=200) { return new Response(JSON.stringify(body),{status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}}) }
async function notifyOffline() { for(const client of await self.clients.matchAll())client.postMessage({type:'ecc-offline-changed'}) }
async function clearPrivate(state={enabled:false,jobs:[]}) {
  for(const name of await caches.keys())if(name.startsWith(OFFLINE_PREFIX))await caches.delete(name);
  await offlineState(state);await notifyOffline();
}
function cacheableRead(path) { return path==='/api/me'||path==='/api/workspace-clock'||path==='/api/staff-options'||path==='/api/staff-directory'||PLAN_RECORDS.test(path)||READ_RECORDS.test(path)||/^\/api\/records\/(contacts|deals|tasks|schools|students|agents|leads|cases|partners|invoices)\/[^/]+$/.test(path) }
function identity(user) { return user?.orgId+':'+user?.id }
function overlayQueued(value,jobs) {
  if(!value||typeof value!=='object')return value;
  if(value.id){const job=jobs.find(j=>j.id===value.id);if(job)return {...value,...(job.patch||job.draft),_revision:job.revision,_offline:true}}
  if(Array.isArray(value))return value.map(v=>overlayQueued(v,jobs));
  return Object.fromEntries(Object.entries(value).map(([key,v])=>[key,overlayQueued(v,jobs)]));
}
async function cachedRecord(state,entity,id,expected) {
  const cache=await caches.open(privateCacheName(state));
  for(const path of ['/api/records/'+entity+'/'+encodeURIComponent(id),'/api/'+entity+'/'+encodeURIComponent(id)]){
    const res=await cache.match(new URL(path,self.location.origin).href);if(res){const data=await res.json();const record=data.record||data[entity==='cases'?'case':entity==='activities'?'activity':entity.slice(0,-1)];if(record?.id===id&&(!expected||record._revision===expected))return record}
  }
  for(const key of await cache.keys()){
    if(new URL(key.url).pathname!=='/api/'+entity)continue;
    const res=await cache.match(key),data=await res.json(),record=data[entity]?.find(r=>r.id===id);if(record&&(!expected||record._revision===expected))return record;
  }
  return null;
}
async function queueOfflineEdit(request,state) {
  if(!state.enabled||!state.user)return jsonResponse({message:'Enable offline work while connected first.'},503);
  const match=editMatch(new URL(request.url).pathname);
  if(!match||!['PUT','PATCH'].includes(request.method))return jsonResponse({message:'This action needs a connection. Offline mode supports editing existing records.'},503);
  if(state.user.role==='viewer')return jsonResponse({message:'Your role has read-only access'},403);
  if(!(request.headers.get('Content-Type')||'').includes('application/json'))return jsonResponse({message:'Uploads need a connection.'},503);
  const [ ,entity,encodedID]=match,id=decodeURIComponent(encodedID);
  const revision=request.headers.get('If-Match')?.replace(/^"|"$/g,'');
  let record=await cachedRecord(state,entity,id,revision);
  if(!record&&match[3]==='plan'){const cache=await caches.open(privateCacheName(state)),res=await cache.match(new URL('/api/work-plans/'+entity+'/'+encodedID,self.location.origin).href);if(res){const plan=await res.json();if(!plan.editable)return jsonResponse({message:'This plan is read only'},403);record={id,_revision:plan.revision}}}
  if(!record||!revision||record._revision!==revision)return jsonResponse({message:'Open this record online before editing offline. Its saved version is unavailable.'},428);
  let draft;try{draft=await request.json()}catch{return jsonResponse({message:'Invalid edit'},400)}
  if(!draft||Array.isArray(draft)||typeof draft!=='object'||JSON.stringify(draft).length>100000)return jsonResponse({message:'Offline edit is too large or invalid.'},400);
  // Payloads are drafts. The server validates fields, scope and business rules during sync.
  const existing=state.jobs.find(j=>j.id===id);
  if(existing&&existing.path!==new URL(request.url).pathname)return jsonResponse({message:'This record already has a queued edit. Sync or discard it before another type of change.'},409);
  if(existing&&existing.status!=='queued')return jsonResponse({message:'Review this record in Offline work before changing its pending edit.'},409);
  if(!existing&&state.jobs.length>=100)return jsonResponse({message:'Sync or discard pending edits before adding more.'},409);
  const patch=match[3]==='plan'?{nextAction:draft.nextAction,[entity==='leads'?'followUpDate':'nextDeadline']:draft.deadline}:draft;
  const job={patch,key:existing?.key||crypto.randomUUID(),entity,id,path:new URL(request.url).pathname,method:request.method,revision,draft,status:'queued',createdAt:existing?.createdAt||new Date().toISOString()};
  state.jobs=state.jobs.filter(j=>j.id!==id).concat(job);await offlineState(state);await notifyOffline();
  try { await self.registration.sync.register('ecc-record-edits') } catch {}
  const updated={...record,...patch,_revision:revision,_offline:true};
  if(match[3]==='plan')return jsonResponse({saved:true,offline:true},202);
  return jsonResponse({[entity==='cases'?'case':entity.slice(0,-1)]:updated,offline:true,message:'Saved on this device; awaiting server sync.'},202);
}
async function handlePrivateRequest(request) {
  const path=new URL(request.url).pathname;
  if(path==='/api/session/logout'||path==='/api/me/logout-all') {
    await offlineExclusive(()=>clearPrivate({enabled:false,jobs:[],logoutPending:true}));
    try{const response=await offlineFetch(request);if(response.ok)await offlineExclusive(()=>clearPrivate());return response}catch{return jsonResponse({message:'Signed out on this device. Server sign-out will finish when connected.'},202)}
  }
  let state;try{state=await offlineState()}catch{return fetch(request)}
  if(state.logoutPending){try{const response=await offlineFetch('/api/session/logout',{method:'POST',credentials:'include'});if(response.ok){await offlineExclusive(()=>clearPrivate());state=await offlineState()}}catch{};if(state.logoutPending)return jsonResponse({message:'Reconnect to finish signing out.'},401)}
  const copy=request.clone();
  if(state.enabled&&request.method!=='GET'&&request.method!=='HEAD'&&editMatch(path)){
    const pending=state.jobs.find(j=>j.id===decodeURIComponent(editMatch(path)[2]));
    if(pending)return offlineExclusive(async()=>queueOfflineEdit(copy,await offlineState()));
  }
  let response;
  try { response=await offlineFetch(request) } catch(error) {
    state=await offlineState();if(!state.enabled)throw error;
    // Elm bootstraps through refresh, not /me. This sentinel grants only local cached access.
    if(path==='/api/session/refresh'&&request.method==='POST')return jsonResponse({token:'cookie-session',user:state.user,offline:true});
    if(request.method==='GET'&&cacheableRead(path)){
      const cache=await caches.open(privateCacheName(state)),saved=await cache.match(copy);
      if(saved){let data=overlayQueued(await saved.json(),state.jobs);const plan=path.match(PLAN_RECORDS);if(plan){const job=state.jobs.find(j=>j.id===decodeURIComponent(plan[2]));if(job)data={...data,nextAction:job.patch.nextAction,deadline:job.patch[plan[1]==='leads'?'followUpDate':'nextDeadline'],revision:job.revision}}return jsonResponse(data)}
      const recordPath=path.match(/^\/api\/(?:records\/)?(contacts|deals|tasks|schools|students|agents|leads|cases|partners|invoices)\/([^/]+)$/);
      if(recordPath){const record=await cachedRecord(state,recordPath[1],decodeURIComponent(recordPath[2]));if(record){const edited=overlayQueued(record,state.jobs);return path.startsWith('/api/records/')?jsonResponse({record:edited,editable:state.user.role!=='viewer'&&(state.user.role==='admin'||state.user.role==='manager'||record.ownerId===state.user.id)}):jsonResponse({[recordPath[1]==='cases'?'case':recordPath[1].slice(0,-1)]:edited})}}
      return jsonResponse({message:'This view has not been saved on this device. Open it online first.'},503);
    }
    return offlineExclusive(async()=>queueOfflineEdit(copy,await offlineState()));
  }
  try {
    if(['/api/me','/api/login','/api/register','/api/sso/finish','/api/session/refresh'].includes(path)&&response.ok){
      const data=await response.clone().json();
      await offlineExclusive(async()=>{state=await offlineState();if(!data.user)return;if(state.enabled&&identity(state.user)!==identity(data.user))await clearPrivate();else if(state.enabled){state.user=data.user;await offlineState(state);const cache=await caches.open(privateCacheName(state));await cache.put(new URL('/api/me',self.location.origin).href,jsonResponse({user:data.user}))}});
    }
    // Cache writes share the same lock as logout and account changes.
    return await offlineExclusive(async()=>{
      state=await offlineState();
      if(state.enabled&&request.method==='GET'&&cacheableRead(path)){
        const cache=await caches.open(privateCacheName(state));
        if(response.ok&&response.headers.get('content-type')?.includes('application/json')){await cache.put(copy,response.clone());const keys=await cache.keys();if(keys.length>250)for(const key of keys.slice(0,keys.length-250))if(new URL(key.url).pathname!=='/api/me')await cache.delete(key)}
        if(response.status===403||response.status===404)await cache.delete(copy);
        if(response.ok&&state.jobs.length){let data=overlayQueued(await response.clone().json(),state.jobs);const plan=path.match(PLAN_RECORDS);if(plan){const job=state.jobs.find(j=>j.id===decodeURIComponent(plan[2]));if(job)data={...data,nextAction:job.patch.nextAction,deadline:job.patch[plan[1]==='leads'?'followUpDate':'nextDeadline'],revision:job.revision}}return jsonResponse(data)}
      }
      return response;
    });
  } catch { return response }

}
async function refreshSyncedRecord(state,job,response) {
 const data=await response.clone().json();let record=data[job.entity==='cases'?'case':job.entity.slice(0,-1)];
 if(!record){const latest=await offlineFetch('/api/records/'+job.entity+'/'+encodeURIComponent(job.id),{credentials:'include'});if(latest.ok)record=(await latest.json()).record}
 if(!record)return;
 const cache=await caches.open(privateCacheName(state));
 function replace(value){if(!value||typeof value!=='object')return value;if(value.id===job.id)return record;if(Array.isArray(value))return value.map(replace);return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,replace(v)]))}
 for(const key of await cache.keys()){
  const path=new URL(key.url).pathname;if(path==='/api/me'||path.includes('staff-'))continue;
  const saved=await cache.match(key);let value=await saved.json();
  if(PLAN_RECORDS.test(path)&&decodeURIComponent(path.match(PLAN_RECORDS)[2])===job.id)value={...value,nextAction:record.nextAction,deadline:record[job.entity==='leads'?'followUpDate':'nextDeadline'],revision:record._revision};else value=replace(value);
  await cache.put(key,jsonResponse(value));
 }
}
async function syncOfflineJobs() {
 if(syncInProgress)return syncInProgress;
 syncInProgress=offlineExclusive(async()=>{
  const state=await offlineState();if(!state.enabled||!state.jobs.length)return;
  let me=await offlineFetch('/api/me',{credentials:'include'});
  if(me.status===401){const refresh=await offlineFetch('/api/session/refresh',{method:'POST',credentials:'include'});if(refresh.ok)me=await offlineFetch('/api/me',{credentials:'include'})}
  if(!me.ok){await caches.delete(privateCacheName(state));for(const job of state.jobs){job.status='blocked';job.error='Sign in to the same account before syncing.'}await offlineState(state);return}
  const user=(await me.json()).user;
  if(identity(user)!==identity(state.user)){await clearPrivate();return}
  state.user=user;
  for(const job of [...state.jobs]){
   if(job.status!=='queued')continue;
   let response;try{response=await offlineFetch(job.path,{method:job.method,credentials:'include',headers:{'Content-Type':'application/json','If-Match':job.revision},body:JSON.stringify(job.draft)})}catch{break}
   if(response.ok){state.jobs=state.jobs.filter(j=>j.key!==job.key);try{await refreshSyncedRecord(state,job,response)}catch{} }
   else {job.status=response.status===409?'conflict':'blocked';let data;try{data=await response.json()}catch{}job.error=data?.message||'Server rejected the edit ('+response.status+').';if(response.status===401||response.status===403)await caches.delete(privateCacheName(state))}
   await offlineState(state);
  }
  await offlineState(state);
 }).finally(async()=>{syncInProgress=null;await notifyOffline()});
 return syncInProgress;
}
async function offlineCommand(data) {
 if(data.action==='status'){const state=await offlineState();return {enabled:state.enabled,user:state.user,jobs:state.jobs}}
 if(data.action==='disable'){await offlineExclusive(()=>clearPrivate());return {enabled:false,jobs:[]}}
 if(data.action==='enable')return offlineExclusive(async()=>{
  const response=await offlineFetch('/api/me',{credentials:'include'});if(!response.ok)throw new Error('Sign in online before enabling offline work.');const body=await response.json();
  const existing=await offlineState();if(existing.enabled&&identity(existing.user)===identity(body.user))return {enabled:true,user:existing.user,jobs:existing.jobs};
  await clearPrivate({enabled:true,user:body.user,jobs:[]});const state=await offlineState(),cache=await caches.open(privateCacheName(state));await cache.put(new URL('/api/me',self.location.origin).href,jsonResponse(body));return {enabled:true,user:state.user,jobs:[]};
 });
 if(data.action==='sync'){await syncOfflineJobs();return offlineCommand({action:'status'})}
 if(data.action==='discard')return offlineExclusive(async()=>{const state=await offlineState();state.jobs=state.jobs.filter(j=>j.key!==data.key);await offlineState(state);await notifyOffline();return {enabled:state.enabled,user:state.user,jobs:state.jobs}});
 if(data.action==='review'){
  const state=await offlineState(),job=state.jobs.find(j=>j.key===data.key);if(!job)throw new Error('Pending edit not found.');
  const me=await offlineFetch('/api/me',{credentials:'include'});if(!me.ok||identity((await me.json()).user)!==identity(state.user))throw new Error('Sign in online to the original account.');
  const response=await offlineFetch('/api/records/'+job.entity+'/'+encodeURIComponent(job.id),{credentials:'include'});if(!response.ok)throw new Error('This record is no longer accessible.');const out=await response.json();if(!out.editable)throw new Error('You no longer have edit access.');return {record:out.record,job};
 }
 if(data.action==='retry')return offlineExclusive(async()=>{
  if(!data.confirmed||!data.revision)throw new Error('Review and confirm the saved record first.');
  const state=await offlineState(),job=state.jobs.find(j=>j.key===data.key);if(!job)throw new Error('Pending edit not found.');
  job.revision=data.revision;job.status='queued';delete job.error;await offlineState(state);return {enabled:state.enabled,user:state.user,jobs:state.jobs};
 });
 throw new Error('Unknown offline command');
}
self.addEventListener('message',event=>{if(event.data?.type!=='ecc-offline')return;event.waitUntil(offlineCommand(event.data).then(result=>event.ports[0]?.postMessage({result})).catch(error=>event.ports[0]?.postMessage({error:error.message})))});
self.addEventListener('sync',event=>{if(event.tag==='ecc-record-edits')event.waitUntil(syncOfflineJobs())});

const offlineReady = offlineState().catch(() => { offlineMode=false });
