const {test} = require('node:test');
const assert=require('node:assert/strict');
const {parseHTML}=require('linkedom');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');

const overview={
 today:'2026-10-13',generatedAt:'2026-10-13T09:00:00Z',scope:'mine',teamId:'',teamName:'',teamSelectable:true,
 kpi:[
  {key:'activeCases',label:'Active applications',value:4,hint:'Not approved, refused or closed',category:'applications'},
  {key:'openLeads',label:'Open leads',value:2,hint:'1 still in qualification',category:'leads'},
  {key:'followUpsDue',label:'Follow-ups due',value:3,hint:'1 overdue',category:'followups',severity:'attention'},
  {key:'invoicesOverdue',label:'Payments overdue',value:1,hint:'2 outstanding invoices in total',category:'invoicesOverdue',severity:'attention'},
  {key:'readyForSubmission',label:'Ready for submission',value:1,hint:'Awaiting submission or a decision',category:'caseStages',stage:'Ready for Submission'},
 ],
 caseStages:[{stage:'Documents Pending',count:3,active:true},{stage:'Ready for Submission',count:1,active:true},{stage:'Closed',count:2,active:false}],
 documentCompleteness:{applications:4,complete:1,incomplete:3,noRequirements:0,requiredDocuments:9,verifiedDocuments:3,expiredDocuments:1,outstandingFiles:6,completePercent:25},
 paymentsDue:{overdue:[{currency:'PHP',amount:1500,count:1}],dueSoon:[{currency:'USD',amount:200,count:1}],later:[],noDueDate:[],overdueCount:1,dueSoonCount:1,openCount:2,pendingApprovals:0},
 teams:[{id:'team_default',name:'General',members:3,activeCases:4,openLeads:2,followUpsDue:3,documentsIncomplete:3,invoicesOverdue:1,selected:true},{id:'team_north',name:'North branch',members:2,activeCases:1,openLeads:0,followUpsDue:1,documentsIncomplete:0,invoicesOverdue:0,selected:false}],
};

const work={items:[{id:'case_ready',entity:'case',name:'ECC-READY',reason:'Stage: Ready for Submission',action:'Submit the file',details:['Required documents verified: 1 of 2','Needs verification: Passport'],priority:'medium',route:'/cases/case_ready'}],total:1,counts:{},today:'2026-10-13',category:'',scope:'mine'};

// linkedom's ShadowRoot does not implement textContent, so assertions read the
// serialized shadow root instead.
const text=element=>element.shadowRoot.innerHTML;

