'use strict';
// Tab-local recovery, scoped to the original account and exact component/record.
(() => {
 const prefix='ecc:session-draft:v1:';
 let active=false;try{active=Object.keys(sessionStorage).some(key=>key.startsWith(prefix))}catch{}
 const owner=()=>document.querySelector('#workspace-navigation')?.getAttribute('data-user-id');
 const controls=form=>[...form.querySelectorAll('input,textarea,select,crm-record-picker,crm-staff-picker')].filter(e=>
  !['password','file','checkbox','radio','hidden','submit','button'].includes(e.type)&&
  !/password|secret|token|otp|verification|consent/i.test((e.name||'')+' '+(e.id||'')));
 const fields=form=>controls(form).map((e,index)=>({key:e.id||(e.name||e.localName)+':'+index,value:e.value||''}));
 const roots=()=>{
  const out=[];
  const visit=(root,path)=>{const counts=new Map();for(const el of root.querySelectorAll('*'))if(el.shadowRoot){const base=el.localName+':'+(el.getAttribute('entity')||'')+':'+(el.getAttribute('record-id')||'');const index=counts.get(base)||0;counts.set(base,index+1);const key=path+'/'+base+':'+index;out.push([el.shadowRoot,key]);visit(el.shadowRoot,key)}};
  visit(document,'');return out;
 };
 const keyFor=(user,path,index,form)=>prefix+JSON.stringify([user,location.pathname,location.search||'',location.hash||'',path,index,form.closest('.card,section,article')?.querySelector('h2,h3')?.textContent||'',fields(form).map(field=>field.key)]);
 const submissions=new WeakMap();
 function saved(form,result){
  if(result?.offline)return false;
  const attempt=submissions.get(form);if(!attempt||owner()!==attempt.owner)return false;
  submissions.delete(form);
  try{
   if(JSON.stringify(fields(form))!==attempt.fields||sessionStorage.getItem(attempt.key)!==attempt.fields)return false;
   sessionStorage.removeItem(attempt.key);attempt.state.active=false;attempt.box.remove();return true;
  }catch{return false}
 }
 let applying=false;
 function capture(user){
  if(!user)return;
  active=true;
  for(const [root,path]of roots())for(const [index,form]of [...root.querySelectorAll('form')].entries()){
   const values=fields(form);if(!values.length)continue;
   try{sessionStorage.setItem(keyFor(user,path,index,form),JSON.stringify(values))}catch{}
  }
 }
 function offer(){
  if(applying||!owner())return;
  for(const [root,path]of roots())for(const [index,form]of [...root.querySelectorAll('form')].entries()){
   if(form.querySelector('[data-session-recovery]'))continue;
   const key=keyFor(owner(),path,index,form);let saved;
   try{saved=JSON.parse(sessionStorage.getItem(key))}catch{}
   if(!Array.isArray(saved))continue;
   const box=document.createElement('fieldset');box.setAttribute('data-session-recovery','');
   const title=document.createElement('legend');title.textContent='Unsaved entries from your expired session';
   const restore=document.createElement('button');restore.type='button';restore.textContent='Restore unsaved entries';
   const discard=document.createElement('button');discard.type='button';discard.textContent='Discard unsaved entries';
   const status=document.createElement('p');status.setAttribute('role','status');status.textContent='Files, passwords and confirmation checkboxes must be entered again.';
   box.append(title,status,restore,discard);form.prepend(box);
   const state={active:true};
   const persist=()=>{if(!state.active)return;try{sessionStorage.setItem(key,JSON.stringify(fields(form)))}catch{}};
   form.addEventListener('input',persist);form.addEventListener('change',persist);
   form.addEventListener('submit',()=>{
    if(!state.active)return;
    const submitted=JSON.stringify(fields(form));
    try{sessionStorage.setItem(key,submitted)}catch{}
    submissions.set(form,{key,owner:owner(),fields:submitted,box,state});
   },{capture:true});
   discard.onclick=()=>{state.active=false;submissions.delete(form);sessionStorage.removeItem(key);box.remove()};
   restore.onclick=()=>{
    applying=true;
    try{
     const latest=controls(form),comparison=document.createElement('details'),summary=document.createElement('summary');summary.textContent='Compare with the latest loaded values';comparison.append(summary);
     for(const [i,e]of latest.entries()){
      const field=saved.find(f=>f.key===(e.id||(e.name||e.localName)+':'+i));if(!field)continue;
      if(e.value!==field.value){const line=document.createElement('p');line.textContent=(e.getAttribute('aria-label')||e.name||e.id||'Field')+': loaded value '+(e.value||'(empty)')+'; your draft '+(field.value||'(empty)');comparison.append(line)}
      e.value=field.value;for(const event of ['input','change'])e.dispatchEvent(new Event(event,{bubbles:true,composed:true}));
     }
     const label=document.createElement('label'),review=document.createElement('input');review.type='checkbox';label.append(review,document.createTextNode(' I compared my entries with the latest loaded values before saving.'));
     form.addEventListener('submit',event=>{if(state.active&&!review.checked){event.preventDefault();event.stopImmediatePropagation();status.textContent='Compare the loaded values and confirm your review before saving.'}},{capture:true});
     restore.disabled=true;box.append(comparison,label);status.textContent='Entries restored. Review any changed values before saving.';
     review.onchange=()=>{status.textContent=review.checked?'Review confirmed. You can save your entries.':'Compare the loaded values before saving.'};
    }finally{applying=false}
   };
  }
 }
 let scheduled=false;
 const schedule=()=>{if(scheduled)return;scheduled=true;queueMicrotask(()=>{scheduled=false;offer()})};
 const observe=root=>new MutationObserver(()=>scan()).observe(root,{childList:true,subtree:true});
 observe(document.body);
 // New components and asynchronously loaded forms may have their own shadow root.
 const observed=new WeakSet();
 const scan=()=>{if(!active)return;for(const [root]of roots())if(!observed.has(root)){observed.add(root);observe(root)}schedule()};
 new MutationObserver(scan).observe(document.body,{childList:true,subtree:true});
 window.CRMSessionDrafts={capture,saved};scan();
})();
