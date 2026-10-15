const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawn} = require('node:child_process');
const puppeteer = require('puppeteer');
let browser;
before(async () => {
  const local = path.join(os.homedir(), '.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');
  const executablePath = process.env.CHROME_PATH || (fs.existsSync(local) ? local : await puppeteer.executablePath());
  browser = await puppeteer.launch({executablePath, headless:true, pipe:true, args:['--no-sandbox','--disable-dev-shm-usage']});
});
after(async () => { await browser?.close(); });

test('work plans preserve edits across refresh and require review of a changed record',async()=>{
 const options={stalePlan:true};const{page,calls,errors}=await fixture('workspace',options);try{
  await page.evaluate(()=>{const plan=document.createElement('crm-work-plan');plan.setAttribute('entity','deals');plan.setAttribute('record-id','deal-1');document.body.append(plan)});
  await page.waitForFunction(()=>document.querySelector('crm-work-plan').shadowRoot.querySelector('textarea').value==='Call client');
  await page.$eval('crm-work-plan >>> textarea',e=>{e.value='Keep this action draft';e.dispatchEvent(new Event('input',{bubbles:true}))});
  const before=calls.filter(c=>c.path.startsWith('/api/work-plans/')).length;
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('crm:record-changed')));
  assert.equal(calls.filter(c=>c.path.startsWith('/api/work-plans/')).length,before);
  await page.$eval('crm-work-plan >>> form',e=>e.requestSubmit());
  await page.waitForFunction(()=>document.querySelector('crm-work-plan').shadowRoot.textContent.includes('Record changed'));
  assert.equal(await page.$eval('crm-work-plan >>> textarea',e=>e.value),'Keep this action draft');
  options.currentPlan=true;
  await page.evaluate(()=>[...document.querySelector('crm-work-plan').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Refresh saved plan').click());
  await page.waitForSelector('crm-work-plan >>> input[type=checkbox]');
  assert.equal(await page.$eval('crm-work-plan >>> textarea',e=>e.value),'Keep this action draft');
  await page.$eval('crm-work-plan >>> form',e=>e.requestSubmit());
  assert.equal(calls.filter(c=>c.path.startsWith('/api/work-plans/')&&c.method==='PUT').length,1);
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('client history provides safe record links and pages the selected category',async()=>{
 const{page,calls,errors}=await fixture('workspace');try{
  await page.evaluate(()=>{const history=document.createElement('crm-client-history');history.setAttribute('record-id','c_client');document.body.append(history)});
  await page.waitForSelector('crm-client-history >>> article a');
  assert.equal(await page.$eval('crm-client-history >>> article a',e=>e.getAttribute('href')),'/cases/case_client#record-tools?tab=documents');
  assert.equal(await page.$eval('crm-client-history',e=>e.shadowRoot.querySelectorAll('img').length),0);
  await page.select('crm-client-history >>> select[aria-label="History type"]','document');
  await page.waitForFunction(()=>document.querySelector('crm-client-history').shadowRoot.textContent.includes('Original CV'));
  await page.evaluate(()=>[...document.querySelector('crm-client-history').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Next').click());
  await page.waitForFunction(()=>document.querySelector('crm-client-history').shadowRoot.textContent.includes('Page 2'));
  assert.ok(calls.some(c=>c.path.endsWith('/history')&&c.query.includes('offset=25')&&c.query.includes('kind=document')));assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('priority queue rapid clicks retain the newest selection and currency totals',async()=>{
 const{page,calls,errors}=await fixture('workspace',{slowQueue:true});try{
  await page.evaluate(()=>document.body.append(document.createElement('crm-priority-queues')));
  await page.waitForSelector('crm-priority-queues >>> nav button');
  await page.evaluate(()=>[...document.querySelector('crm-priority-queues').shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent.startsWith('Finance')).click());
  await page.waitForFunction(()=>document.querySelector('crm-priority-queues').shadowRoot.textContent.includes('PHP · Received 1000.00'));
  await new Promise(r=>setTimeout(r,650));
  assert.ok(await page.$eval('crm-priority-queues',e=>e.shadowRoot.querySelector('[aria-pressed=true]').textContent.startsWith('Finance')));
  assert.equal(await page.$eval('crm-priority-queues >>> .tools a',e=>e.getAttribute('href')),'/workspace?tab=finance');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('statement reconciliation excludes other currencies and preserves a rejected match selection',async()=>{
 const{page,calls,errors}=await fixture('workspace');try{
  await page.evaluate(()=>document.body.append(document.createElement('crm-reconciliation')));
  await page.waitForSelector('crm-reconciliation >>> article select');
  assert.equal(await page.$$eval('crm-reconciliation >>> article option',e=>e.length),2);
  await page.select('crm-reconciliation >>> article select','receipt-1');
  await page.click('crm-reconciliation >>> article input[type=checkbox]');
  await page.$eval('crm-reconciliation >>> article form',e=>e.requestSubmit());
  await page.waitForFunction(()=>document.querySelector('crm-reconciliation').shadowRoot.textContent.includes('already matched'));
  assert.equal(await page.$eval('crm-reconciliation >>> article select',e=>e.value),'receipt-1');
  assert.equal(calls.find(c=>c.path.endsWith('/match')).headers['if-match'],'bank-version');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('modal drafts restore fields without restoring consent and retain their original record version',async()=>{
 const options={staleContact:true};const{page,calls,contact}=await fixture('workspace',options);try{
  await page.evaluate(async()=>{
   const nav=document.createElement('aside');nav.id='workspace-navigation';nav.setAttribute('data-user-id','draft-user');document.body.append(nav);
   await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});
   window.openDraftModal=()=>{const modal=document.createElement('div');modal.className='modal';modal.setAttribute('data-draft-record-id','c_client');modal.innerHTML='<h2>Edit contact</h2><form><crm-draft-recovery></crm-draft-recovery><input id="name" value="Client One"><input id="consent" type="checkbox"><button type="submit">Save</button></form>';modal.querySelector('form').addEventListener('submit',event=>{event.preventDefault();const xhr=new XMLHttpRequest();xhr.open('PUT','/api/contacts/c_client');xhr.send('{}')});document.body.append(modal)};
   window.openDraftModal();
  });
  await page.waitForSelector('crm-draft-recovery');
  await page.$eval('#name',e=>{e.value='Recovered client';e.dispatchEvent(new Event('input',{bubbles:true}))});
  await page.click('#consent');
  await page.evaluate(()=>{document.querySelector('.modal form').requestSubmit();document.querySelector('.modal form').requestSubmit()});
  await page.waitForResponse(r=>new URL(r.url()).pathname==='/api/contacts/c_client'&&r.request().method()==='PUT');
  assert.equal(calls.filter(c=>c.path==='/api/contacts/c_client'&&c.method==='PUT').length,1);
  await page.waitForFunction(()=>document.querySelector('.save-recovery')?.textContent.includes('Save needs review'));
  assert.equal(await page.$eval('#name',e=>e.value),'Recovered client');
  assert.ok(await page.$eval('.save-recovery',e=>e.textContent.includes('Restore draft')&&e.textContent.includes('compare')));
  await page.evaluate(()=>document.querySelector('.modal').remove());contact._revision='new-version';
  await page.evaluate(async()=>{await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});window.openDraftModal()});
  await page.waitForFunction(()=>document.querySelector('crm-draft-recovery').textContent.includes('Restore draft'));
  await page.evaluate(()=>[...document.querySelector('crm-draft-recovery').querySelectorAll('button')].find(b=>b.textContent==='Restore draft').click());
  assert.equal(await page.$eval('#name',e=>e.value),'Recovered client');assert.equal(await page.$eval('#consent',e=>e.checked),false);
  const response=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/contacts/c_client'&&r.request().method()==='PUT');await page.$eval('.modal form',e=>e.requestSubmit());await response;
  const puts=calls.filter(c=>c.path==='/api/contacts/c_client'&&c.method==='PUT');assert.equal(puts.at(-1).headers['if-match'],'old-version');
 }finally{await page.close()}
});

test('modal drafts stay isolated across records with the same title, including reused dialogs',async()=>{
 const {page}=await fixture('workspace');try{
  await page.evaluate(()=>{
   const nav=document.createElement('aside');nav.id='workspace-navigation';nav.setAttribute('data-user-id','isolation-user');document.body.append(nav);
   const modal=document.createElement('div');modal.className='modal';modal.setAttribute('data-draft-record-id','first');
   modal.innerHTML='<h2>Edit contact</h2><form><crm-draft-recovery></crm-draft-recovery><input id="draft-name" value="Same name"></form>';document.body.append(modal);
  });
  await page.waitForFunction(()=>document.querySelector('.modal form'));
  await page.$eval('#draft-name',e=>{e.value='First draft';e.dispatchEvent(new Event('input',{bubbles:true}))});
  await page.evaluate(()=>{document.querySelector('#draft-name').value='Same name';document.querySelector('.modal').setAttribute('data-draft-record-id','second')});
  await new Promise(r=>setTimeout(r,50));
  assert.equal(await page.$eval('crm-draft-recovery',e=>e.textContent.includes('Restore draft')),false);
  await page.$eval('#draft-name',e=>{e.value='Second draft';e.dispatchEvent(new Event('input',{bubbles:true}))});
  for(const [id,expected] of [['first','First draft'],['second','Second draft']]){
   await page.evaluate(id=>{document.querySelector('#draft-name').value='Same name';document.querySelector('.modal').setAttribute('data-draft-record-id',id)},id);
   await page.waitForFunction(()=>document.querySelector('crm-draft-recovery').textContent.includes('Restore draft'));
   await page.$eval('crm-draft-recovery button',e=>e.click());
   assert.equal(await page.$eval('#draft-name',e=>e.value),expected);
  }
 }finally{await page.close()}
});

async function fixture(view = 'contacts', options = {}) {
  const page = await browser.newPage(), calls=[], errors=[];
  const contact = {id:'c_client',name:'Client One',email:'client@example.com',phone:'+12025550123',orgId:'org_a',ownerId:'u_manager',visibility:'organization',_revision:'old-version'};
  const student = {id:'s_client',name:'Student One',schoolId:'school',applicationStage:'Applying',intake:'January 2027',_revision:'student-version'};
  const flow={contacts:[contact,{...contact,id:'c_other',name:'Other Client'}],students:[student],deals:[],cases:[{id:'case_client',clientId:contact.id,studentId:student.id,caseNumber:'ECC-001',currentStage:'Documents Pending'}],documents:[{id:'doc_client',caseId:'case_client',caseNumber:'ECC-001',docName:'Passport',latestVersion:1,status:'Received'}],invoices:[],leads:[],agents:[],partners:[],schools:[],tasks:[],templates:options.templates||[],ledger:[]};
  if(['leads','leadwork'].includes(view)){flow.leads=[{id:'l_client',name:'Prospective Client',email:'prospect@example.com',source:'Referral',referrer:'Flor',nextAction:'Call about CV',status:'New',assignedTo:'Adviser',createdAt:'2026-10-04',followUpDate:'2026-10-20',notes:'Existing inquiry notes',_revision:'lead-version'}];flow.documents.push({id:'cv_client',leadId:'l_client',docName:'Client CV',latestVersion:1,status:'Received',filePath:'/api/documents/cv_client/files/1'});}
  const center={role:'manager',user:{id:'u_manager'},organization:[{name:'Demo workspace',timezone:'UTC'}],records:{contacts:flow.contacts.map(c=>({id:c.id,label:c.name})),students:[{id:student.id,label:student.name}]},features:{smtp:true,ai:view==='leads'},entries:[],mail:[],notifications:[]};
  page.on('pageerror',e=>errors.push(e.message));
  await page.setRequestInterception(true);
  page.on('request', async req=> {
    try {
      const url=new URL(req.url()); calls.push({query:url.search,path:url.pathname,method:req.method(),headers:req.headers(),body:req.postData()});
      let data,contentType='application/json',status=200;
      if(url.pathname.startsWith('/public/')) {data=fs.readFileSync(path.join(__dirname,'..',url.pathname));contentType=url.pathname.endsWith('.css')?'text/css':'application/javascript';}
      else if(url.pathname==='/portal') {data=fs.readFileSync(path.join(__dirname,'../public/portal.html'));contentType='text/html';}
      else if(url.pathname==='/') {contentType='text/html';data=`<!doctype html><html><head><meta charset="utf-8"></head><body><div id="app">${view==='leadwork'?'<crm-lead-work record-id="l_client"></crm-lead-work>':view==='picker'?'<crm-record-picker entity="contacts" value="c_client" label="Client"></crm-record-picker>':view==='ai'?'<crm-ai-chat></crm-ai-chat>':view==='workspace'?'<crm-workspace></crm-workspace>':view==='insights'?'<crm-insights></crm-insights>':view==='daily'?'<div id="work-dashboard-fixture"></div>':view==='journey'?'<crm-student-journey record-id="s_client"></crm-student-journey>':view==='quality'?'<crm-form-quality entity="students" studentcode="DUP"></crm-form-quality>':view==='connections'?'<crm-integration-health></crm-integration-health>':`<crm-record-tools entity="${view}" record-id="${view==='students'?'s_client':view==='leads'?'l_client':'c_client'}"></crm-record-tools>`}</div><script src="/public/pickers.js"></script><script src="/public/assignment-review.js"></script><script src="/public/record-versions.js"></script><script src="/public/draft-recovery.js"></script><script src="/public/productivity.js"></script><script src="/public/ai.js"></script><script src="/public/followup-templates.js"></script><script src="/public/handoffs.js"></script><script src="/public/progress.js"></script><script src="/public/consolidation.js"></script><script src="/public/workspace-secondary.js"></script><link rel="stylesheet" href="/public/work-dashboard-elm.css"><script src="/public/work-dashboard-elm.js"></script><script src="/public/record-browser-elm.js"></script><script src="/public/center.js"></script><script src="/public/components.js"></script><script src="/public/lead-work.js"></script>${view==='daily'?'<script>Elm.WorkDashboard.init({node:document.getElementById("work-dashboard-fixture"),flags:{userId:"u_manager"}})</script>':''}</body></html>`;}
      else if(view==='picker'&&url.pathname==='/api/contacts/c_client') data={contact};
      else if(view==='picker'&&url.pathname==='/api/contacts') {
        let rows=Array.from({length:240},(_,i)=>({id:'pick-'+i,name:'Searchable client '+i,email:'client'+i+'@example.com'}));
        const q=url.searchParams.get('q')||'';
        if(q==='Slow'){await new Promise(resolve=>setTimeout(resolve,700));rows=[{id:'stale',name:'Slow result'}]}
        else rows=rows.filter(row=>row.name.includes(q));
        const offset=Number(url.searchParams.get('offset')||0);data={contacts:rows.slice(offset,offset+20),total:rows.length};
      }
      else if(view==='leads'&&url.pathname==='/api/assistant/jobs')data={jobs:[{id:'cv-draft',recordId:'cv_client',createdAt:'2026-10-10',job:{action:'cv-extract',status:'completed',result:JSON.stringify({fields:{name:'Reviewed Prospect',email:'reviewed@example.com',notes:'Degree in business'},missing_fields:['phone'],uncertainties:['Check employment dates']})}}]};
      else if(view==='leads'&&url.pathname==='/api/assistant/jobs/cv-draft')data={status:'completed',result:JSON.stringify({fields:{name:'Reviewed Prospect',email:'reviewed@example.com',notes:'Degree in business'},missing_fields:['phone'],uncertainties:['Check employment dates']})};
      else if(view==='leads'&&url.pathname==='/api/workflows/lead-convert'){flow.leads[0].convertedContactId='c_client';flow.leads[0].convertedCaseId='case_client';flow.leads[0].status='Converted';flow.documents.find(d=>d.id==='cv_client').caseId='case_client';data={contactId:'c_client',caseId:'case_client'};}
      else if(url.pathname==='/api/records/leads/l_client')data={record:flow.leads[0],editable:true};
      else if(url.pathname==='/api/leads/l_client/timeline'&&req.method()==='GET')data={events:[{id:'event-1',title:'Logged call',body:'<img src=x onerror=alert(1)>',actor:'Adviser',at:'2026-10-10T08:00:00Z'}],total:26};
      else if(url.pathname==='/api/leads/l_client/timeline'&&req.method()==='POST')data={status:'ok'};
      else if(url.pathname==='/api/leads/l_client'&&req.method()==='PUT'&&options.staleLead){status=409;data={error:'Record changed since you opened it'};}
      else if(url.pathname==='/api/records/documents/cv_client')data={record:flow.documents.find(d=>d.id==='cv_client'),editable:true};
      else if(url.pathname==='/api/documents/cv_client/review'){const doc=flow.documents.find(d=>d.id==='cv_client');doc.reviewedBy='Demo User';doc.reviewedAt='2026-10-10T12:00:00Z';doc.reviewedVersion=doc.latestVersion;data={document:doc};}
      else if(url.pathname==='/api/leads/l_client'&&req.method()==='PUT'){Object.assign(flow.leads[0],JSON.parse(req.postData()));data={lead:flow.leads[0]};}
      else if(url.pathname.startsWith('/api/records/')) data={record:contact,editable:true};
      else if(url.pathname.startsWith('/api/work-plans/')){if(req.method()==='PUT'){if(options.stalePlan){status=409;data={error:'Record changed. Your draft is kept.'}}else data={saved:true}}else data={nextAction:'Call client',deadline:'2026-10-20',responsible:'u_1',revision:options.currentPlan?'new-plan':'plan-version',editable:true};}
      else if(url.pathname==='/api/contacts/c_client/history')data={items:[{id:'history-1',kind:'document',title:'Original CV',detail:'<img src=x onerror=alert(1)>',date:'2026-10-10',route:'/cases/case_client#record-tools?tab=documents'}],total:26};
      else if(url.pathname==='/api/workspace-priorities'){const queue=url.searchParams.get('queue');if(options.slowQueue&&queue==='overdue')await new Promise(r=>setTimeout(r,500));data={queue,canManage:true,items:[{id:'priority-1',title:queue+' record',reason:'Review',action:'Call client',responsible:'u_1',deadline:'2026-10-20',route:'/leads/l_client'}],total:26,counts:{overdue:26,documents:2,missingPlans:4,finance:1},finance:{PHP:{received:1000,outstanding:500,overdue:100,pending:200}},today:'2026-10-11'};}
      else if(url.pathname==='/api/operations/attention')data={counts:{emailUncertain:1},deliveries:[{subject:'Uncertain test message',deliveryExplanation:'Check provider evidence before retrying',route:'/contacts/c_client#record-tools?tab=conversations'}],backup:{state:'unknown',restoreState:'not_verified'},checkedAt:'2026-10-11'};
      else if(url.pathname==='/api/reconciliation')data={items:[{id:'bank-1',reference:'BANK-1',date:'2026-10-10',currency:'PHP',amount:1000,revision:'bank-version'}],total:1,unmatched:1,receipts:[{id:'receipt-1',reference:'Valid receipt',paidOn:'2026-10-10',currency:'PHP',amount:1000},{id:'receipt-2',reference:'Wrong currency',paidOn:'2026-10-10',currency:'USD',amount:1000}]};
      else if(url.pathname==='/api/reconciliation/bank-1/match'){status=409;data={error:'This receipt was already matched. Refresh before matching.'};}
      else if(url.pathname==='/api/cases/case_client/blockers')data={owner:'Adviser',nextAction:'Review passport',deadline:'2026-10-12',blockingCount:1,completedCount:1,requiredCount:2,items:[],checklist:[{id:'missing-passport',title:'Passport',status:'Requested',complete:false,attention:'Missing required file',responsible:'Adviser',dueDate:'2026-10-12',route:'/cases/case_client#record-tools?tab=documents',editable:true,assignees:[{id:'u_1',name:'Demo User'}],revision:'doc-version'},{id:'complete-cv',title:'CV',status:'Verified',complete:true,responsible:'Adviser',route:'/cases/case_client#record-tools?tab=documents',editable:false}]};
      else if(url.pathname==='/api/staff-directory')data={staff:[{id:'u_1',name:'Demo User'},{id:'u_manager',name:'Adviser'}]};
      else if(url.pathname==='/api/assignments/review')data={items:[{entity:'leads',id:'l_client',label:'Prospective Client',previous:'Historical Flor',suggestedId:'u_1',editable:true,revision:'legacy-version',route:'/leads/l_client',staff:[{id:'u_1',name:'Demo User'}]}],total:1};
      else if(url.pathname==='/api/assignments/leads/l_client'){if(options.staleMapping){status=409;data={error:'Assignment changed'}}else data={mapped:'l_client',staffName:'Demo User'};}
      else if(url.pathname==='/api/staff-options') data={staff:[{id:'u_1',name:'Demo User'},{id:'u_manager',name:'Adviser'}]};
      else if(url.pathname==='/api/my-work') {data={scope:url.searchParams.get('scope')||'mine',teamId:url.searchParams.get('team')||'',teamName:'',category:url.searchParams.get('category')||'',today:'2026-10-10',total:url.searchParams.get('category')==='documents'?1:url.searchParams.get('category')==='overdueLeads'?0:60,counts:{applications:60,documents:1,followups:0,deadlines:1,tasks:0},items:url.searchParams.get('category')==='overdueLeads'?[]:[{id:'case_client',entity:'case',name:'ECC-001',reason:'Required documents need review',action:'Review passport',owner:'Adviser',priority:'high',deadline:'2026-10-12',route:'/cases/case_client'}]};if(!url.searchParams.get('category'))data.items=Array.from({length:Math.min(25,Math.max(0,data.total-Number(url.searchParams.get('offset')||0)))},(_,i)=>({...data.items[0],id:'case_'+i}));if(options.workResponse){const override=await options.workResponse(url,data);if(override){data=override.data;status=override.status||200;}}}
      else if(url.pathname==='/api/students/s_client/journey') data={student,applications:flow.cases.map(c=>({...c,assignedOfficer:'Adviser',nextAction:'Request passport'})),documents:flow.documents.map(d=>({...d,required:true})),invoices:[{id:'invoice-1',invoiceNumber:'INV-1',currency:'PHP',balance:50,amountReceived:20}],payments:[{invoiceId:'invoice-1',reference:'Receipt-1',amount:20,currency:'PHP'}],messages:[{caseId:'case_client',subject:'Portal response',body:'<img src=x onerror=alert(1)>',channel:'portal',direction:'inbound',createdAt:'2026-10-10'}],messageTotal:1,required:1,verified:0};
      else if(url.pathname==='/api/form-quality') data={findings:JSON.parse(req.postData()).studentCode==='DUP'?[{title:'Possible duplicate student',detail:'Review Student One.',route:'/students/s_client'}]:[]};
      else if(url.pathname==='/api/integrations/status') data={canTest:true,integrations:[{id:'email',name:'Email',state:'needs_configuration',message:'Configure SMTP.'},{id:'payments',name:'Payments',state:'configured',message:'Run a connection check.'}]};
      else if(url.pathname==='/api/admin/integrations/payments/test') data={id:'payments',name:'Payments',state:'failing',message:'Verify credentials and provider access.',checkedAt:'2026-10-10T08:00:00Z'};
      else if(url.pathname==='/api/follow-up-templates')data={canManage:true,templates:[{id:'documents',name:'Document request',subject:'Application documents',body:'Hello {{name}}, next step: {{nextAction}} by {{followUpDate}}.',builtin:true}]};
      else if(url.pathname==='/api/leads/l_client/conversion-preview')data={lead:flow.leads[0],documents:flow.documents.filter(d=>d.leadId==='l_client'),duplicates:options.conversionDuplicates?[{id:'c_other',entity:'contacts',detail:'Review Other Client — matching phone.'}]:[],editable:true,revision:'lead-version'};
      else if(url.pathname==='/api/control-center') data=center;
      else if(url.pathname==='/api/workflows') data=flow;
      else if(url.pathname==='/api/insights') data={cohort:'All accessible records',sources:[{source:'Website',leads:501,converted:100,rate:19.96}],enrollment:[],agents:[],stages:[],nextActions:[{record:'ECC-001',action:'Request passport',deadline:'2026-10-01',url:'/cases/case_client'}]};
      else if(url.pathname==='/api/assistant/capabilities') data={enabled:true,actions:true};
      else if(url.pathname==='/api/assistant/threads') data={threads:[]};
      else if(url.pathname==='/api/assistant/chat') data={reply:'<img src=x onerror=alert(1)>',threadId:'thread-1',version:1,sources:[{title:'Client One',url:'/contacts/c_client'}],actions:[{id:'action-1',kind:'update_record',label:'Client One',status:'pending',fields:{name:'Updated client'},before:{name:'Client One'}}]};
      else if(url.pathname==='/api/assistant/jobs') data={jobs:[]};
      else if(url.pathname==='/api/portal/invitations') data={invitations:[],url:'http://crm.test/portal#invite=private',message:'Share this invitation'};
      else if(url.pathname==='/api/portal/me') data={email:contact.email,student:{name:'Client One',applicationStage:'Applying'},cases:[{id:'case_client',caseNumber:'ECC-001',stage:'Documents Pending',nextAction:'Upload passport'}],documents:[{id:'doc_client',name:'Passport',required:true,status:'Requested',caseNumber:'ECC-001',latestVersion:0}],invoices:[],messages:[]};
      else if(url.pathname==='/api/data-quality') data={total:1,totalAll:1,page:1,pages:1,findings:[{severity:'error',title:'Deadline is overdue',detail:'ECC-001 passed its deadline.',entity:'cases',recordId:'case_client',route:'/cases/case_client'}]};
      else if(url.pathname==='/api/follow-up-rules') data={rules:[{id:'rule-1',data:JSON.stringify({name:'Stale case',entity:'cases',stage:'',inactiveDays:5,taskTitle:'Follow {{record}}',description:'Check in',enabled:false}),count:1}]};
      else if(url.pathname.endsWith('/rule-1/preview')) data={count:1,records:[{name:'ECC-001',lastTouch:'2026-09-20'}],previewToken:'preview-token',previewExpiresAt:'2026-10-07T09:05:00Z'};
      else if(url.pathname==='/api/follow-up-rules/rule-1'&&req.method()==='PATCH') {status=409;data={error:'Records changed since the preview. Preview the rule again before enabling it.'};}
      else if((url.pathname.includes('/conversations')||url.pathname==='/api/communication')) data={messages:[{channel:'email',direction:'inbound',subject:'Reply',body:'<img src=x onerror=alert(1)>',status:'received'}]};
      else if(url.pathname==='/api/contacts/c_client'&&req.method()==='PUT'){status=options.staleContact?409:200;data=options.staleContact?{error:'Record changed'}:{contact};}
      else if(url.pathname==='/api/contacts/c_client'&&req.method()==='GET') data={contact};
      else data={status:'ok'};
      await req.respond({status,contentType,body:typeof data==='object'&&!Buffer.isBuffer(data)?JSON.stringify(data):data});
    }catch(e){errors.push(e.message);await req.abort().catch(()=>{});}
  });
  await page.goto('http://crm.test/'+(view==='portal'?'portal#invite=single-use-invitation':''),{waitUntil:'networkidle0'});
  return {page,calls,errors,flow,center,contact};
}

test('contact tools stay on the record, default to the correct client and show safe conversation text', async () => {
  const {page,errors}=await fixture();
  try {
    await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.querySelector('form'));
    assert.equal(await page.$eval('body',el=>el.querySelectorAll('iframe').length),0);
    const selected=await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('[name=contactId]').value);
    assert.equal(selected,'c_client');
    await page.evaluate(()=>[...document.querySelector('crm-record-tools').shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent==='Communication').click());
    await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.textContent.includes('<img src=x'));
    assert.equal(await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.querySelectorAll('img').length),0);
    assert.deepEqual(errors,[]);
  }finally{await page.close()}
});

test('student workflow hydrates existing values and sends its record version with edits', async()=>{
 const {page,calls,errors}=await fixture('students');
 try{
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('[name=intake]')?.value==='January 2027');
  await page.evaluate(()=>{const root=document.querySelector('crm-record-tools').shadowRoot;root.querySelector('[name=intake]').value='September 2027';root.querySelector('[name=intake]').closest('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('#notice').textContent.includes('Saved'));
  const mutation=calls.find(r=>r.path==='/api/workflows/student');assert.ok(mutation);assert.equal(mutation.headers['if-match'],'student-version');assert.equal(JSON.parse(mutation.body).intake,'September 2027');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('native workspace renders operational tabs without an iframe',async()=>{
 const {page,errors}=await fixture('workspace');try{await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button').length>5);assert.equal(await page.$eval('body',el=>el.querySelectorAll('iframe').length),0);assert.ok(await page.evaluate(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Trash')));assert.deepEqual(errors,[])}finally{await page.close()}
});

test('report date filters request server aggregates and retain full record counts',async()=>{
 const {page,calls,errors}=await fixture('insights');try{await page.waitForFunction(()=>document.querySelector('crm-insights').shadowRoot.textContent.includes('501'));await page.evaluate(()=>{const root=document.querySelector('crm-insights').shadowRoot;root.querySelector('[name=from]').value='2026-01-01';root.querySelector('form').requestSubmit()});await page.waitForFunction(()=>document.querySelector('crm-insights').shadowRoot.textContent.includes('501'));assert.ok(calls.filter(r=>r.path==='/api/insights').length>=2);assert.deepEqual(errors,[])}finally{await page.close()}
});

test('portal removes invitation credentials from the URL and supports document submission',async()=>{
 const {page,calls,errors}=await fixture('portal');try{await page.waitForSelector('input[type=file]');assert.equal(new URL(page.url()).hash,'');assert.equal(JSON.parse(calls.find(r=>r.path==='/api/portal/session').body).token,'single-use-invitation');assert.ok(await page.$eval('body',el=>el.textContent.includes('Document review')&&el.textContent.includes('0 of 1 required documents verified')&&el.textContent.includes('Upload Passport')));const file=path.join(os.tmpdir(),'ecc-portal-upload.txt');fs.writeFileSync(file,'Client document');const input=await page.$('input[type=file]');await input.uploadFile(file);await page.evaluate(()=>document.querySelector('input[type=file]').closest('form').requestSubmit());await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('uploaded'));assert.ok(calls.some(r=>r.path==='/api/portal/documents/doc_client/files'&&r.method==='POST'));assert.deepEqual(errors,[]);fs.unlinkSync(file)}finally{await page.close()}
});

test('data-quality scan filters findings and navigates to the affected case',async()=>{
 const {page,calls,errors}=await fixture('workspace');try{await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button').length);await page.evaluate(()=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent==='Data & views').click());await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Run data quality scan'));await page.evaluate(()=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Run data quality scan').click());await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Deadline is overdue'));const link=await page.$eval('crm-workspace',el=>[...el.shadowRoot.querySelectorAll('a')].find(a=>a.textContent==='Review cases')?.getAttribute('href'));assert.equal(link,'/cases/case_client');assert.ok(calls.some(c=>c.path==='/api/data-quality'&&c.path.includes('data-quality')));assert.deepEqual(errors,[])}finally{await page.close()}
});

test('follow-up rule preview surfaces a stale-preview rejection',async()=>{
 const {page,calls,errors}=await fixture('workspace');try{page.on('dialog',d=>d.accept());await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button').length);await page.evaluate(()=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent==='Workflows').click());await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Preview & enable'));await page.evaluate(()=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Preview & enable').click());await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Records changed since the preview'));assert.ok(calls.some(c=>c.path==='/api/follow-up-rules/rule-1/preview'));assert.deepEqual(errors,[])}finally{await page.close()}
});

test('a background refresh cannot replace the version attached to an open edit dialog',async()=>{
 const {page,calls,contact,errors}=await fixture('workspace');try{assert.deepEqual(errors,[]);assert.equal(await page.evaluate(()=>XMLHttpRequest.prototype.open.toString().includes('crmURL')),true);await page.evaluate(async()=>{const get=()=>new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});await get();document.body.append(Object.assign(document.createElement('div'),{className:'modal-panel'}));await new Promise(resolve=>setTimeout(resolve,0))});contact._revision='new-version';await page.evaluate(async()=>{await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('PUT','/api/contacts/c_client');xhr.onload=resolve;xhr.send('{}')})});assert.equal(calls.find(r=>r.path==='/api/contacts/c_client'&&r.method==='PUT').headers['if-match'],'old-version',JSON.stringify(calls.filter(r=>r.path==='/api/contacts/c_client')))}finally{await page.close()}
});