async function mount(options={}){
 const {window}=parseHTML('<html><body><div id="app"></div></body></html>');
 const document=window.document,calls=[];
 Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){const selected=this.querySelector('option[selected]')||this.querySelector('option');return selected?.getAttribute('value')||''},set(value){for(const o of this.querySelectorAll('option')){if(o.getAttribute('value')===String(value))o.setAttribute('selected','');else o.removeAttribute('selected')}}});
 window.HTMLElement.prototype.scrollIntoView=()=>{};
 const sandbox={window,document,history:{replaceState(){}},location:{href:'http://crm.test/',origin:'http://crm.test',pathname:'/',search:''},localStorage:{getItem:()=>null},URLSearchParams,URL,Intl,console,CustomEvent:window.CustomEvent,Event:window.Event,MutationObserver:window.MutationObserver,HTMLElement:window.HTMLElement,customElements:window.customElements,navigator:{},setTimeout,clearTimeout};
 sandbox.fetch=async(url,opts={})=>{
  calls.push({url,opts});
  if(url.startsWith('/api/dashboard/overview')){
   if(options.failDashboard)return{status:500,ok:false,json:async()=>({error:'Database unavailable; try Refresh again'})};
   const params=new URL(url,'http://crm.test').searchParams;
   const team=params.get('team');
   const data=JSON.parse(JSON.stringify(overview));
   data.teamId=team||'';data.teamName=team?'North branch':'';data.scope=params.get('scope')||'mine';
   data.teams.forEach(t=>{t.selected=t.id===(team||'team_default')});
   if(options.teamSelectable===false){data.teamSelectable=false;data.teams=data.teams.slice(0,1);data.teamName='General'}
   return{status:200,ok:true,json:async()=>data};
  }
  if(url.startsWith('/api/my-work')){const params=new URL(url,'http://crm.test').searchParams;return{status:200,ok:true,json:async()=>Object.assign({},work,options.emptyWork?{items:[],total:0}:{},{scope:params.get('scope')||'mine',category:params.get('category')||'',teamId:params.get('team')||'',teamName:params.get('team')?'North branch':''})}};
  return{status:200,ok:true,json:async()=>({status:'ok'})};
 };
 window.HTMLElement.prototype.focus=()=>{};
 Object.defineProperty(window.HTMLElement.prototype,'onclick',{configurable:true,get(){return ()=>this.dispatchEvent(new window.Event('click',{bubbles:true}))}});
 Object.defineProperty(window.HTMLElement.prototype,'onchange',{configurable:true,get(){return ()=>this.dispatchEvent(new window.Event('input',{bubbles:true}))}});
 window.innerWidth=1280;window.innerHeight=900;window.pageXOffset=0;window.pageYOffset=0;
 sandbox.XMLHttpRequest=class {
  constructor(){this.listeners={};this.upload={addEventListener(){}};this.status=0;this.response='';}
  addEventListener(name,callback){this.listeners[name]=callback;}
  open(method,url){this.method=method;this.url=url;}
  setRequestHeader(){}
  getAllResponseHeaders(){return 'content-type: application/json';}
  abort(){this.aborted=true;}
  async send(){try{const response=await sandbox.fetch(this.url,{method:this.method});if(this.aborted)return;this.status=response.status;this.statusText=response.ok?'OK':'Error';this.responseURL=new URL(this.url,'http://crm.test').href;this.response=JSON.stringify(await response.json());this.listeners.load?.();}catch{this.listeners.error?.();}}
 };
 const context=vm.createContext(sandbox);
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../public/work-dashboard-elm.js'),'utf8'),context,{filename:'work-dashboard-elm.js'});
 context.Elm.WorkDashboard.init({node:document.getElementById('app'),flags:{userId:'unit-owner'}});
 await new Promise(resolve=>setTimeout(resolve,100));
 const dashboard={shadowRoot:document.querySelector('.dashboard-overview')};
 const myWork={shadowRoot:document.querySelector('.daily-work')};
 const revealCategory=async(category,stage='',filters={})=>{
  const scope=dashboard.shadowRoot.querySelector('[name=scope]');scope.value=filters.scope||'mine';scope.onchange();await new Promise(r=>setTimeout(r,40));
  const team=dashboard.shadowRoot.querySelector('[name=team]');team.value=filters.team||'';team.onchange();await new Promise(r=>setTimeout(r,40));
  if(category==='caseStages'){
   const button=[...dashboard.shadowRoot.querySelectorAll('.stage-list button')].find(button=>button.getAttribute('aria-label')?.startsWith(stage+':'));button.onclick();
  }else dashboard.shadowRoot.querySelector('.kpi[data-category="'+category+'"]').onclick();
 };
 myWork.revealCategory=revealCategory;
 return{window,document,dashboard,myWork,calls,cleanup(){document.body.replaceChildren()}};
}

test('dashboard overview renders real figures from the server response',async()=>{
 const app=await mount();try{
  const root=app.dashboard.shadowRoot;
  assert.ok(app.calls.some(c=>c.url==='/api/dashboard/overview?scope=mine'));
  const kpis=[...root.querySelectorAll('.kpi')];
  assert.equal(kpis.length,5);
  assert.ok(kpis.some(card=>card.textContent.includes('Active applications')&&card.textContent.includes('4')));
  assert.ok(kpis.some(card=>card.textContent.includes('Payments overdue')&&card.textContent.includes('1')));
  assert.equal(root.querySelectorAll('.kpi[aria-label]').length,5);
  // Cards that need staff attention are marked without hiding the rest.
  assert.ok(root.querySelectorAll('.kpi--attention').length>=2);
  // Stage summary keeps the server's pipeline order and real counts.
  const stages=[...root.querySelectorAll('.stage-list>li>button')].map(b=>b.textContent);
  assert.ok(stages[0].includes('Documents Pending')&&stages[0].includes('3'),stages.join('|'));
  assert.ok(root.querySelector('.completeness').getAttribute('aria-label').includes('25%'));
  assert.ok(text(app.dashboard).includes('9 required documents recorded'));
  // Payments are reported per currency and never summed.
  assert.ok(text(app.dashboard).includes('PHP'));
  assert.ok(text(app.dashboard).includes('North branch'));
  assert.ok(root.querySelectorAll('.dashboard-table').length>0);
 }finally{app.cleanup()}
});

