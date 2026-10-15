'use strict';
(() => {
 const node=(tag,text,attrs={})=>{const e=document.createElement(tag);if(text!=null)e.textContent=String(text);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);return e};
 const field=(form,label,input)=>{const l=node('label',label);l.append(input);form.append(l);return input};
 const select=(label,options,value='')=>{const e=node('select',null,{'aria-label':label});for(const[v,t]of options)e.append(node('option',t,{value:v}));e.value=value;return e};
 const localDate=value=>value?new Date(new Date(value).getTime()-new Date(value).getTimezoneOffset()*60000).toISOString().slice(0,16):'';
 const save=(request,path,data,revision,method='PATCH')=>request(path,{method,headers:{'Content-Type':'application/json',...(revision?{'If-Match':revision}:{})},body:JSON.stringify(data)});
 function handling(card,row,{request,editable},reload){
  if(row.direction!=='inbound'||row.source!=='conversation')return;
  const form=node('form',null,{class:'communication-compose'}),notice=node('p','',{role:'status'});
  const state=field(form,'Handling',select('Message handling',[['needs_reply','Needs reply'],['assigned','Assigned'],['resolved','Resolved']],row.handlingStatus||'needs_reply'));
  const staff=field(form,'Responsible staff',select('Responsible staff',[['','Unassigned']],''));
  const due=field(form,'Response deadline (your device timezone)',node('input',null,{type:'datetime-local'}));due.value=localDate(row.responseDue);
  if(row.responseDue)form.append(node('p','Saved deadline: '+new Date(row.responseDue).toLocaleString()));
  const submit=node('button','Save handling',{type:'submit'});submit.disabled=!editable;form.append(submit,notice);card.append(form);
  const entity=row.caseId?'cases':'contacts',id=row.caseId||row.contactId;
  request('/api/staff-options?'+new URLSearchParams(id?{entity,id}:{})).then(out=>{if(!form.isConnected)return;for(const person of out.staff||[])staff.append(node('option',person.name,{value:person.id}));staff.value=row.assignedTo||'';}).catch(e=>{notice.textContent=e.message;submit.disabled=true;});
  form.oninput=()=>{card.dataset.dirty='true'};
  form.onsubmit=async event=>{event.preventDefault();if(submit.disabled)return;submit.disabled=true;try{await save(request,'/api/communication/'+encodeURIComponent(row.id)+'/handling',{status:state.value,assignedTo:staff.value,responseDue:due.value?new Date(due.value).toISOString():''},row.handlingRevision);card.dataset.dirty='false';reload()}catch(e){notice.textContent=e.message+' Your entries are kept.';submit.disabled=!editable}};
  if(row.channel==='portal'&&editable){const replies=node('form',null,{class:'communication-compose'});const body=field(replies,'Reply in client portal',node('textarea',null,{required:'',maxlength:'10000',rows:'4'}));const send=node('button','Send portal reply',{type:'submit'}),status=node('p','',{role:'status'});replies.append(send,status);card.append(replies);replies.oninput=()=>{card.dataset.dirty='true'};replies.onsubmit=async event=>{event.preventDefault();if(send.disabled)return;send.disabled=true;try{const out=await save(request,'/api/communication/'+encodeURIComponent(row.id)+'/reply',{body:body.value},null,'POST');body.value='';card.dataset.dirty='false';status.textContent=out.message;}catch(e){status.textContent=e.message+' Your reply is kept.'}finally{send.disabled=false}}}
 }
 function profile(main,{request,context,editable}){
  const section=node('section',null,{class:'card'}),notice=node('p','Loading shared client profile…',{role:'status'});section.append(node('h2','Client profile'),node('p','Reuse reviewed education, employment, qualifications and communication preferences across the client journey.'),notice);main.append(section);
  const path='/api/client-profile/'+encodeURIComponent(context.entity)+'/'+encodeURIComponent(context.id);
  request(path).then(out=>{if(!section.isConnected)return;notice.textContent='';const form=node('form',null,{class:'communication-compose'}),inputs={};
   for(const[key,label]of [['education','Education (institution, qualification and dates)'],['employment','Employment (employer, role and dates)'],['qualifications','Qualifications and test results']]){inputs[key]=field(form,label,node('textarea',null,{rows:'4',maxlength:'10000',name:key}));inputs[key].value=out.profile[key]||''}
   inputs.preferredChannel=field(form,'Preferred channel',select('Preferred channel',[['','Not set'],['email','Email'],['whatsapp','WhatsApp'],['phone','Phone'],['portal','Client portal']],out.profile.preferredChannel||''));
   for(const[key,label]of [['contactTimes','Preferred contact times and timezone'],['contactRestrictions','Contact restrictions and instructions']]){inputs[key]=field(form,label,node('input',null,{maxlength:'10000',name:key}));inputs[key].value=out.profile[key]||''}
   inputs.doNotContact=field(form,'Do not send client email, WhatsApp or consultation notifications',node('input',null,{type:'checkbox',name:'doNotContact'}));inputs.doNotContact.checked=!!out.profile.doNotContact;
   const submit=node('button','Save client profile',{type:'submit'});submit.disabled=!editable||!out.editable;form.append(submit);section.append(form);
   form.oninput=()=>{section.dataset.dirty='true'};form.onsubmit=async event=>{event.preventDefault();if(submit.disabled)return;submit.disabled=true;try{const data={};for(const[key,input]of Object.entries(inputs))data[key]=input.type==='checkbox'?input.checked:input.value;const result=await save(request,path,data,out.revision,'PUT');out.revision=result.revision;section.dataset.dirty='false';notice.textContent='Shared profile saved.'}catch(e){notice.textContent=e.message+' Your entries are kept.'}finally{submit.disabled=!editable||!out.editable}};
  }).catch(e=>{notice.textContent=e.message;});
 }
 function consultations(main,{request,editable},reload,eventRow=null){
  const details=node('details',null,{class:'card'});details.append(node('summary',eventRow?'Edit consultation: '+eventRow.title:'Schedule consultation'));main.append(details);
  const c=eventRow?.event||{},form=node('form',null,{class:'communication-compose'}),notice=node('p','',{role:'status'});
  const client=field(form,'Client',node('crm-record-picker',null,{entity:'contacts',name:'contactId',label:'Client'}));client.value=c.contactId||'';if(eventRow)client.setAttribute('disabled','');
  const title=field(form,'Title',node('input',null,{required:'',maxlength:'180'}));title.value=c.title||'';
  const at=field(form,'Start (your device timezone)',node('input',null,{type:'datetime-local',required:''}));at.value=localDate(c.occurredAt);
  const duration=field(form,'Duration in minutes',node('input',null,{type:'number',min:'5',max:'480',required:''}));duration.value=c.duration||30;
  const location=field(form,'Location or meeting link',node('input',null,{maxlength:'1000'}));location.value=c.location||'';
  const status=field(form,'Consultation status',select('Consultation status',[['scheduled','Scheduled'],['cancelled','Cancelled'],['completed','Completed']],c.status||'scheduled'));
  const attendance=field(form,'Attendance',select('Attendance',[['','Not recorded'],['attended','Attended'],['no_show','Did not attend']],c.attendance||''));
  const invite=field(form,'Queue an email invitation or update',node('input',null,{type:'checkbox'}));
  const reminder=field(form,'Send email reminder 24 hours before (schedule at least 24 hours ahead)',node('input',null,{type:'checkbox'}));reminder.checked=!!c.reminder;
  const submit=node('button',eventRow?'Save consultation':'Create consultation',{type:'submit'});submit.disabled=!editable;form.append(submit,notice);details.append(form);form.oninput=()=>{details.dataset.dirty='true'};
  form.onsubmit=async e=>{e.preventDefault();if(submit.disabled)return;if(!client.value){notice.textContent='Choose a client.';return}submit.disabled=true;try{const out=await save(request,'/api/consultations'+(eventRow?'/'+encodeURIComponent(eventRow.id):''),{contactId:c.contactId||client.value,title:title.value,occurredAt:new Date(at.value).toISOString(),duration:Number(duration.value),location:location.value,status:status.value,attendance:attendance.value,invite:invite.checked,reminder:reminder.checked},eventRow?.revision,eventRow?'PATCH':'POST');details.dataset.dirty='false';notice.textContent=out.message;if(eventRow){eventRow.revision=out.revision;eventRow.event=out.event}else{form.reset();client.value=''}reload();}catch(e){notice.textContent=e.message+' Your entries are kept.'}finally{submit.disabled=!editable}};
  if(eventRow)details.append(node('a','Download calendar invitation',{href:'/api/consultations/'+encodeURIComponent(eventRow.id)+'/calendar.ics'}));
 }
 function finance(main,{request}){
  const section=node('section',null,{class:'card'}),notice=node('p','Loading finance permissions…',{role:'status'});section.append(node('h2','Finance permissions'),notice);main.append(section);
  request('/api/finance-capabilities').then(out=>{if(!section.isConnected)return;notice.textContent='';if(!out.canManage){section.append(node('p','An administrator manages finance permissions.'));return}
   for(const person of out.staff||[]){if(person.role!=='member')continue;const form=node('form',null,{class:'communication-compose'});form.append(node('h3',person.name));const inputs={};for(const[key,label]of [['recordPayments','Record payments'],['approveAdjustments','Approve receipts and adjustments'],['reconcile','Reconcile bank statements'],['refunds','Approve and process refunds']]){inputs[key]=field(form,label,node('input',null,{type:'checkbox'}));inputs[key].checked=person.grants[key]??(key==='recordPayments')}
    const submit=node('button','Save permissions',{type:'submit'}),status=node('p','',{role:'status'});form.append(submit,status);section.append(form);form.onsubmit=async e=>{e.preventDefault();if(submit.disabled)return;submit.disabled=true;try{await save(request,'/api/finance-capabilities/'+encodeURIComponent(person.id),Object.fromEntries(Object.entries(inputs).map(([k,v])=>[k,v.checked])),person.revision,'PUT');status.textContent='Permissions saved.';const refreshed=await request('/api/finance-capabilities');person.revision=refreshed.staff.find(p=>p.id===person.id).revision}catch(e){status.textContent=e.message}finally{submit.disabled=false}};
   }
  }).catch(e=>{notice.textContent=e.message});
 }
 function readiness(main,{request,role}){
  const section=node('section',null,{class:'card'});
  section.append(node('h2','Start your day'),node('p','Choose your workflow. Record access and finance permissions still apply.'));
  const guides=[
   ['Advising','Review today’s priorities, open the application, check missing documents, and save a next action and deadline. Use Ownership and handoffs when responsibility changes.','/','My work today'],
   ['Finance','Open the client’s invoice, check its balance, record the receipt and review any approval before reconciling the statement.','/invoices','Invoices & payments'],
   ['Management','Review overdue actions, missing plans and pending handoffs. Resolve the highest-impact exception first.','/workspace?tab=priorities','Work priorities'],
   ['New inquiry','Create the lead once, attach its CV or supporting files, and review conversion into a client or student/application. Reuse the linked client profile.','/leads','Leads']
  ];
  const order=role==='admin'||role==='manager'?[2,0,1,3]:[0,3,1];
  for(const i of order){const[title,description,href,label]=guides[i],card=node('article',null,{class:'card'});card.append(node('h3',title),node('p',description),node('a',label,{href}));section.append(card)}
  if(role==='viewer')section.append(node('p','Your access is read-only. Ask the record owner to make changes.'));
  main.append(section);
  if(role!=='admin')return;
  const status=node('section',null,{class:'card'}),notice=node('p','',{role:'status','aria-live':'polite'}),content=node('div');
  const refresh=node('button','Refresh readiness',{type:'button',class:'secondary'});
  status.append(node('h2','Administrator readiness'),node('p','Review setup, recent failures and recovery evidence. A connection check does not establish live delivery or production readiness.'),refresh,notice,content);main.append(status);
  let generation=0;
  const load=async()=>{
   const current=++generation;refresh.disabled=true;notice.textContent='Checking workspace readiness…';
   // Each section can succeed independently, so a failed check never hides the other evidence.
   const results=await Promise.allSettled([request('/api/integrations/status'),request('/api/admin/operations')]);
   if(!status.isConnected||current!==generation)return;
   content.replaceChildren();
   const add=(title,description,label,href)=>{const card=node('article',null,{class:'card'});card.append(node('h3',title),node('p',description),node('a',label,{href}));content.append(card)};
   if(results[0].status==='fulfilled')for(const item of results[0].value.integrations||[])add(item.name+' · '+item.state.replaceAll('_',' '),item.message+(item.checkedAt?' Last connection check: '+item.checkedAt:''),'Review connection','/workspace?tab=integrations');
   else add('Integration status unavailable',results[0].reason.message,'Open integrations','/workspace?tab=integrations');
   if(results[1].status==='fulfilled'){
    const out=results[1].value,backup=out.backup||{},verified=backup.restoreVerification||{};
    add('Backup · '+(backup.state||'unknown'),'Last backup check: '+(backup.checkedAt||'Not recorded')+'. Isolated restore: '+(verified.state||'Not verified')+'. '+(backup.message||''),'Review backup & restore','/workspace?tab=recovery');
    add('Email delivery',(out.mail?.failed||0)+' failed; '+(out.mail?.waitingConfiguration||0)+' waiting for configuration.','Review messages','/workspace?tab=communication&channel=email');
    for(const alert of out.alerts||[])content.append(node('p',alert));
    const workers=node('details');workers.append(node('summary','Background job status'));for(const[name,worker]of Object.entries(out.workers||{}))workers.append(node('p',name+' · '+worker.state));content.append(workers);
   }else add('Operational status unavailable',results[1].reason.message,'Open backup & restore','/workspace?tab=recovery');
   add('Team and workspace setup','Set the workspace timezone and currency, invite staff, and review their roles before assigning work.','Manage people and access','/administration');
   notice.textContent=results.some(r=>r.status==='rejected')?'Some checks failed. Use Refresh readiness to retry.':'Status refreshed. Complete live provider checks and staff workflow sessions before treating setup as accepted.';refresh.disabled=false;
  };
  refresh.onclick=load;load();
 }
 class Outcomes extends HTMLElement{
  connectedCallback(){
   if(this.loaded)return;this.loaded=true;this.generation=0;
   this.content=node('div');const refresh=node('button','Refresh outcomes',{type:'button'});
   const render=async()=>{const generation=++this.generation;refresh.disabled=true;window.CRMHomeSummary?.update(this,'Loading…');try{
    const res=await fetch('/api/work-outcomes',{credentials:'same-origin'}),out=await res.json();
    if(!res.ok)throw new Error(out.error||'Could not load outcomes');
    if(!this.isConnected||generation!==this.generation)return;
    window.CRMHomeSummary?.update(this,`${out.unansweredMessages||0} unanswered messages · ${out.overdueReplies||0} overdue replies · ${out.overdueTasks||0} overdue tasks · ${out.overdueApplications||0} overdue applications`);
    this.content.replaceChildren(node('h2','Work needing attention'));
    const links=[['unansweredMessages','Unanswered messages','/workspace?tab=communication&handling=needs_reply'],['overdueReplies','Overdue replies','/workspace?tab=communication'],['overdueTasks','Overdue tasks','/tasks'],['overdueApplications','Overdue application actions','/cases']];
    for(const[key,label,url]of links)this.content.append(node('a',`${label}: ${out[key]}`,{href:url,class:'card'}));
    if(!this.hasAttribute('attention-only')){
    this.content.append(node('h3','Collections this month'));
    for(const r of out.collectionsThisMonth||[])this.content.append(node('p',`${r.currency} ${Number(r.amount).toFixed(2)}`));
    if(!(out.collectionsThisMonth||[]).length)this.content.append(node('p','No posted collections this month.'));
    }
   }catch(e){if(this.isConnected&&generation===this.generation){this.content.replaceChildren(node('p',e.message+' Use Refresh outcomes to retry.',{role:'status'}));window.CRMHomeSummary?.update(this,'Unavailable · open to retry')}}
   finally{if(generation===this.generation)refresh.disabled=false}};
   refresh.onclick=render;this.append(refresh,this.content);if(window.CRMHomeSummary)window.CRMHomeSummary.schedule(this,render);else render();this.changed=()=>render();window.addEventListener('crm:record-changed',this.changed);
  }
  disconnectedCallback(){this.summaryCleanup?.();window.removeEventListener('crm:record-changed',this.changed);this.generation++;this.loaded=false;this.replaceChildren()}
 }
 if(!customElements.get('crm-work-outcomes'))customElements.define('crm-work-outcomes',Outcomes);
 window.CRMEveryday={handling,profile,consultations,finance,readiness};
})();