test('live app login, native record workflows, reporting and mobile layout', {skip:process.env.ECC_BROWSER_LIVE!=='true'},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-crm-browser-')),port='17001';
 const server=spawn(path.join(__dirname,'../build/ecc-crm'),[],{cwd:path.join(__dirname,'..'),env:{...process.env,SEED_DEMO_DATA:'true',PORT:port,DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'browser-test-secret-only',APP_URL:'http://localhost:'+port,ALLOW_SIGNUP:'false',GRAPH_ORG_ID:'',WHATSAPP_ORG_ID:''},stdio:'pipe'});
 const page=await browser.newPage();let output='';server.stderr.on('data',data=>output+=data);server.stdout.on('data',data=>output+=data);
 await page.setRequestInterception(true);page.on('request',request=>{if(new URL(request.url()).origin==='http://localhost:'+port)request.continue();else request.abort()});
 try{
  for(let i=0;i<100;i++){try{const response=await fetch('http://localhost:'+port+'/api/health');if(response.ok)break}catch{}await new Promise(resolve=>setTimeout(resolve,100))}
  await page.goto('http://localhost:'+port,{waitUntil:'networkidle2'});
  await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');
  await page.waitForSelector('.app-shell');
  await page.goto('http://localhost:'+port+'/contacts/c_1',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('form'));
  assert.equal(await page.$eval('body',el=>el.querySelectorAll('iframe').length),0);
  for (const width of [320,390,768]) {
    await page.setViewport({width,height:844,isMobile:true,hasTouch:true});
    await page.goto('http://localhost:'+port+'/contacts',{waitUntil:'networkidle2'});
    await page.waitForSelector('table[data-mobile-cards]');
    assert.ok(await page.$eval('body',el=>el.scrollWidth<=window.innerWidth+2), 'contacts overflow at '+width);
    assert.equal(await page.$eval('.mobile-nav',el=>getComputedStyle(el).display),'grid');
    if(width<=600) assert.equal(await page.$eval('table.data-table',el=>getComputedStyle(el).minWidth),'0px');
    await page.click('.topbar__menu-btn');
    await page.waitForSelector('.sidebar.is-open');
    await page.waitForFunction(()=>document.querySelector('.app-main').inert);
    assert.equal(await page.$eval('.app-main',el=>el.inert),true);
    await page.waitForFunction(()=>document.activeElement?.classList.contains('sidebar__close'));await page.click('.sidebar__close');
    await page.waitForFunction(()=>document.querySelector('.sidebar').inert);
    await page.evaluate(()=>[...document.querySelectorAll('.mobile-nav button')].find(b=>b.textContent.trim()==='Tasks').click());
    await page.waitForFunction(()=>location.pathname==='/tasks');
    assert.equal(await page.$eval('.app-main',el=>el.inert),false);
  }
  await page.setViewport({width:390,height:844,isMobile:true,hasTouch:true});
  await page.goto('http://localhost:'+port+'/contacts',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent.trim()==='Add contact'));await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='Add contact').click());
  await page.waitForSelector('.modal');
  assert.ok(await page.$eval('.modal',el=>el.getBoundingClientRect().width<=window.innerWidth));
  assert.equal(await page.$eval('.modal input',el=>getComputedStyle(el).fontSize),'16px');
  await page.click('.modal__close');
  await page.goto('http://localhost:'+port+'/administration',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('.administration-elm table'));
  await page.evaluate(()=>[...document.querySelector('.administration-elm').querySelectorAll('button')].find(b=>b.textContent==='Add user').click());
  await page.evaluate(()=>{const root=document.querySelector('.administration-elm');for(const [name,value] of Object.entries({name:'Browser Viewer',email:'browser-viewer@example.com',role:'viewer',password:'BrowserViewerPassword!'})){const field=root.querySelector('[name='+name+']');field.value=value;field.dispatchEvent(new Event('input',{bubbles:true}));}root.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('.administration-elm').textContent.includes('browser-viewer@example.com'));
  await page.evaluate(()=>[...document.querySelector('.administration-elm').querySelectorAll('nav button')].find(b=>b.textContent==='Access levels').click());
  await page.waitForFunction(()=>document.querySelector('.administration-elm').textContent.includes('Read only'));
  await page.setViewport({width:390,height:844});assert.ok(await page.$eval('body',el=>el.scrollWidth<=window.innerWidth+2));
  await page.goto('http://localhost:'+port+'/reports',{waitUntil:'networkidle2'});await page.waitForFunction(()=>document.querySelector('crm-insights').shadowRoot.textContent.includes('Lead conversion'));
  await page.setViewport({width:390,height:844});assert.ok(await page.$eval('body',el=>el.scrollWidth<=window.innerWidth+2));

  await page.setViewport({width:1280,height:900});
  assert.equal(await page.$('crm-nav-focus'),null);
  assert.equal(await page.evaluate(()=>[...document.querySelector('.sidebar nav[aria-label="Daily work"]').children].some(e=>e.textContent.trim()==='Leads'&&getComputedStyle(e).display!=='none')),true);
  await page.goto('http://localhost:'+port+'/leads',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent.trim()==='Add lead'));
  await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='Add lead').click());
  await page.waitForSelector('#lf-referrer');
  for(const [field,value]of Object.entries({name:'Flor CV Browser Client',email:'flor-cv-browser@example.com',referrer:'Flor',assignedTo:'u_1',followUpDate:'2026-10-20'}))await page.$eval('#lf-'+field,(e,value)=>{e.value=value;e.dispatchEvent(new Event('input',{bubbles:true}))},value);
  await page.evaluate(()=>[...document.querySelectorAll('.modal button')].find(b=>b.textContent.trim()==='Referral').click());
  await page.click('.modal button[type=submit]');
  await page.waitForFunction(()=>!document.querySelector('.modal'));
  const lead=await page.evaluate(async()=>{const out=await(await fetch('/api/leads?q=flor-cv-browser@example.com')).json();return out.leads[0]});
  assert.equal(lead.referrer,'Flor');assert.equal(lead.source,'Referral');
  await page.goto('http://localhost:'+port+'/leads/'+lead.id,{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.querySelector('[name=nextAction]'));
  await page.evaluate(()=>{const form=document.querySelector('crm-lead-work').shadowRoot.querySelector('[name=nextAction]').closest('form');form.querySelector('[name=nextAction]').value='Call about missing transcript';form.querySelector('[name=followUpDate]').value='2000-01-01';form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.textContent.includes('Next action: Call about missing transcript'));
  await page.evaluate(()=>{const root=document.querySelector('crm-lead-work').shadowRoot;root.querySelector('[name=body]').value='Discussed documents with client';root.querySelector('[name=followUp]').checked=true;root.querySelector('[name=body]').closest('form').requestSubmit()});
  await page.waitForFunction(()=>[...document.querySelector('crm-lead-work')?.shadowRoot.querySelectorAll('article')||[]].some(e=>e.textContent.includes('Discussed documents with client')));
  await page.goto('http://localhost:'+port+'/leads/'+lead.id,{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.querySelector('input[type=file]'));
  const cvPath=path.join(directory,'client.txt');fs.writeFileSync(cvPath,'Flor CV Browser Client\nDegree in business');
  const picker=await page.evaluateHandle(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('input[type=file]'));await picker.asElement().uploadFile(cvPath);
  await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('input[type=file]').closest('form').requestSubmit());
  await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.textContent.includes('Versions'));
  await page.setViewport({width:390,height:844,isMobile:true,hasTouch:true});
  assert.ok(await page.$eval('body',e=>e.scrollWidth<=innerWidth+2),'lead CV panel overflows on phone');
  await page.waitForFunction(()=>{const form=document.querySelector('crm-record-tools')?.shadowRoot.querySelector('[name=target]')?.closest('form');return form&&!form.querySelector('button[type=submit]').disabled});
  await page.evaluate(()=>{const form=document.querySelector('crm-record-tools').shadowRoot.querySelector('[name=target]').closest('form');form.querySelector('[name=target]').value='student';form.querySelector('[name=confirmed]').checked=true;form.querySelector('button[type=submit]').click()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.textContent.includes('Open application'));
  const converted=await page.evaluate(async id=>(await(await fetch('/api/leads/'+id)).json()).lead,lead.id);
  assert.ok(converted.convertedContactId&&converted.convertedStudentId&&converted.convertedCaseId);
  const documents=await page.evaluate(async id=>(await(await fetch('/api/documents?caseId='+id)).json()).documents,converted.convertedCaseId);
  assert.equal(documents.length,1);assert.equal(documents[0].docName,'Client CV');assert.equal(documents[0].latestVersion,1);
  const original=await page.evaluate(async id=>await(await fetch('/api/documents/'+id+'/files/1')).text(),documents[0].id);assert.ok(original.includes('Degree in business'));
  const requirement=await page.evaluate(async id=>{const response=await fetch('/api/documents',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({caseId:id,docName:'Browser transcript',required:true,status:'Requested'})});return await response.json()},converted.convertedCaseId);
  assert.ok(requirement.document?.id);
  await page.goto('http://localhost:'+port+'/cases/'+converted.convertedCaseId,{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('crm-application-blockers')?.shadowRoot.querySelector('[name=responsibleId]'));
  await page.evaluate(()=>{const form=document.querySelector('crm-application-blockers').shadowRoot.querySelector('[name=responsibleId]').closest('form');form.querySelector('[name=responsibleId]').value='u_1';form.querySelector('[name=dueDate]').value='2000-01-01';form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-application-blockers')?.shadowRoot.textContent.includes('Responsible: Demo User'));
  assert.ok(await page.evaluate(()=>document.querySelector('crm-application-blockers').shadowRoot.textContent.includes('0 of 1 accessible required documents complete')));
  await page.goto('http://localhost:'+port+'/reports',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>document.querySelector('crm-insights')?.shadowRoot.textContent.includes('Lead pipeline by source and referrer'));
  assert.ok(await page.evaluate(()=>document.querySelector('crm-insights').shadowRoot.textContent.includes('Flor')));
  await page.goto('http://localhost:'+port+'/leads',{waitUntil:'networkidle2'});
  await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent.trim()==='Add lead'));
  await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='Add lead').click());
  await page.waitForSelector('#lf-email');
  await page.$eval('#lf-name',e=>{e.value='Separate reviewed inquiry';e.dispatchEvent(new Event('input',{bubbles:true}))});await page.$eval('#lf-email',e=>{e.value='flor-cv-browser@example.com';e.dispatchEvent(new Event('input',{bubbles:true}))});
  await page.waitForFunction(()=>document.querySelector('crm-form-quality')?.shadowRoot.querySelector('a'));
  await page.click('.modal button[type=submit]');
  await page.waitForFunction(()=>document.querySelector('.modal input[type=checkbox]'));
  await page.$eval('.modal input[type=checkbox]',e=>{e.checked=true;e.dispatchEvent(new Event('change',{bubbles:true}))});
  await page.click('.modal button[type=submit]');
  await page.waitForFunction(()=>!document.querySelector('.modal'));

 }catch(error){fs.mkdirSync(path.join(__dirname,'artifacts'),{recursive:true});await page.screenshot({path:path.join(__dirname,'artifacts/live-failure.png'),fullPage:true});throw new Error(error.message+'\nUI: '+await page.evaluate(()=>JSON.stringify({url:location.pathname,width:innerWidth,mobile:matchMedia('(max-width: 900px)').matches,mainInert:document.querySelector('.app-main')?.inert,mainAttr:document.querySelector('.app-main')?.hasAttribute('inert'),sideInert:document.querySelector('.sidebar')?.inert,work:document.querySelector('.daily-work')?.textContent,active:document.activeElement?.outerHTML?.slice(0,200)}))+'\n'+output)}finally{await page.close();server.kill('SIGTERM');await new Promise(resolve=>{if(server.exitCode!==null)return resolve();server.once('exit',resolve)});fs.rmSync(directory,{recursive:true,force:true})}
});