test('dashboard KPI cards open the matching filtered records',async()=>{
 const app=await mount();try{
  const stageCard=[...app.dashboard.shadowRoot.querySelectorAll('.kpi')].find(card=>card.dataset.stage==='Ready for Submission');
  stageCard.onclick();
  await new Promise(resolve=>setTimeout(resolve,40));
  const request=app.calls.filter(c=>c.url.startsWith('/api/my-work')).pop();
  assert.ok(request.url.includes('category=caseStages'),request.url);
  assert.ok(new URL(request.url,'http://crm.test').searchParams.get('stage')==='Ready for Submission',request.url);
  assert.ok(text(app.myWork).includes('Applications by stage · Ready for Submission'));
  assert.ok(text(app.myWork).includes('ECC-READY'));

  const overdue=[...app.dashboard.shadowRoot.querySelectorAll('.kpi')].find(card=>card.dataset.category==='invoicesOverdue');
  overdue.onclick();
  await new Promise(resolve=>setTimeout(resolve,40));
  const next=app.calls.filter(c=>c.url.startsWith('/api/my-work')).pop();
  assert.ok(next.url.includes('category=invoicesOverdue'),next.url);
  assert.ok(!next.url.includes('stage='),'choosing another figure must clear the stage filter');
  assert.ok(text(app.myWork).includes('Payments overdue'));
 }finally{app.cleanup()}
});

test('branch overview offers a selector to managers and narrows the request',async()=>{
 const app=await mount();try{
  const select=app.dashboard.shadowRoot.querySelector('[name=team]');
  assert.ok(select,'managers must be offered a branch selector');
  select.value='team_north';
  select.onchange();
  await new Promise(resolve=>setTimeout(resolve,40));
  assert.ok(app.calls.some(c=>c.url.includes('team=team_north')));
  const row=[...app.dashboard.shadowRoot.querySelectorAll('.dashboard-table tbody tr')].find(r=>r.textContent.includes('North branch'));
  assert.equal(row.getAttribute('aria-current'),'true');
  assert.ok(row.textContent.includes('Viewing'));
 }finally{app.cleanup()}
});

test('members are not offered a branch switcher',async()=>{
 const app=await mount({teamSelectable:false});try{
  const root=app.dashboard.shadowRoot;
  assert.equal(root.querySelector('[name=team]'),null,'a member must not be offered other branches');
  assert.ok(text(app.dashboard).includes('Branch: General'));
  assert.ok(text(app.dashboard).includes('My branch'));
  assert.ok(!text(app.dashboard).includes('Viewing'));
 }finally{app.cleanup()}
});

test('dashboard overview reports a retryable failure instead of an empty dashboard',async()=>{
 const app=await mount({failDashboard:true});try{
  const root=app.dashboard.shadowRoot;
  assert.ok(text(app.dashboard).includes('Database unavailable'));
  assert.ok(text(app.dashboard).includes('Refresh overview to retry'));
  assert.equal(root.querySelectorAll('.kpi').length,0);
  assert.ok(root.querySelector('[role=status]').textContent.includes('Unavailable'));
  // A failed load must not be presented as zero issues.
  assert.ok(!text(app.dashboard).includes('Active applications'));
 }finally{app.cleanup()}
});
test('every dashboard category opens once and preserves assignment and branch filters',async()=>{
 const app=await mount();try{
  const scope=app.dashboard.shadowRoot.querySelector('[name=scope]');
  scope.value='all';scope.onchange();
  await new Promise(resolve=>setTimeout(resolve,40));
  const team=app.dashboard.shadowRoot.querySelector('[name=team]');
  team.value='team_north';team.onchange();
  await new Promise(resolve=>setTimeout(resolve,40));
  for(const category of ['applications','leads','followups','invoicesOverdue','caseStages']){
   const card=app.dashboard.shadowRoot.querySelector('.kpi[data-category="'+category+'"]');
   const before=app.calls.filter(c=>c.url.startsWith('/api/my-work')).length;
   card.onclick();
   await new Promise(resolve=>setTimeout(resolve,40));
   const calls=app.calls.filter(c=>c.url.startsWith('/api/my-work'));
   assert.equal(calls.length,before+1,'one request per click');
   const params=new URL(calls.at(-1).url,'http://crm.test').searchParams;
   assert.equal(params.get('category'),category);
   assert.equal(params.get('scope'),'all');
   assert.equal(params.get('team'),'team_north');
   assert.equal(params.get('dashboard'),'1');
  }
  app.myWork.shadowRoot.querySelector('[data-category=tasks]').onclick();
  await new Promise(resolve=>setTimeout(resolve,40));
  const params=new URL(app.calls.filter(c=>c.url.startsWith('/api/my-work')).at(-1).url,'http://crm.test').searchParams;
  assert.equal(params.get('category'),'tasks');
  assert.equal(params.get('stage'),null,'a regular work category clears the stage');
 }finally{app.cleanup()}
});


