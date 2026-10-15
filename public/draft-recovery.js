'use strict';
// Session-only recovery for record modals. Consent, files and passwords are never restored.
(function(){
 const attached=new WeakMap(),pending=new Map();let candidate=null,draftSequence=0;
 const user=()=>document.querySelector('#workspace-navigation')?.getAttribute('data-user-id');
 const controls=form=>[...form.querySelectorAll('input,textarea,select,crm-staff-picker,crm-record-picker')].filter(e=>!['password','file','checkbox','radio','hidden','submit'].includes(e.type));
 const snapshot=form=>controls(form).map((e,index)=>({key:e.id||e.name||e.tagName+':'+index,value:e.value??e.getAttribute('value')??''}));
 function attach(){if(!user())return;for(const form of document.querySelectorAll('.modal form,form.modal,[role=dialog] form')){
  const host=form.querySelector('crm-draft-recovery');if(!host)continue;const title=form.closest('.modal,[role=dialog]')?.querySelector('h2,h3')?.textContent||'Record';const recordId=form.closest('[data-draft-record-id]')?.getAttribute('data-draft-record-id')||host.getAttribute('record-id');if(!recordId)continue;const key='ecc:modal-draft:v2:'+JSON.stringify([user(),location.pathname,title,recordId]);const previous=attached.get(form);if(previous?.key===key)continue;previous?.controller.abort();host.replaceChildren();const controller=new AbortController();const original=JSON.stringify(snapshot(form));const data={key,original,recordId,controller,versions:window.crmDraftRevisions?.()||{},pending:false};attached.set(form,data);
  const panel=document.createElement('div');panel.className='draft-recovery';panel.setAttribute('role','status');panel.setAttribute('aria-live','polite');host.append(panel);
  let saved;try{saved=JSON.parse(sessionStorage.getItem(key))}catch{}
  if(saved){panel.textContent='An unsaved '+title.toLowerCase()+' draft is available. ';const restore=document.createElement('button');restore.type='button';restore.className='ecc-btn ecc-btn--ghost ecc-btn--inline';restore.textContent='Restore draft';const discard=restore.cloneNode();discard.textContent='Discard draft';
   restore.onclick=()=>{if(saved.original!==original&&!window.confirm('The saved record differs from this draft. Confirm this is the same record and compare the restored fields before saving.'))return;const fields=controls(form);for(const field of saved.fields||[]){const element=fields.find((e,index)=>(e.id||e.name||e.tagName+':'+index)===field.key);if(!element)continue;element.value=field.value;for(const event of ['input','change'])element.dispatchEvent(new Event(event,{bubbles:true,composed:true}))}data.versions=saved.versions||{};window.dispatchEvent(new CustomEvent('crm:restore-draft-versions',{detail:data.versions}));panel.replaceChildren(document.createTextNode('Draft restored. Reselect files and review the fields. '));const label=document.createElement('label'),confirm=document.createElement('input');confirm.type='checkbox';label.append(confirm,document.createTextNode(' I compared the latest saved record and want to use its current version.'));confirm.onchange=()=>window.dispatchEvent(new CustomEvent('crm:restore-draft-versions',{detail:confirm.checked?(window.crmDraftRevisions?.()||{}):data.versions}));panel.append(label)};
   discard.onclick=()=>{try{sessionStorage.removeItem(key)}catch{}panel.remove()};panel.append(restore,discard)
  }else panel.remove();
  const store=()=>{const draftVersion=++draftSequence;try{sessionStorage.setItem(key,JSON.stringify({original,fields:snapshot(form),versions:data.versions,draftVersion}))}catch{}return draftVersion};form.addEventListener('input',store,{signal:controller.signal});form.addEventListener('change',store,{signal:controller.signal});
  form.addEventListener('submit',event=>{if(data.pending){event.preventDefault();event.stopImmediatePropagation();return}candidate={form,data,submitted:JSON.stringify(snapshot(form)),draftVersion:store()}},{capture:true,signal:controller.signal});
 }}
 window.addEventListener('crm:save-start',event=>{if(event.detail.requestId!=null&&candidate?.form.isConnected){const attempt={...candidate,path:event.detail.path};pending.set(event.detail.requestId,attempt);attempt.data.pending=true;candidate=null}});
 window.addEventListener('crm:save-result',event=>{
  const attempt=pending.get(event.detail.requestId);
  if(!attempt||event.detail.path!==attempt.path)return;
  pending.delete(event.detail.requestId);
  const{form,data}=attempt,status=event.detail.status;data.pending=false;
  const host=form.querySelector('crm-draft-recovery');host?.querySelector('.save-recovery')?.remove();
  if(status>=200&&status<300){try{if(JSON.stringify(snapshot(form))===attempt.submitted&&JSON.parse(sessionStorage.getItem(data.key))?.draftVersion===attempt.draftVersion)sessionStorage.removeItem(data.key)}catch{}}
  else if(host){
   const panel=document.createElement('div');panel.className='draft-recovery save-recovery';panel.setAttribute('role','alert');
   const heading=document.createElement('strong'),message=document.createElement('p');
   if(status===409||status===412){heading.textContent='Save needs review';message.textContent='The server rejected this save. Your draft is kept in this tab. Check the error below. If the record changed, close this form, refresh the record, and reopen Edit. Use Restore draft and compare your fields with the latest record before saving again.'}
   else if(status===0||status>=500){heading.textContent='Save could not be confirmed';message.textContent='Your draft is kept in this tab. Check your connection, then close this form and refresh the record to see whether the change was saved. If it was not, reopen the form and restore your draft before retrying. Check for an existing record before creating another.'}
   else if(status===401){heading.textContent='Sign in to continue';message.textContent='Your session expired. Your draft is kept in this tab. Sign in with the same account, reopen this record, and use Restore draft.'}
   else if(status===403){heading.textContent='Permission required';message.textContent='Your draft is kept in this tab. Ask your workspace administrator to check your access before trying again.'}
   else{heading.textContent='Changes were not saved';message.textContent='Your fields are still in this form and your draft is kept in this tab. Correct the highlighted fields or the issue described below, then save again.'}
   panel.append(heading,message);host.append(panel);
  }
 });
 new MutationObserver(attach).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['data-draft-record-id','record-id','user-id']});attach();
})();