test('live dashboard overview cards open record details on desktop and mobile',{skip:process.env.ECC_BROWSER_LIVE!=='true'},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-crm-overview-')),port='17002';
 const server=spawn(path.join(__dirname,'../build/ecc-crm'),[],{cwd:path.join(__dirname,'..'),env:{...process.env,SEED_DEMO_DATA:'true',PORT:port,DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'overview-test-secret-only',APP_URL:'http://localhost:'+port,ALLOW_SIGNUP:'false',GRAPH_ORG_ID:'',WHATSAPP_ORG_ID:''},stdio:'pipe'});
 const page=await browser.newPage();let output='';server.stdout.on('data',d=>output+=d);server.stderr.on('data',d=>output+=d);
 await page.setRequestInterception(true);page.on('request',r=>new URL(r.url()).origin==='http://localhost:'+port?r.continue():r.abort());
 try{
  for(let i=0;i<100;i++){try{if((await fetch('http://localhost:'+port+'/api/health')).ok)break}catch{}await new Promise(r=>setTimeout(r,100))}
  await page.setViewport({width:1280,height:900});
  await page.goto('http://localhost:'+port,{waitUntil:'networkidle2'});
  await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');
  await page.waitForSelector('.app-shell');
  for(const width of [1280,390]){
   await page.setViewport({width,height:900});
  await page.waitForFunction(()=>document.querySelector('.daily-work')?.querySelector('.work-item'));
  await page.$eval('.daily-work',host=>host.querySelectorAll('details.journey-section').forEach(section=>section.open=true));
  await page.waitForFunction(()=>getComputedStyle(document.querySelector('.daily-work').querySelector('.work-count')).display==='grid');
  for(const category of ['deals','pipeline','leads','students','cases','applications','followups','overdueLeads','documents','deadlines']){
    const response=page.waitForResponse(r=>{const url=new URL(r.url());return url.pathname==='/api/my-work'&&url.searchParams.get('category')===category});
    await page.evaluate(category=>document.querySelector('.daily-work').querySelector('[data-category="'+category+'"]').scrollIntoView({block:'center',behavior:'instant'}),category);
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    await page.click('.daily-work [data-category="'+category+'"]');
    const out=await (await response).json();assert.equal(out.category,category);
    await page.waitForFunction(category=>{const root=document.querySelector('.daily-work');return root.querySelector('[data-category="'+category+'"]').getAttribute('aria-pressed')==='true'&&root.querySelector('[aria-busy="false"]')}, {},category);
    if(category==='cases'||category==='applications'||category==='documents')assert.ok(out.items.every(item=>item.entity==='case'));
    if(category==='leads'||category==='followups'||category==='overdueLeads')assert.ok(out.items.every(item=>item.entity==='lead'));
    if(out.total)assert.ok(await page.evaluate(()=>[...document.querySelector('.daily-work').querySelectorAll('.work-item a')].every(a=>a.getAttribute('href').startsWith('/'))));
  }
  assert.equal(await page.$$eval('[data-work-category]',cards=>cards.length),0);
   await page.focus('.daily-work [data-category="deals"]');
   const keyboardResponse=page.waitForResponse(r=>{const url=new URL(r.url());return url.pathname==='/api/my-work'&&url.searchParams.get('category')==='deals'});
   await page.keyboard.press('Enter');assert.equal((await (await keyboardResponse).json()).category,'deals');
   await page.waitForFunction(()=>document.querySelector('.daily-work').querySelector('[aria-busy="false"]'));
  }
  await page.setViewport({width:1280,height:900});
  await page.goto('http://localhost:'+port+'/deals',{waitUntil:'networkidle2'});
  await page.waitForSelector('.deals-filter-panel');
  assert.equal(await page.$eval('.deals-filter-panel',e=>e.open),false);
  assert.equal(await page.$eval('.deals-extra-summary',e=>e.open),false);
  assert.equal(await page.$eval('.deals-summary',e=>e.querySelectorAll('.deals-summary__kpi').length),3);
  assert.equal(await page.$$eval('.pipeline-col__weighted, .pipeline-col__bar, .deal-card__age',e=>e.length),0);
  await page.click('.deals-filter-panel > summary');
  await page.waitForFunction(()=>document.querySelector('crm-staff-filter')?.shadowRoot.querySelector('select'));
  assert.equal(await page.$eval('.deals-filter-panel',e=>e.open),true);
  await page.click('.deals-extra-summary > summary');
  assert.equal(await page.$eval('.deals-extra-summary',e=>e.open),true);
  await page.focus('.deal-card');
  await page.waitForFunction(()=>getComputedStyle(document.querySelector('.deal-card__menu')).opacity==='1');
  await page.keyboard.press('Enter');
  await page.waitForSelector('.detail-hero');
  await page.goto('http://localhost:'+port+'/deals',{waitUntil:'networkidle2'});
  await page.waitForSelector('.pipeline-board');
  await page.setViewport({width:390,height:900});
  assert.equal(await page.$eval('.deals-pipeline .pipeline-board',e=>getComputedStyle(e).gridAutoFlow),'row');
  await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='Add deal').click());
  await page.waitForSelector('.modal');
  await page.goto('http://localhost:'+port,{waitUntil:'networkidle2'});
  await page.goto('http://localhost:'+port+'/leads/l_1',{waitUntil:'networkidle2'});
  await page.waitForSelector('.detail-hero__actions');
  await page.evaluate(()=>[...document.querySelectorAll('.detail-hero__actions button')].find(b=>b.textContent.trim()==='Edit').click());
  await page.waitForFunction(()=>document.querySelector('crm-staff-picker')?.shadowRoot.textContent.includes('Choose an active account'));
  await page.select('crm-staff-picker >>> select','u_1');
  const saveResponse=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/leads/l_1'&&r.request().method()==='PUT');
  await page.click('.modal button[type=submit]');const saved=await saveResponse;
  assert.equal(saved.status(),200);assert.equal(JSON.parse(saved.request().postData()).assignedTo,'u_1');
  await page.waitForFunction(()=>!document.querySelector('.modal'));
 }catch(error){throw new Error(error.stack+'\nUI: '+await page.evaluate(()=>JSON.stringify({path:location.pathname,work:document.querySelector('.daily-work')?.textContent,display:document.querySelector('.work-count')&&getComputedStyle(document.querySelector('.work-count')).display,root:document.querySelector('.work-dashboard-elm')?.className,sheets:[...document.styleSheets].map(sheet=>({href:sheet.href,rules:[...sheet.cssRules].filter(rule=>rule.selectorText?.includes('work-count')).map(rule=>rule.cssText)}))}))+'\n'+output)}finally{await page.close();server.kill('SIGTERM');await new Promise(resolve=>{if(server.exitCode!==null)return resolve();server.once('exit',resolve)});fs.rmSync(directory,{recursive:true,force:true})}
});

