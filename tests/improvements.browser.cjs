const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {spawn}=require('node:child_process');
const puppeteer=require('puppeteer');
const root=path.join(__dirname,'..');

test('daily work, searchable relationships, draft recovery and staff retests on desktop and phone', {timeout:180000}, async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-improvements-'));
 const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
 const base='http://127.0.0.1:'+port;
 const server=spawn(path.join(root,'build/ecc-crm'),[],{cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',PORT:String(port),DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'improvements-fixture-secret',APP_URL:base,ALLOW_SIGNUP:'false',SMTP_HOST:'',OPENAI_API_KEY:'',STRIPE_SECRET_KEY:'',WHATSAPP_ORG_ID:'',GRAPH_ORG_ID:''},stdio:'pipe'});
 let log='',browser;server.stderr.on('data',data=>log+=data);const errors=[];
 try{
  for(let i=0;i<100;i++){try{if((await fetch(base+'/api/health')).ok)break}catch{}if(i===99)throw new Error(log);await new Promise(resolve=>setTimeout(resolve,100))}
  const local=path.join(os.homedir(),'.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');
  browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||(fs.existsSync(local)?local:await puppeteer.executablePath()),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  const page=await browser.newPage();page.setDefaultTimeout(20000);page.on('pageerror',error=>errors.push(error.message));await page.setViewport({width:1280,height:900});
  await page.goto(base);await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');await page.waitForSelector('.app-shell');
  const api=async(url,method='GET',body,revision)=>page.evaluate(async(url,method,body,revision)=>{const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...(revision?{'If-Match':revision}:{})},body:body===undefined?undefined:JSON.stringify(body)});const data=await response.json();if(!response.ok)throw new Error(JSON.stringify(data));return data},url,method,body,revision);
  const toolForm=(title)=>page.evaluateHandle(title=>[...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('.card')].find(card=>card.querySelector('h2')?.textContent===title)?.querySelector('form'),title);
  const choose=async(form,name,query,id)=>{
   await form.evaluate((form,{name,query})=>{const picker=form.querySelector('[name="'+name+'"]'),search=picker.shadowRoot.querySelector('input[type=search]');search.value=query;search.dispatchEvent(new Event('input',{bubbles:true}))},{name,query});
   await page.waitForFunction((form,name,id)=>[...form.querySelector('[name="'+name+'"]').shadowRoot.querySelectorAll('.results button')].some(button=>button.textContent.includes(id)),{},form,name,id);
   await form.evaluate((form,{name,id})=>[...form.querySelector('[name="'+name+'"]').shadowRoot.querySelectorAll('.results button')].find(button=>button.textContent.includes(id)).click(),{name,id});
  };
  await page.waitForFunction(()=>document.querySelector('.daily-work')?.textContent.includes('work items'));
  await page.waitForFunction(()=>[...document.querySelectorAll('.home-secondary > summary')].filter(summary=>!summary.textContent.includes('Recent workspace')).every(summary=>!summary.textContent.includes('Loading')&&summary.textContent.includes(' · ')));
  assert.ok(await page.$eval('.home-secondary',section=>!section.open));
  const totals=await api('/api/work-outcomes');
  assert.ok(await page.$eval('crm-work-outcomes',host=>host.closest('details').querySelector('summary').textContent).then(text=>text.includes(totals.unansweredMessages+' unanswered messages')));
  // Expose a real failure, then retry without treating it as zero issues.
  await page.setRequestInterception(true);let failOutcomes=true,failSave=true;
  page.on('request',request=>{const pathname=new URL(request.url()).pathname;if(pathname==='/api/work-outcomes'&&failOutcomes){failOutcomes=false;request.abort()}else if(pathname==='/api/workflows/case'&&request.method()==='POST'&&failSave){failSave=false;request.abort()}else request.continue()});
  await page.evaluate(()=>document.querySelector('crm-work-outcomes').querySelector('button').click());
  await page.waitForFunction(()=>document.querySelector('crm-work-outcomes').closest('details').querySelector('summary').textContent.includes('Unavailable'));
  await page.evaluate(()=>document.querySelector('crm-work-outcomes').querySelector('button').click());await page.waitForFunction(()=>document.querySelector('crm-work-outcomes').closest('details').querySelector('summary').textContent.includes('unanswered messages'));
  const client=(await api('/api/contacts')).contacts[0];const application=(await api('/api/cases')).cases[0];
  const partnerType=(await api('/api/partners')).partners[0].type;let partner,parent;
  for(let i=0;i<26;i++){
   partner=(await api('/api/partners','POST',{legalCompanyName:'Improvement partner '+String(i).padStart(2,'0'),type:partnerType,country:'PH'})).partner;
   parent=(await api('/api/cases','POST',{caseNumber:'IMPROVE-'+String(i).padStart(2,'0'),clientId:client.id,serviceCategory:'Student Visa',currentStage:'Assessment',priority:application.priority,dateOpened:'2026-10-12'})).case;
  }
  await page.goto(base+'/workspace?tab=workflows');await page.waitForSelector('crm-workspace >>> crm-record-picker[name=partnerId]');
  let form=await toolForm('Application checklist & deadlines');await choose(form,'id',application.caseNumber,application.id);await choose(form,'partnerId','Improvement partner 25',partner.id);await choose(form,'parentCaseId',parent.caseNumber,parent.id);
  await form.evaluate(form=>{form.querySelector('[name=slaDays]').value='5';form.querySelector('[name=slaDays]').dispatchEvent(new Event('input',{bubbles:true}));form.requestSubmit()});
  await page.waitForFunction(form=>form.textContent.includes('Your entries are kept'),{},form);
  assert.equal(await form.evaluate(form=>form.querySelector('[name=partnerId]').value),partner.id);
  await page.evaluate(()=>window.dispatchEvent(new CustomEvent('crm:record-changed')));
  await page.evaluate(()=>document.querySelector('crm-workspace').shadowRoot.querySelector('#refresh').click());
  assert.equal(await form.evaluate(form=>form.querySelector('[name=slaDays]').value),'5');
  // A concurrent edit must be reviewed before rebasing the form revision.
  const current=(await api('/api/records/cases/'+application.id)).record;
  await api('/api/cases/'+application.id,'PUT',{...current,nextAction:'Concurrent saved action'},current._revision);
  await form.evaluate(form=>[...form.querySelectorAll('button')].find(button=>button.textContent==='Retry save').click());
  await page.waitForFunction(form=>!([...form.querySelectorAll('button')].find(button=>button.textContent==='Review current saved record').hidden),{},form);
  await form.evaluate(form=>[...form.querySelectorAll('button')].find(button=>button.textContent==='Review current saved record').click());
  await page.waitForFunction(form=>form.textContent.includes('Concurrent saved action'),{},form);
  await form.evaluate(form=>{const check=form.querySelector('input[type=checkbox]:not([name])');check.checked=true;check.dispatchEvent(new Event('change'));[...form.querySelectorAll('button')].find(button=>button.textContent==='Use reviewed version for retry').click();[...form.querySelectorAll('button')].find(button=>button.textContent==='Retry save').click()});
  await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelector('#notice').textContent.includes('Saved'));
  const saved=(await api('/api/records/cases/'+application.id)).record;assert.equal(saved.partnerId,partner.id);assert.equal(saved.parentCaseId,parent.id);assert.equal(saved.nextAction,'Concurrent saved action');
  form=await toolForm('Application checklist & deadlines');await choose(form,'id',application.caseNumber,application.id);assert.equal(await form.evaluate(form=>form.querySelector('[name=partnerId]').value),partner.id);
  // Search and choose using the keyboard; retain a selection when searches fail.
  const picker=await form.$('[name=parentCaseId]');
  // Nested shadow selectors are exercised through the picker host itself.
  await picker.evaluate(picker=>{const input=picker.shadowRoot.querySelector('input[type=search]');input.value='IMPROVE-25';input.dispatchEvent(new Event('input',{bubbles:true}));input.focus()});
  await page.waitForFunction(picker=>picker.shadowRoot.querySelector('.results button'),{},picker);await page.keyboard.press('ArrowDown');await page.keyboard.press('Enter');assert.equal(await picker.evaluate(picker=>picker.value),parent.id);
  await page.goto(base+'/cases/'+application.id);await page.waitForSelector('.application-essentials');await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.querySelector('#title')?.textContent==='Overview');assert.ok(await page.$eval('crm-record-tools',host=>!host.shadowRoot.textContent.includes('Could not load workspace tools')&&!host.shadowRoot.querySelector('#notice').textContent));assert.ok(await page.$eval('.application-essentials',section=>section.textContent.includes('Stage:')));await page.waitForFunction(()=>document.querySelector('crm-application-blockers').shadowRoot.textContent.includes('document'));
  await page.setViewport({width:390,height:844});await page.screenshot({path:path.join(directory,'application-phone.png'),fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));fs.mkdirSync(path.join(root,'tests/artifacts'),{recursive:true});await page.screenshot({path:path.join(root,'tests/artifacts/improvements-application-phone.png'),fullPage:true});
  await page.goto(base+'/workspace?tab=usability');await page.waitForSelector('crm-workspace >>> crm-usability >>> form');
  const usability=await page.$('crm-workspace >>> crm-usability');
  await usability.evaluate(host=>{const form=host.shadowRoot.querySelector('form');form.elements.session.value='Finance A';form.elements.device.value='Phone / Chromium';form.elements.role.value='finance';form.elements.role.dispatchEvent(new Event('change'));form.elements.task.value='invoice-receipt';form.elements.phase.value='retest';form.elements.phase.dispatchEvent(new Event('change'));form.elements.issueReference.value='OBS-fixture';form.elements.comments.value='Automated browser fixture only; actual staff session remains pending.';form.elements.seconds.value='12';[...form.querySelectorAll('button')].find(button=>button.textContent==='Start task timer').click();[...form.querySelectorAll('button')].find(button=>button.textContent==='Stop task timer').click();form.requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelector('crm-usability').shadowRoot.textContent.includes('Observation saved'));
  const observations=(await api('/api/usability/feedback')).observations;const observation=JSON.parse(observations[0].data);assert.equal(observation.phase,'retest');assert.equal(observation.issueReference,'OBS-fixture');assert.equal(observation.device,'Phone / Chromium');
  // Browser timings are local evidence, separate from backend benchmark means.
  await page.goto(base,{waitUntil:'domcontentloaded'});await page.waitForFunction(()=>document.querySelector('.daily-work')?.textContent.includes('work items'));
  const timing=await page.evaluate(()=>({navigationToUsableWorkMs:performance.now(),resources:performance.getEntriesByType('resource').filter(entry=>entry.name.includes('/api/my-work')).map(entry=>({duration:entry.duration,transferSize:entry.transferSize,limit:new URL(entry.name).searchParams.get('limit')}))}));
  fs.mkdirSync(path.join(root,'tests/artifacts'),{recursive:true});fs.writeFileSync(path.join(root,'tests/artifacts/improvements-timing.json'),JSON.stringify(timing,null,2));await page.screenshot({path:path.join(root,'tests/artifacts/improvements-home-phone.png'),fullPage:true});
  assert.equal(timing.resources[0].limit,'10');console.log('Local browser timing:',JSON.stringify(timing));assert.deepEqual(errors,[]);
 }finally{await browser?.close();if(server.exitCode===null){server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve))}fs.rmSync(directory,{recursive:true,force:true})}
});
