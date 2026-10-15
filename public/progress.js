'use strict';
(() => {
 const node=(tag,text,attrs={})=>{const el=document.createElement(tag);if(text!=null)el.textContent=String(text);for(const[k,v]of Object.entries(attrs))el.setAttribute(k,v);return el};
 async function request(path,body,method="POST",revision){const options={credentials:'same-origin',...(body===undefined?{}:{method,headers:{'Content-Type':'application/json',...(revision?{'If-Match':revision}:{})},body:JSON.stringify(body)})};let response=await window.CRMAuthenticatedFetch(path,options);const out=await response.json();if(!response.ok)throw new Error(out.error||'Could not load record. Refresh and try again.');return out}
 class RecordProgress extends HTMLElement {
  static get observedAttributes(){return ['record-id']}
  constructor(){super();this.attachShadow({mode:'open'});this.generation=0}
  connectedCallback(){this.changed=()=>{if(!this.shadowRoot.querySelector('[data-dirty="true"]'))this.load()};window.addEventListener('crm:record-changed',this.changed);this.load()}
  attributeChangedCallback(){if(this.isConnected)this.load()}
  disconnectedCallback(){this.generation++;window.removeEventListener('crm:record-changed',this.changed)}
  async load(){if(this.shadowRoot.querySelector('[data-dirty="true"]')){const notice=this.shadowRoot.querySelector('[role=status]');if(notice)notice.textContent='Your unsaved entries are kept. Save or discard them before refreshing.';return}const generation=++this.generation;const root=node('section',null,{class:'tools progress-panel'}),notice=node('p','Loading…',{role:'status','aria-live':'polite'}),refresh=node('button','Refresh '+this.label,{type:'button',class:'secondary'});this.shadowRoot.replaceChildren(node('link',null,{rel:'stylesheet',href:'/public/center.css'}),node('link',null,{rel:'stylesheet',href:'/public/components.css'}),root);refresh.onclick=()=>this.load();root.append(node('h2',this.label),refresh,notice);try{const out=await request(this.endpoint());if(!this.isConnected||generation!==this.generation)return;notice.textContent='';this.render(root,out,notice,generation)}catch(error){if(generation===this.generation)notice.textContent=error.message}}
 }
 class ApplicationBlockers extends RecordProgress {
  get label(){return 'Application requirements'}
  endpoint(){return '/api/cases/'+encodeURIComponent(this.getAttribute('record-id'))+'/blockers'}
  render(root,out,notice,generation){
   if(!this.closest('.application-essentials'))root.append(node('p','Owner: '+(out.owner||'Unassigned')+' · Next action: '+(out.nextAction||'Not set')+' · Due: '+(out.deadline||'Not set')));
   const gate=out.nextStageGate,gateItems=gate?.items||[],automatic=(out.items||[]).filter(item=>item.blocking);
   const summary=node('section',null,{class:'card blocker-summary','aria-label':'What is blocking progress'});
   summary.append(node('h3','What is blocking progress'));
   if(out.active===false)summary.append(node('p','This application is no longer active. Review its history before planning further work.'));
   else {
    summary.append(node('p',gate?.stage?(gateItems.length?'Move to '+gate.stage+' — blocked':gate.enabled?'Move to '+gate.stage+' — configured requirements satisfied':'Move to '+gate.stage+' — no stage gate configured'):'Review the requirements before progressing this application.'));
    const reasons=(title,items)=>{if(!items.length)return;summary.append(node('h4',title));const list=node('ul');for(const item of items){const row=node('li');row.append(node('p',item.title?item.title+(item.detail?' — '+item.detail:''):item.detail),node('p','Responsible: '+(item.responsible||out.owner||'Unassigned')+' · Due: '+(item.deadline||'Not set')),node('a',item.action||'Review requirement',{href:item.route}));list.append(row)}summary.append(list)};
    reasons('Required for the next stage',gateItems);
    reasons('Blocks automatic submission readiness',automatic);
    if(!gateItems.length&&!automatic.length)summary.append(node('p','No blocking conditions found in this check.'));
   }
   summary.append(node('p','Next action: '+(out.nextAction||'Not set')+' · Deadline: '+(out.deadline||'Not set')));
   root.append(summary);
   this.renderGuidance(root,out,notice);
   root.append(node('p',out.blockingCount?out.blockingCount+' document requirements block automatic submission readiness.':'Document follow-up and reminders appear below.'));
   if(out.checklist){root.append(node('p',out.completedCount+' of '+out.requiredCount+' accessible required documents complete.'));
    const filters=node('nav',null,{'aria-label':'Document follow-up filters'}),list=node('div'),empty=node('p','No requirements match this filter.',{role:'status',hidden:''}),cards=[];this.filter||='attention';
    const matches={attention:item=>!item.complete,missing:item=>item.missing,overdue:item=>item.overdue,expiring:item=>item.expiring,all:()=>true};
    const apply=()=>{for(const{item,element}of cards)element.hidden=!matches[this.filter](item);empty.hidden=cards.some(({element})=>!element.hidden);for(const button of filters.querySelectorAll('button'))button.setAttribute('aria-pressed',String(button.dataset.filter===this.filter))};
    for(const[key,label]of [['attention','Needs attention'],['missing','Missing files'],['overdue','Overdue'],['expiring','Expiring in 30 days'],['all','All requirements']]){const button=node('button',label+' ('+out.checklist.filter(matches[key]).length+')',{type:'button',class:'secondary','data-filter':key});button.onclick=()=>{if(root.querySelector('[data-dirty="true"]')){notice.textContent='Your unsaved document plan is kept. Save it before changing filters.';return}this.filter=key;apply()};filters.append(button)}
    root.append(filters,node('p','Missing means no uploaded file. Overdue means an incomplete requirement due before '+out.today+'. Expiring means expiry from '+out.today+' through the next 30 days, inclusive.'),list,empty);
    for(const item of out.checklist){
     const card=node('article',null,{class:'card requirement-item'});card.append(node('strong',(item.complete?'✓ ':'')+item.title),node('p',item.status+(item.overdue?' · Overdue':'')),node('p',item.attention||''),node('p',item.expiryDate?'Expires '+item.expiryDate:''),node('p','Responsible: '+item.responsible+' · Due: '+(item.dueDate||'Not set')),node('small',item.deadlineSource),node('a','Review document',{href:item.route,class:'button secondary'}));
     if(item.editable){const form=node('form'),personLabel=node('label','Responsible staff'),person=node('select',null,{name:'responsibleId'});person.append(node('option','Use application adviser / record owner',{value:''}));for(const u of item.assignees)person.append(node('option',u.name,{value:u.id}));if(item.responsibleId&&!item.assignees.some(u=>u.id===item.responsibleId))person.append(node('option','Assigned staff unavailable',{value:item.responsibleId}));person.value=item.responsibleId||'';personLabel.append(person);const dateLabel=node('label','Document deadline'),date=node('input',null,{type:'date',name:'dueDate'});date.value=item.documentDueDate||'';dateLabel.append(date);form.oninput=form.onchange=()=>{form.dataset.dirty='true'};const save=node('button','Save responsibility and deadline',{type:'submit'});form.append(personLabel,dateLabel,node('p','An empty document deadline uses the application next-action deadline.'),save);form.onsubmit=async event=>{event.preventDefault();save.disabled=true;try{const saved=await request('/api/documents/'+encodeURIComponent(item.id)+'/requirement-plan',{responsibleId:person.value,dueDate:date.value},'PATCH',item.revision);if(!this.isConnected||generation!==this.generation)return;window.CRMSessionDrafts?.saved?.(form,saved);form.dataset.dirty='false';if(saved.document){item.revision=saved.document._revision||item.revision;item.responsibleId=saved.document.responsibleId;item.documentDueDate=saved.document.dueDate}notice.textContent='Document responsibility and deadline saved.';save.disabled=false;window.dispatchEvent(new CustomEvent('crm:record-changed',{detail:this.getAttribute('record-id')}));}catch(error){notice.textContent=error.message+' Your entries are kept. Retry save, or refresh after reviewing the saved version.';save.disabled=false}};const settings=node('details');settings.append(node('summary','Assign responsibility or deadline'),form);card.append(settings)}
     if(item.complete){const complete=node('details',null,{class:'completed-requirement'});complete.append(node('summary',item.title+' — complete'),card);list.append(complete);cards.push({item,element:complete})}else {list.append(card);cards.push({item,element:card})}
    }apply();
   }
   const attention=(out.items||[]).filter(item=>!out.checklist||item.kind!=='document');if(attention.length)root.append(node('h3','Reminders and follow-up'));
   if(!out.items?.length&&!out.requiredCount)root.append(node('p','No issues found in accessible application records.'));
   for(const item of attention){const card=node('article',null,{class:'card requirement-item'});card.append(node('strong',item.title),node('p',item.detail),node('p','Responsible: '+(item.responsible||out.owner||'Unassigned')+' · Due: '+(item.deadline||'Not set')),node('p',item.blocking?'Blocks automatic submission readiness':'Needs attention; does not block the next stage'),node('a',item.action,{href:item.route,class:'button secondary'}));root.append(card)}
  }

  renderGuidance(root,out,notice){
   if(out.active===false)return;
   const checklist=out.checklist||[];
   const requestKind=item=>item.complete?'':item.expiryDate&&item.expiryDate<out.today?'replacement':item.status==='Correction Required'?'correction':item.missing?'missing':'';
   const requested=checklist.filter(item=>requestKind(item));
   const suggestions=[];
   for(const item of checklist.filter(item=>!item.complete)){
    const kind=requestKind(item);
    suggestions.push({action:kind==='replacement'?'Ask client for an updated '+item.title:kind==='correction'?'Ask client for a corrected '+item.title:kind==='missing'?'Ask client for '+item.title:'Review '+item.title+' and record the outcome',deadline:item.dueDate,route:item.route});
   }
   for(const item of out.nextStageGate?.items||[])suggestions.push({action:item.action==='Review approval'?'Ask a workspace manager to approve the current application for '+out.nextStageGate.stage:item.detail,deadline:item.deadline,route:item.route});
   const guidance=node('details',null,{class:'application-guidance'});guidance.append(node('summary','Suggested next actions and document request'));
   if(suggestions.length){guidance.append(node('h3','Suggested next actions'));const list=node('ul');
    for(const suggestion of suggestions){const row=node('li');row.append(node('p',suggestion.action),node('a','Review requirement',{href:suggestion.route}));
     if(out.editable){const review=node('button','Review as next action',{type:'button',class:'secondary'});review.onclick=()=>window.dispatchEvent(new CustomEvent('crm:suggest-work-plan',{detail:{entity:'cases',id:this.getAttribute('record-id'),action:suggestion.action,deadline:suggestion.deadline}}));row.append(review)}list.append(row)}guidance.append(list);
    if(out.editable&&!this.closest('.application-essentials'))guidance.append(node('crm-work-plan',null,{entity:'cases','record-id':this.getAttribute('record-id')}));
   }else guidance.append(node('p','No document or stage-gate actions to suggest. Review the application and plan the next staff action.'));
   const draft=node('section',null,{class:'document-request-draft'});draft.append(node('h3','Document request draft'));
   if(!requested.length){draft.append(node('p','No missing, expired or correction-required documents to request. Uploaded documents awaiting staff review are excluded.'));guidance.append(draft);root.append(guidance);return}
   draft.append(node('p','Choose the documents to request, then review and edit the message before copying.'));
   const choices=[];
   for(const item of requested){const label=node('label'),check=node('input',null,{type:'checkbox'});check.checked=true;label.append(check,document.createTextNode(item.title));draft.append(label);choices.push({item,check})}
   const label=node('label','Message'),message=node('textarea',null,{rows:'10','aria-label':'Document request message'});label.append(message);draft.append(label);
   const status=node('p','',{role:'status','aria-live':'polite'}),copy=node('button','Copy document request',{type:'button',class:'secondary'}),rebuild=node('button','Rebuild message from selection',{type:'button',class:'secondary'}),discard=node('button','Discard draft and refresh',{type:'button',class:'secondary'});
   const compose=()=>{const selected=choices.filter(row=>row.check.checked);message.value=selected.length?'Hello,\n\nFor your application'+(out.caseNumber?' '+out.caseNumber:'')+', please provide:\n'+selected.map(({item})=>'- '+item.title+(requestKind(item)==='replacement'?' (updated copy; the previous document has expired)':requestKind(item)==='correction'?' (corrected copy)':'')+(item.dueDate?' — requested by '+item.dueDate:'')).join('\n')+'\n\nPlease use our agreed document submission channel. Let us know if you need help or more time.\n\nThank you.':'';copy.disabled=!selected.length;status.textContent=selected.length?'Check the recipient, requested dates and wording before using this message.':'Select at least one document.'};
   for(const {check} of choices)check.onchange=()=>{draft.dataset.dirty='true';copy.disabled=true;status.textContent='Selection changed. Rebuild the message to apply it; this replaces the current message text.'};
   rebuild.onclick=()=>{draft.dataset.dirty='true';compose()};
   message.oninput=()=>{draft.dataset.dirty='true';copy.disabled=!message.value.trim()};
   copy.onclick=async()=>{try{await navigator.clipboard.writeText(message.value);status.textContent='Document request copied.'}catch{message.focus();message.select();status.textContent='Select and copy the message using your device’s copy command.'}};
   discard.onclick=()=>{draft.dataset.dirty='false';this.load()};
   draft.append(rebuild,copy,discard,status);compose();guidance.append(draft);root.append(guidance);
  }


 }
 class InvoiceFinance extends RecordProgress {
  get label(){return 'Balance and receipt approvals'}
  endpoint(){return '/api/invoices/'+encodeURIComponent(this.getAttribute('record-id'))+'/finance-status'}
  render(root,out,notice,generation){const inv=out.invoice,currency=inv.currency||'USD',amount=value=>currency+' '+Number(value||0).toFixed(2);root.append(node('p','Posted receipts: '+amount(inv.amountReceived)+' · Outstanding balance: '+amount(Math.max(0,Number(inv.balance)))+(Number(inv.balance)<0?' · Credit balance: '+amount(-Number(inv.balance)):'')),node('p','Awaiting approval: '+amount(out.pendingAmount)+' in '+out.pendingCount+' receipt(s). Pending receipts do not reduce the posted balance.'));root.append(node('p','Due: '+(inv.dueDate||'Not set')+(Number(inv.balance)>0&&inv.dueDate&&inv.dueDate<out.today?' · Overdue':'')));const history=node('details');history.append(node('summary','Posted receipt history'));for(const p of out.postedReceipts||[])history.append(node('p',amount(p.amount)+' · '+(p.reference||'No reference')+' · '+p.paidOn+' · '+(p.method||'Method not set')));if(!(out.postedReceipts||[]).length)history.append(node('p','No accessible posted receipts.'));root.append(history);if(out.pendingCount)root.append(node('p','Review pending receipts before requesting another payment.'));if(out.approvalNote)root.append(node('p','Legacy invoice approval note: '+out.approvalNote));if(!out.pendingCount)root.append(node('p','No receipts awaiting approval.'));for(const receipt of out.pendingReceipts||[]){const card=node('article',null,{class:'card'});card.append(node('strong',amount(receipt.amount)+' · '+(receipt.reference||'No reference')),node('p',(receipt.method||'Method not set')+' · '+receipt.paidOn+' · recorded by '+receipt.createdBy));if(out.canReview)for(const[decision,title]of [['approve','Approve receipt'],['reject','Reject receipt']]){const button=node('button',title,{type:'button',class:'secondary'});button.onclick=async()=>{card.querySelectorAll('button').forEach(b=>b.disabled=true);try{await request('/api/payments/'+encodeURIComponent(receipt.id)+'/review',{decision});if(!this.isConnected||generation!==this.generation)return;window.dispatchEvent(new CustomEvent('crm:record-changed',{detail:inv.id}))}catch(error){notice.textContent=error.message;card.querySelectorAll('button').forEach(b=>b.disabled=false)}};card.append(button)}else card.append(node('p','Awaiting manager review.'));root.append(card)}}
 }
 customElements.define('crm-application-blockers',ApplicationBlockers);
 customElements.define('crm-invoice-status',InvoiceFinance);
})();