test('historical assignment review requires confirmation and keeps a stale mapping selection',async()=>{
 const options={staleMapping:true};const {page,calls,errors}=await fixture('workspace',options);try{
  await page.evaluate(()=>document.body.append(document.createElement('crm-assignment-review')));
  await page.waitForFunction(()=>document.querySelector('crm-assignment-review').shadowRoot.textContent.includes('Historical Flor'));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-assignment-review').shadowRoot.querySelector('select').value),'u_1');
  await page.evaluate(()=>document.querySelector('crm-assignment-review').shadowRoot.querySelector('form').requestSubmit());
  assert.equal(calls.filter(c=>c.path==='/api/assignments/leads/l_client').length,0);
  await page.evaluate(()=>{const form=document.querySelector('crm-assignment-review').shadowRoot.querySelector('form');form.querySelector('[name=confirmed]').checked=true;form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-assignment-review').shadowRoot.textContent.includes('Assignment changed'));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-assignment-review').shadowRoot.querySelector('select').value),'u_1');
  options.staleMapping=false;
  await page.evaluate(()=>document.querySelector('crm-assignment-review').shadowRoot.querySelector('form').requestSubmit());
  await page.waitForFunction(()=>document.querySelector('crm-assignment-review').shadowRoot.textContent.includes('record ownership was preserved'));
  const save=calls.find(c=>c.path==='/api/assignments/leads/l_client');assert.equal(save.headers['if-match'],'legacy-version');assert.equal(JSON.parse(save.body).confirmed,true);assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('staff labels and owner filters show names while preserving account IDs',async()=>{
 const {page,errors}=await fixture('workspace');try{
  await page.evaluate(()=>{const name=document.createElement('crm-staff-name');name.setAttribute('value','u_1');document.body.append(name);const filter=document.createElement('crm-staff-filter');filter.setAttribute('owners',JSON.stringify(['u_1','Historical Flor']));filter.setAttribute('value','u_1');document.body.append(filter)});
  await page.waitForFunction(()=>document.querySelector('crm-staff-name').textContent==='Demo User');
  await page.waitForFunction(()=>document.querySelector('crm-staff-filter').shadowRoot.querySelector('option[value="u_1"]').textContent==='Demo User');
  assert.equal(await page.evaluate(()=>document.querySelector('crm-staff-filter').value),'u_1');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('daily work renders full counts without AI and pages the assignment queue',async()=>{
 const {page,calls,errors}=await fixture('daily');try{
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('60 work items'));
  assert.equal(await page.$eval('.daily-work',host=>host.querySelector('details.journey-section').open),false);
  assert.ok(await page.evaluate(()=>{const root=document.querySelector('.daily-work');return root.querySelector('a').getAttribute('href')==='/cases/case_client'&&root.textContent.includes('Needs attention')&&root.textContent.includes('Browse all records')&&root.querySelectorAll('.work-counts').length===2}));
  await page.evaluate(()=>[...document.querySelector('.daily-work').querySelectorAll('button')].find(b=>b.textContent==='Next').click());
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('26–50 of 60')).catch(async error=>{throw new Error(error.message+' '+await page.evaluate(()=>document.querySelector('.daily-work').textContent))});
  await page.evaluate(()=>document.querySelector('.daily-work').querySelector('[data-category="documents"]').click());
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('1 work items'));
  assert.ok(calls.some(c=>c.path==='/api/my-work'&&c.query.includes('category=documents')&&c.query.includes('offset=0')));
  assert.ok(await page.evaluate(()=>{const root=document.querySelector('.daily-work');return root.textContent.includes('Responsible: Adviser')&&root.textContent.includes('Due 2026-10-12')&&[...root.querySelectorAll('a')].some(a=>a.textContent==='Review application and next action'&&a.getAttribute('href')==='/cases/case_client')}));
  await page.evaluate(()=>document.querySelector('.daily-work').querySelector('[data-category="overdueLeads"]').click());
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('No matching work items'));
  await page.evaluate(()=>[...document.querySelector('.daily-work').querySelectorAll('button')].find(b=>b.textContent==='Show all work').click());
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('60 work items'));
  assert.equal(calls.filter(c=>c.path.includes('/assistant')).length,0);assert.deepEqual(errors,[]);
 }finally{await page.close()}
});
test('daily work preserves controls on slow requests, ignores stale results and recovers from errors',async()=>{
 const options={};const {page,errors}=await fixture('daily',options);
 try{
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('60 work items'));
  options.workResponse=async(url,data)=>{if(url.searchParams.get('category')==='documents')await new Promise(resolve=>setTimeout(resolve,600));return {data}};
  await page.evaluate(()=>{const root=document.querySelector('.daily-work');root.querySelector('.work-counts').parentElement.open=true;window.workButton=root.querySelector('[data-category="documents"]');window.workButton.click();});
  assert.ok(await page.evaluate(()=>{const root=document.querySelector('.daily-work');return window.workButton.isConnected&&root.querySelector('[aria-busy="true"]')&&root.querySelector('h3').textContent==='Applications needing documents'}));
  await page.click('.daily-work [data-category="overdueLeads"]');
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('No matching work items'));
  await new Promise(resolve=>setTimeout(resolve,800));
  assert.equal(await page.evaluate(()=>document.querySelector('.daily-work').querySelector('h3').textContent),'Overdue lead follow-ups');
  assert.ok(await page.evaluate(()=>window.workButton.isConnected));
  options.workResponse=async()=>({status:503,data:{error:'Temporary database failure'}});
  await page.click('.daily-work [data-category="documents"]');
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('Temporary database failure'));
  assert.ok(await page.evaluate(()=>{const root=document.querySelector('.daily-work');return !root.querySelector('button[type="submit"]').disabled&&root.querySelectorAll('[data-category]').length===16&&!root.querySelector('[aria-busy="true"]')}));
  options.workResponse=async(url,data)=>{delete data.category;return {data}};
  await page.click('.daily-work button[type="submit"]');
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('Could not read the response'));
  options.workResponse=null;
  await page.click('.daily-work button[type="submit"]');
  await page.waitForFunction(()=>document.querySelector('.daily-work').textContent.includes('1 work items'));
  assert.ok(await page.evaluate(()=>document.querySelector('.daily-work').querySelector('.work-item a').getAttribute('href')==='/cases/case_client'));
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('daily overview cards show record details and links for all five categories',async()=>{
 const entities={deals:'deal',pipeline:'deal',leads:'lead',students:'student',cases:'case'};
 const options={workResponse:async(url,data)=>{
  const category=url.searchParams.get('category');if(!entities[category])return {data};
  const entity=entities[category],plural={deal:'deals',lead:'leads',student:'students',case:'cases'}[entity];
  return {data:{...data,total:1,items:[{id:'overview',entity,name:'Specific '+entity,reason:'Status: Active',action:'Review details',owner:'Adviser',route:'/'+plural+'/overview',priority:'medium',details:['Program: Nursing','Source: Flor']}]}};
 }};
 const {page,errors}=await fixture('daily',options);
 try{
  await page.waitForFunction(()=>document.querySelector('.daily-work').querySelector('.work-item'));
  await page.$eval('.daily-work',host=>host.querySelectorAll('details.journey-section').forEach(section=>section.open=true));
  for(const [category,entity]of Object.entries(entities)){
   await page.click('.daily-work [data-category="'+category+'"]');
   await page.waitForFunction(entity=>!document.querySelector('.daily-work [aria-busy=true]')&&document.querySelector('.daily-work').textContent.includes('Specific '+entity),{},entity);
   assert.ok(await page.evaluate(entity=>{const root=document.querySelector('.daily-work');return root.textContent.includes('Program: Nursing')&&root.textContent.includes('Source: Flor')&&[...root.querySelectorAll('.work-item a')].some(a=>a.classList.contains('button')&&a.getAttribute('href')==='/'+({deal:'deals',lead:'leads',student:'students',case:'cases'}[entity])+'/overview')},entity));
  }
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('student journey keeps owner, next action, documents and currency-specific payments together',async()=>{
 const {page,errors}=await fixture('journey');try{
  await page.waitForFunction(()=>document.querySelector('crm-student-journey').shadowRoot.textContent.includes('Assigned adviser: Adviser'));
  const result=await page.evaluate(()=>{const root=document.querySelector('crm-student-journey').shadowRoot;return {text:root.textContent,images:root.querySelectorAll('img').length,sections:root.querySelectorAll('details').length}});
  assert.ok(result.text.includes('Request passport')&&result.text.includes('PHP')&&result.text.includes('Receipt-1')&&result.text.includes('Portal response'));assert.equal(result.images,0);assert.equal(result.sections,4);assert.deepEqual(errors,[]);
 }finally{await page.close()}
});
test('inline duplicate warnings clear after input changes and keep review links safe',async()=>{
 const {page,errors}=await fixture('quality');try{
  await page.waitForFunction(()=>document.querySelector('crm-form-quality').shadowRoot.textContent.includes('Possible duplicate student'));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-form-quality').shadowRoot.querySelector('a').getAttribute('rel')),'noopener');
  await page.evaluate(()=>document.querySelector('crm-form-quality').setAttribute('studentcode','UNIQUE'));
  await page.waitForFunction(()=>document.querySelector('crm-form-quality').shadowRoot.querySelector('.quality-hints').textContent==='');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});
test('integration checks distinguish setup from provider failure and expose retry guidance',async()=>{
 const {page,calls,errors}=await fixture('connections');try{
  await page.waitForFunction(()=>document.querySelector('crm-integration-health').shadowRoot.querySelectorAll('.card').length===2);
  assert.equal(await page.evaluate(()=>document.querySelector('crm-integration-health').shadowRoot.querySelector('.card button').disabled),true);
  await page.evaluate(()=>document.querySelector('crm-integration-health').shadowRoot.querySelectorAll('.card button')[1].click());
  await page.waitForFunction(()=>document.querySelector('crm-integration-health').shadowRoot.textContent.includes('Verify credentials'));
  assert.ok(calls.some(c=>c.path==='/api/admin/integrations/payments/test'&&c.method==='POST'));assert.deepEqual(errors,[]);
 }finally{await page.close()}
});


test('AI proposals remain pending until staff explicitly confirm them',async()=>{
 const {page,calls,errors}=await fixture('ai');try{
  await page.evaluate(()=>document.querySelector('crm-ai-chat').shadowRoot.querySelector('button').click());
  await page.waitForFunction(()=>document.querySelector('crm-ai-chat').shadowRoot.querySelector('form button')?.disabled===false);
  await page.evaluate(()=>{const root=document.querySelector('crm-ai-chat').shadowRoot;root.querySelector('textarea').value='Suggest an update';root.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-ai-chat').shadowRoot.textContent.includes('Proposed — not executed.'));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-ai-chat').shadowRoot.querySelectorAll('img').length),0);
  assert.ok(!calls.some(c=>c.path.endsWith('/confirm')));
  await page.evaluate(()=>[...document.querySelector('crm-ai-chat').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Confirm action').click());
  await page.waitForFunction(()=>document.querySelector('crm-ai-chat').shadowRoot.textContent.includes('Confirmed successfully.'));
  assert.equal(calls.filter(c=>c.path.endsWith('/confirm')).length,1);assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

 test('record picker searches beyond loaded pages, retains selection and ignores stale responses',async()=>{
 const {page,errors}=await fixture('picker');
 try {
  await page.waitForFunction(()=>document.querySelector('crm-record-picker').shadowRoot.textContent.includes('Client One'));
  const search=await page.$('crm-record-picker >>> input[type=search]');
  await search.focus();
  await page.waitForFunction(()=>document.querySelector('crm-record-picker').shadowRoot.textContent.includes('of 240'));
  await page.evaluate(()=>[...document.querySelector('crm-record-picker').shadowRoot.querySelectorAll('.paging button')].find(b=>b.textContent==='Next').click());
  await page.waitForFunction(()=>document.querySelector('crm-record-picker').shadowRoot.querySelector('.results button')?.textContent.includes('pick-20'),{timeout:5000});
  await page.evaluate(()=>{const search=document.querySelector('crm-record-picker').shadowRoot.querySelector('input');search.value='Slow';search.dispatchEvent(new Event('input'))});
  await new Promise(resolve=>setTimeout(resolve,350));
  await page.evaluate(()=>{const search=document.querySelector('crm-record-picker').shadowRoot.querySelector('input');search.value='Searchable client 239';search.dispatchEvent(new Event('input'))});
  await page.waitForFunction(()=>document.querySelector('crm-record-picker').shadowRoot.querySelector('.results button')?.textContent.includes('pick-239'));
  await new Promise(resolve=>setTimeout(resolve,750));
  assert.equal(await page.$eval('crm-record-picker',host=>host.value),'c_client');
  assert.equal(await page.$eval('crm-record-picker',host=>host.shadowRoot.textContent.includes('Slow result')),false);
  await search.focus();await page.keyboard.press('ArrowDown');
  assert.ok(await page.$eval('crm-record-picker',host=>host.shadowRoot.activeElement.tagName==='BUTTON'&&getComputedStyle(host.shadowRoot.activeElement).outlineStyle!=='none'));
  await page.keyboard.press('Enter');
  assert.equal(await page.$eval('crm-record-picker',host=>host.value),'pick-239');
  assert.deepEqual(errors,[]);
 }catch(error){throw new Error(error.message+' '+await page.$eval('crm-record-picker',host=>JSON.stringify({offset:host.offset,text:host.shadowRoot.textContent}))+' '+JSON.stringify(calls))}finally{await page.close()}
 });


test('lead intake keeps its CV separate from other cases and requires reviewed fields and conversion confirmation',async()=>{
 const {page,calls,errors}=await fixture('leads');try{
  await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.textContent.includes('Upload CV'));
  const text=await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.textContent);assert.ok(text.includes('Client CV'));assert.ok(!text.includes('Passport'));assert.ok(text.includes('Convert lead'));assert.ok(text.includes('Client intake'));assert.ok(text.includes('Status: New'));assert.ok(text.includes('Assigned to: Adviser'));assert.ok(text.includes('Created: 2026-10-04'));assert.ok(text.includes('CV/document attached: Recorded'));assert.ok(text.includes('Next action and follow-up scheduled: Recorded'));assert.ok(text.includes('Converted to a client record: Pending'));
  await page.evaluate(()=>[...document.querySelector('crm-record-tools').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Review CV fields').click());
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('#cv-review [name=name]')?.value==='Reviewed Prospect');
  assert.equal(calls.filter(c=>c.path.endsWith('/cv-review')).length,0);
  const notes=await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('#cv-review [name=notes]').value);assert.ok(notes.includes('Existing inquiry notes'));assert.ok(notes.includes('Degree in business'));
  await page.evaluate(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('#cv-review form').requestSubmit());assert.equal(calls.filter(c=>c.path.endsWith('/cv-review')).length,0);
  await page.evaluate(()=>{const form=document.querySelector('crm-record-tools').shadowRoot.querySelector('#cv-review form');form.querySelector('[name=confirmed]').checked=true;form.querySelector('[name=name]').value='Staff corrected name';form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('#notice').textContent.includes('Reviewed CV details saved'));
  const save=calls.find(c=>c.path==='/api/leads/l_client/cv-review');assert.equal(save.headers['if-match'],'lead-version');const data=JSON.parse(save.body);assert.equal(data.confirmed,true);assert.equal(data.fields.name,'Staff corrected name');assert.equal(data.fields.source,undefined);
  await page.setViewport({width:390,height:844,isMobile:true,hasTouch:true});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.querySelector('[name=target]'));
  await page.evaluate(()=>{const root=document.querySelector('crm-record-tools').shadowRoot;const form=root.querySelector('[name=target]').closest('form');form.querySelector('[name=confirmed]').checked=true;form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('a[href="/cases/case_client"]'));
  const conversion=calls.find(c=>c.path==='/api/workflows/lead-convert');assert.equal(JSON.parse(conversion.body).target,'application');assert.equal(conversion.headers['if-match'],'lead-version');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});


test('native staff picker retains legacy selections and emits account IDs',async()=>{
 const {page,errors}=await fixture('leadwork');try{
  await page.evaluate(()=>{const picker=document.createElement('crm-staff-picker');picker.setAttribute('entity','leads');picker.setAttribute('record-id','l_client');picker.setAttribute('value','Historical Flor');picker.setAttribute('label','Assigned consultant');picker.addEventListener('input',()=>{window.selectedStaff=picker.value});document.body.append(picker)});
  await page.waitForFunction(()=>document.querySelector('crm-staff-picker').shadowRoot.textContent.includes('Choose an active account'));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-staff-picker').value),'Historical Flor');
  await page.select('crm-staff-picker >>> select','u_1');
  assert.equal(await page.evaluate(()=>window.selectedStaff),'u_1');
  await page.evaluate(()=>document.querySelector('crm-staff-picker').setAttribute('disabled',''));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-staff-picker').shadowRoot.querySelector('select').disabled),true);assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('staff selector uses active account IDs and lead drafts survive stale saves',async()=>{
 const options={staleLead:true};const {page,calls,errors}=await fixture('leadwork',options);
 try{
  await page.waitForFunction(()=>document.querySelector('crm-lead-work').shadowRoot.querySelector('[name=assignedTo]'));
  const result=await page.evaluate(()=>{const root=document.querySelector('crm-lead-work').shadowRoot;return {tag:root.querySelector('[name=assignedTo]').tagName,options:[...root.querySelector('[name=assignedTo]').options].map(o=>o.value),statuses:[...root.querySelector('[name=status]').options].map(o=>o.value)}});
  assert.equal(result.tag,'SELECT');assert.ok(result.options.includes('u_1'));assert.ok(!result.statuses.includes('Converted'));
  await page.evaluate(()=>{const root=document.querySelector('crm-lead-work').shadowRoot;root.querySelector('[name=assignedTo]').value='u_1';const action=root.querySelector('[name=nextAction]');action.value='Keep this draft';action.dispatchEvent(new Event('input',{bubbles:true}));root.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-lead-work').shadowRoot.textContent.includes('Your draft has been kept'));
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('crm:record-changed',{detail:'l_client'})));
  assert.equal(await page.evaluate(()=>document.querySelector('crm-lead-work').shadowRoot.querySelector('[name=nextAction]').value),'Keep this draft');
  await page.evaluate(()=>[...document.querySelector('crm-lead-work').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Load current version and keep draft').click());
  await page.waitForFunction(()=>document.querySelector('crm-lead-work').shadowRoot.textContent.includes('Compare it before saving again'));
  options.staleLead=false;
  await page.evaluate(()=>document.querySelector('crm-lead-work').shadowRoot.querySelector('form').requestSubmit());
  await page.waitForFunction(()=>document.querySelector('crm-lead-work').shadowRoot.textContent.includes('Next action: Keep this draft'));
  assert.equal(JSON.parse(calls.filter(c=>c.path==='/api/leads/l_client'&&c.method==='PUT').at(-1).body).assignedTo,'u_1');assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('CV upload and version review show different indicators',async()=>{
 const {page,calls,errors}=await fixture('leads');try{
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.textContent.includes('Uploaded; current version not reviewed'));
  page.on('dialog',d=>d.accept());
  await page.evaluate(()=>[...document.querySelector('crm-record-tools').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Record review of version 1').click());
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.textContent.includes('Reviewed version 1 by Demo User'));
  assert.ok(calls.some(c=>c.path==='/api/documents/cv_client/review'&&JSON.parse(c.body).confirmed));assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('lead work edits next actions with a revision, logs performed activity and pages safe timeline text',async()=>{
 const {page,calls,errors}=await fixture('leadwork');try{
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.querySelector('[name=nextAction]')?.value==='Call about CV');
  assert.equal(await page.evaluate(()=>document.querySelector('crm-lead-work').shadowRoot.querySelectorAll('img').length),0);
  await page.evaluate(()=>{const form=document.querySelector('crm-lead-work').shadowRoot.querySelector('[name=nextAction]').closest('form');form.querySelector('[name=nextAction]').value='Request transcript';form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.textContent.includes('Next action: Request transcript'));
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.querySelector('[name=body]')).catch(async e=>{throw new Error(e.message+' '+await page.evaluate(()=>document.querySelector('crm-lead-work').shadowRoot.textContent))});
  const plan=calls.find(c=>c.path==='/api/leads/l_client'&&c.method==='PUT');assert.equal(plan.headers['if-match'],'lead-version');assert.equal(JSON.parse(plan.body).referrer,'Flor');
  await page.evaluate(()=>{const root=document.querySelector('crm-lead-work').shadowRoot;root.querySelector('[name=body]').value='Called client about documents';root.querySelector('[name=followUp]').checked=true;root.querySelector('[name=body]').closest('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.querySelector('[name=body]')?.value==='');
  const log=calls.find(c=>c.path.endsWith('/timeline')&&c.method==='POST');assert.equal(JSON.parse(log.body).followUp,true);assert.equal(log.headers['if-match'],'lead-version');
  await page.evaluate(()=>[...document.querySelector('crm-lead-work').shadowRoot.querySelectorAll('button')].find(b=>b.textContent==='Next activities').click());
  await page.waitForFunction(()=>document.querySelector('crm-lead-work')?.shadowRoot.textContent.includes('Previous activities'));
  assert.ok(calls.some(c=>c.path.endsWith('/timeline')&&c.query.includes('offset=25')));assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('bulk requests keep reviewed revisions when records refresh behind a confirmation',async()=>{
 const {page,calls,contact}=await fixture('workspace');try{
  await page.evaluate(async()=>{await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});document.body.append(Object.assign(document.createElement('div'),{className:'modal-panel'}));await new Promise(resolve=>setTimeout(resolve,0))});
  contact._revision='new-version';
  await page.evaluate(async()=>{await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('GET','/api/contacts/c_client');xhr.onload=resolve;xhr.send()});await new Promise(resolve=>{const xhr=new XMLHttpRequest();xhr.open('POST','/api/contacts/bulk');xhr.setRequestHeader('Content-Type','application/json');xhr.onload=resolve;xhr.send(JSON.stringify({ids:['c_client','unreviewed'],stage:'Client'}))})});
  const request=calls.find(c=>c.path==='/api/contacts/bulk');assert.deepEqual(JSON.parse(request.body).revisions,{c_client:'old-version',unreviewed:''});
 }finally{await page.close()}
});


test('application requirements keep missing files visible and collapse completed files and assignment controls',async()=>{
 const {page,errors}=await fixture('workspace');try{
  await page.evaluate(()=>{const essentials=document.createElement('section');essentials.className='application-essentials';const panel=document.createElement('crm-application-blockers');panel.setAttribute('record-id','case_client');essentials.append(panel);document.body.append(essentials)});
  await page.waitForSelector('crm-application-blockers >>> .requirement-item');
  const state=await page.$eval('crm-application-blockers',host=>{const root=host.shadowRoot;return {missing:root.querySelector('.requirement-item').textContent,completedOpen:root.querySelector('.completed-requirement').open,assignmentOpen:root.querySelector('.requirement-item details').open,duplicateOwner:root.textContent.includes('Owner: Adviser')}});
  assert.ok(state.missing.includes('Passport')&&state.missing.includes('Missing required file'));
  assert.equal(state.completedOpen,false);assert.equal(state.assignmentOpen,false);assert.equal(state.duplicateOwner,false);
  await page.click('crm-application-blockers >>> .requirement-item details > summary');
  assert.equal(await page.$eval('crm-application-blockers >>> .requirement-item details',e=>e.open),true);
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('live application essentials group daily actions and reveal linked handoffs on mobile',{skip:process.env.ECC_BROWSER_LIVE!=='true'},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-crm-essentials-')),port='17003';
 const server=spawn(path.join(__dirname,'../build/ecc-crm'),[],{cwd:path.join(__dirname,'..'),env:{...process.env,SEED_DEMO_DATA:'true',PORT:port,DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'essentials-test-secret-only',ALLOW_SIGNUP:'false'},stdio:'pipe'});
 const page=await browser.newPage();
 try{
  for(let i=0;i<100;i++){try{if((await fetch('http://localhost:'+port+'/api/health')).ok)break}catch{}await new Promise(resolve=>setTimeout(resolve,100))}
  await page.goto('http://localhost:'+port,{waitUntil:'networkidle2'});
  await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');await page.waitForSelector('.app-shell');
  const id=await page.evaluate(async()=>{const out=await(await fetch('/api/cases')).json();return out.cases[0].id});
  for(const width of [1280,390]){
   await page.setViewport({width,height:900});
   await page.goto('http://localhost:'+port+'/cases/'+id,{waitUntil:'networkidle2'});
   await page.waitForSelector('.application-essentials');
   await page.waitForFunction(()=>document.querySelector('.application-essentials crm-work-plan')?.shadowRoot.querySelector('textarea'));
   assert.equal(await page.$eval('crm-record-tools',e=>e.shadowRoot.querySelectorAll('crm-work-plan').length),0);
   const essentials=await page.$eval('.application-essentials',e=>e.textContent);
   assert.ok(essentials.includes('Application essentials')&&essentials.includes('Stage:'));
   assert.equal(await page.$eval('#handoff',e=>e.open),false);
   assert.equal(await page.$eval('.application-controls:last-of-type',e=>e.open),false);
   await page.goto('http://localhost:'+port+'/cases/'+id+'#handoff',{waitUntil:'networkidle2'});
   await page.waitForFunction(()=>document.getElementById('handoff')?.open);
   await page.$eval('.application-essentials button',e=>e.click());await page.waitForSelector('#cf-nextAction');
   assert.equal(await page.$eval('#cf-assignedOfficer',e=>e.getAttribute('entity')),'cases');
  }
 }finally{await page.close();server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve));fs.rmSync(directory,{recursive:true,force:true})}
});


test('manager exceptions and operational attention retain direct review links',async()=>{
 const {page,errors}=await fixture('workspace');try{
  await page.evaluate(()=>{const queue=document.createElement('crm-priority-queues');queue.setAttribute('queue','unassigned');queue.setAttribute('exceptions-only','true');document.body.append(queue,document.createElement('crm-operational-attention'))});
  await page.waitForSelector('crm-priority-queues >>> .card a');
  assert.equal(await page.$eval('crm-priority-queues',host=>[...host.shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent.startsWith('Unassigned')).hidden),false);
  assert.equal(await page.$eval('crm-priority-queues',host=>[...host.shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent.startsWith('Document issues')).hidden),true);
  await page.waitForFunction(()=>document.querySelector('crm-operational-attention').shadowRoot.textContent.includes('Uncertain test message'));
  assert.equal(await page.$eval('crm-operational-attention',host=>[...host.shadowRoot.querySelectorAll('a')].find(a=>a.textContent==='Review linked message').getAttribute('href')),'/contacts/c_client#record-tools?tab=conversations');
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('service templates preview requirements and action defaults before applying',async()=>{
 const templates=[{id:'study-template',data:JSON.stringify({name:'Study starter',service:'Study',documents:'Passport\nCV',stages:'Assessment\nDocuments Pending',nextAction:'Review CV',deadlineDays:7})}];
 const {page,errors}=await fixture('workspace',{templates});try{
  await page.evaluate(()=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('nav button')].find(b=>b.textContent==='Workflows').click());
  await page.waitForSelector('crm-workspace >>> select[name=templateId]');
  await page.select('crm-workspace >>> select[name=templateId]','study-template');
  await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.textContent.includes('Requirements: Passport, CV'));
  assert.ok(await page.$eval('crm-workspace',host=>host.shadowRoot.textContent.includes('Starting action: Review CV')&&host.shadowRoot.textContent.includes('7 days after applying')));
  assert.equal(await page.$eval('crm-workspace >>> [name=applyTemplatePlan]',e=>e.checked),false);
  assert.deepEqual(errors,[]);
 }finally{await page.close()}
});

test('live dashboard filters, closed stage transitions and mobile stay consistent',{skip:process.env.ECC_BROWSER_LIVE!=='true',timeout:120000},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-dashboard-regression-')),port='17009',base='http://localhost:'+port;
 const server=spawn(path.join(__dirname,'../build/ecc-crm'),[],{cwd:path.join(__dirname,'..'),env:{...process.env,SEED_DEMO_DATA:'true',PORT:port,DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'dashboard-regression-only',APP_URL:base,ALLOW_SIGNUP:'false',SMTP_HOST:'',STRIPE_SECRET_KEY:'',OPENAI_API_KEY:''},stdio:'pipe'});
 const page=await browser.newPage(),errors=[];page.on('pageerror',error=>errors.push(error.message));
 await page.setRequestInterception(true);page.on('request',r=>new URL(r.url()).origin===base?r.continue():r.abort());
 const api=(method,url,body,etag)=>page.evaluate(async({method,url,body,etag})=>{const r=await fetch(url,{method,headers:{'Content-Type':'application/json',...(etag?{'If-Match':etag}:{})},body:body===undefined?undefined:JSON.stringify(body)});return{status:r.status,etag:r.headers.get('etag'),data:await r.json()}},{method,url,body,etag});
 try{
  for(let i=0;i<100;i++){try{if((await fetch(base+'/api/health')).ok)break}catch{}await new Promise(r=>setTimeout(r,100))}
  await page.goto(base,{waitUntil:'networkidle2'});
  await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');
  await page.waitForSelector('.app-shell');
  const overview=await api('GET','/api/dashboard/overview?scope=all');
  const expectedLeads={};
  for(const [label,offset] of [['overdue',-2],['today',0],['upcoming',30]]){
   const day=new Date(overview.data.today+'T12:00:00Z');day.setUTCDate(day.getUTCDate()+offset);
   const created=await api('POST','/api/leads',{name:'Regression '+label,source:'Other',status:'New',followUpDate:day.toISOString().slice(0,10),nextAction:'Regression follow-up'});
   assert.equal(created.status,201,JSON.stringify(created.data));expectedLeads[label]=created.data.lead.id;
  }
  const team=await api('POST','/api/admin/teams',{name:'Regression empty branch'});assert.equal(team.status,201);
  await page.evaluate(()=>window.dispatchEvent(new Event('crm:record-changed')));
  await page.waitForFunction(id=>document.querySelector('.dashboard-overview')?.querySelector('[name=team] option[value="'+id+'"]'),{},team.data.id);
  const cases=await api('GET','/api/cases?limit=100');const id=cases.data.cases[0].id;
  const record=await api('GET','/api/cases/'+id+'/gates');
  const moved=await api('POST','/api/cases/'+id+'/transition',{stage:'Closed',override:true,reason:'Browser regression test'},record.data.revision);assert.equal(moved.status,200,JSON.stringify(moved.data));
  await page.evaluate(()=>window.dispatchEvent(new Event('crm:record-changed')));
  for(const width of [1280,390]){
   await page.setViewport({width,height:900});
   await page.waitForFunction(()=>document.querySelector('.dashboard-overview')?.querySelector('.kpi'));
   await page.select('.dashboard-overview [name=scope]','all');
   await page.waitForFunction(()=>!document.querySelector('.dashboard-overview').querySelector('button').disabled);
   for(const category of ['applications','leads','followups','followupsToday','followupsUpcoming','invoicesOverdue']){
    const response=page.waitForResponse(r=>{const u=new URL(r.url());return u.pathname==='/api/my-work'&&u.searchParams.get('category')===category&&u.searchParams.get('dashboard')==='1'});
    await page.evaluate(category=>document.querySelector('.dashboard-overview').querySelector('.kpi[data-category="'+category+'"]').click(),category);
    const r=await response;assert.equal(r.status(),200);const out=await r.json();assert.equal(out.category,category);assert.equal(new URL(r.url()).searchParams.get('scope'),'all');
    if(category==='followups') {assert.ok(out.items.some(i=>i.id===expectedLeads.today));assert.ok(out.items.some(i=>i.id===expectedLeads.overdue));assert.ok(!out.items.some(i=>i.id===expectedLeads.upcoming));}
    if(category==='followupsToday') {assert.ok(out.items.some(i=>i.id===expectedLeads.today));assert.ok(!out.items.some(i=>i.id===expectedLeads.upcoming||i.id===expectedLeads.overdue));}
    if(category==='followupsUpcoming') {assert.ok(out.items.some(i=>i.id===expectedLeads.upcoming));assert.ok(!out.items.some(i=>i.id===expectedLeads.today||i.id===expectedLeads.overdue));}

   }
   const closedResponse=page.waitForResponse(r=>{const u=new URL(r.url());return u.pathname==='/api/my-work'&&u.searchParams.get('stage')==='Closed'});
   await page.evaluate(()=>[...document.querySelector('.dashboard-overview').querySelectorAll('.stage-list button')].find(b=>b.getAttribute('aria-label')?.startsWith('Closed:')).click());
   assert.ok((await (await closedResponse).json()).items.some(item=>item.id===id));
   const taskResponse=page.waitForResponse(r=>new URL(r.url()).searchParams.get('category')==='tasks');
   await page.evaluate(()=>document.querySelector('.daily-work').querySelector('[data-category=tasks]').click());
   const tasks=await taskResponse;assert.equal(tasks.status(),200);assert.equal(new URL(tasks.url()).searchParams.get('stage'),null);
   await page.select('.dashboard-overview [name=team]',team.data.id);
   await page.waitForFunction(()=>!document.querySelector('.dashboard-overview').querySelector('button').disabled);
   const branchResponse=page.waitForResponse(r=>{const u=new URL(r.url());return u.pathname==='/api/my-work'&&u.searchParams.get('category')==='applications'&&u.searchParams.get('team')===team.data.id});
   await page.evaluate(()=>document.querySelector('.dashboard-overview').querySelector('.kpi[data-category=applications]').click());
   const branch=await branchResponse;assert.equal(branch.status(),200);assert.equal((await branch.json()).total,0);
   await page.waitForFunction(()=>document.querySelector('.daily-work').querySelector('[data-work-branch]').textContent==='Branch: Regression empty branch');
   const clearedResponse=page.waitForResponse(r=>{const u=new URL(r.url());return u.pathname==='/api/my-work'&&u.searchParams.get('category')==='applications'&&!u.searchParams.has('team')});
   await page.click('.daily-work [data-clear-work-branch]');
   assert.equal((await clearedResponse).status(),200);
   await page.waitForFunction(()=>document.querySelector('.daily-work').querySelector('[data-work-branch]').textContent==='Branch: All accessible branches');

   assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),'page must fit mobile and desktop');
   await page.select('.dashboard-overview [name=team]','');
   await page.waitForFunction(()=>!document.querySelector('.dashboard-overview').querySelector('button').disabled);
  }
  assert.deepEqual(errors,[]);
 }finally{await page.close();server.kill('SIGTERM');await new Promise(resolve=>server.exitCode!==null?resolve():server.once('exit',resolve));fs.rmSync(directory,{recursive:true,force:true})}
});