test('My work shows the selected branch and clears it without changing the category',async()=>{
 const app=await mount();try{
  await app.myWork.revealCategory('applications','',{scope:'all',team:'team_north',teamName:'North branch'});
  await new Promise(resolve=>setTimeout(resolve,40));
  const branch=app.myWork.shadowRoot.querySelector('[data-work-branch]');
  const clear=app.myWork.shadowRoot.querySelector('[data-clear-work-branch]');
  assert.equal(branch.textContent,'Branch: North branch');assert.equal(clear.hidden,false);
  assert.ok(!text(app.myWork).includes('full accessible dataset'));
  clear.onclick();await new Promise(resolve=>setTimeout(resolve,40));
  const params=new URL(app.calls.filter(c=>c.url.startsWith('/api/my-work')).at(-1).url,'http://crm.test').searchParams;
  assert.equal(params.get('team'),null);assert.equal(params.get('category'),'applications');
  assert.equal(branch.textContent,'Branch: All accessible branches');assert.equal(app.myWork.shadowRoot.querySelector('[data-clear-work-branch]'),null);
 }finally{app.cleanup()}
});


test('changing assignment preserves the selected stage and branch',async()=>{
 const app=await mount();try{
  await app.myWork.revealCategory('caseStages','Closed',{scope:'all',team:'team_north',teamName:'North branch'});
  await new Promise(resolve=>setTimeout(resolve,40));
  const scope=app.myWork.shadowRoot.querySelector('[name=scope]');scope.value='unassigned';scope.onchange();
  await new Promise(resolve=>setTimeout(resolve,40));
  const params=new URL(app.calls.filter(c=>c.url.startsWith('/api/my-work')).at(-1).url,'http://crm.test').searchParams;
  assert.equal(params.get('scope'),'unassigned');assert.equal(params.get('stage'),'Closed');assert.equal(params.get('team'),'team_north');
  assert.ok(text(app.myWork).includes('Applications by stage · Closed'));
 }finally{app.cleanup()}
});

test('attention filters and overview breakdowns start collapsed while work stays actionable',async()=>{
 const app=await mount();try{
  const categories=app.myWork.shadowRoot.querySelector('.work-counts').parentElement;
  assert.equal(categories.tagName,'DETAILS');
  assert.equal(categories.hasAttribute('open'),false);
  const breakdowns=[...app.dashboard.shadowRoot.querySelectorAll('.dashboard-panel')];
  assert.equal(breakdowns.length,4);
  assert.ok(breakdowns.every(panel=>panel.tagName==='DETAILS'&&!panel.hasAttribute('open')));
  assert.ok(app.myWork.shadowRoot.querySelector('.work-item a[href="/cases/case_ready"]'));
  assert.equal(app.myWork.shadowRoot.querySelector('.work-item__details').tagName,'SECTION');
  assert.ok(text(app.myWork).includes('Needs verification: Passport'));
 }finally{app.cleanup()}
});


test('empty Elm daily work offers assignment recovery and workflow links',async()=>{
 const app=await mount({emptyWork:true});try{
  const root=app.myWork.shadowRoot;
  assert.equal(root.querySelector('a[href="/leads"]').textContent,'Create your first lead');
  assert.ok(root.querySelector('a[href="/invoices"]'));
  [...root.querySelectorAll('button')].find(button=>button.textContent==='Check all accessible work').onclick();
  await new Promise(resolve=>setTimeout(resolve,40));
  assert.ok(app.calls.some(call=>call.url.startsWith('/api/my-work?')&&new URL(call.url,'http://crm.test').searchParams.get('scope')==='all'));
 }finally{app.cleanup()}
});
