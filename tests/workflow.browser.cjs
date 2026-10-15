const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {spawn}=require('node:child_process');
const puppeteer=require('puppeteer');
const root=path.join(__dirname,'..');

test('live stage policies, audited override, unified timeline, escalation rules and progressive board',{timeout:180000},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-workflow-live-'));
 const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));const base='http://localhost:'+port;
 const server=spawn(path.join(root,'build/ecc-crm'),[],{cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',PORT:String(port),DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'workflow-test-only',APP_URL:base,ALLOW_SIGNUP:'false',GRAPH_ORG_ID:'',WHATSAPP_ORG_ID:''},stdio:'pipe'});let output='';server.stderr.on('data',data=>output+=data);
 let browser;
 try{
  for(let i=0;i<100;i++){try{if((await fetch(base+'/api/health')).ok)break}catch{}await new Promise(resolve=>setTimeout(resolve,100));if(i===99)throw new Error('Server failed: '+output)}
  const local=path.join(os.homedir(),'.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||(fs.existsSync(local)?local:await puppeteer.executablePath()),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']});const page=await browser.newPage();const errors=[];page.on('pageerror',error=>errors.push(error.message));
  await page.goto(base,{waitUntil:'networkidle2'});await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');await page.waitForSelector('.app-shell');
  await page.goto(base+'/workspace?tab=gates',{waitUntil:'networkidle2'});await page.waitForSelector('crm-workspace >>> crm-gate-policies >>> details');
  await page.evaluate(()=>{const root=document.querySelector('crm-workspace').shadowRoot.querySelector('crm-gate-policies').shadowRoot;const panel=[...root.querySelectorAll('details')].find(d=>d.querySelector('summary').textContent.startsWith('Submitted'));panel.open=true;panel.querySelector('[name=enabled]').checked=true;panel.querySelector('[name=managerApproval]').checked=true;panel.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelector('crm-gate-policies').shadowRoot.textContent.includes('Submitted · enabled'));
  const application=await page.evaluate(async()=>{const out=await(await fetch('/api/cases')).json();return out.cases.find(c=>c.currentStage!=='Submitted')});assert.ok(application);
  await page.goto(base+'/cases/'+application.id,{waitUntil:'networkidle2'});await page.waitForSelector('crm-record-tools >>> crm-stage-gates >>> select');
  await page.evaluate(()=>{const gate=document.querySelector('crm-record-tools').shadowRoot.querySelector('crm-stage-gates');const select=gate.shadowRoot.querySelector('select');select.value='Submitted';select.dispatchEvent(new Event('change'));gate.shadowRoot.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('crm-stage-gates').shadowRoot.querySelector('[role=status]').textContent.includes('Stage gate'));
  await page.evaluate(()=>{const gate=document.querySelector('crm-record-tools').shadowRoot.querySelector('crm-stage-gates').shadowRoot;gate.querySelector('[name=reason]').value='Browser verified override';gate.querySelector('[name=override]').checked=true;gate.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('crm-stage-gates').shadowRoot.textContent.includes('Current stage: Submitted'));
  await page.evaluate(()=>{const root=document.querySelector('crm-record-tools').shadowRoot;[...root.querySelectorAll('details')].find(d=>d.querySelector('summary')?.textContent==='Unified client timeline').open=true});
  await page.waitForFunction(()=>document.querySelector('crm-record-tools').shadowRoot.querySelector('crm-client-history')?.shadowRoot.textContent.includes('Browser verified override'));
  await page.goto(base+'/workspace?tab=escalations',{waitUntil:'networkidle2'});await page.waitForSelector('crm-workspace >>> crm-escalation-rules >>> details');
  await page.evaluate(()=>{const rule=document.querySelector('crm-workspace').shadowRoot.querySelector('crm-escalation-rules').shadowRoot.querySelector('details');rule.open=true;rule.querySelector('[name=name]').value='Browser overdue escalation';rule.querySelector('[name=enabled]').checked=true;rule.querySelector('form').requestSubmit()});
  await page.waitForFunction(()=>document.querySelector('crm-workspace').shadowRoot.querySelector('crm-escalation-rules').shadowRoot.textContent.includes('Browser overdue escalation · enabled'));
  await page.evaluate(async()=>{const client=(await(await fetch('/api/contacts')).json()).contacts[0];for(let i=0;i<65;i++){const response=await fetch('/api/deals',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({title:'Progressive browser '+String(i).padStart(3,'0'),contactId:client.id,value:10,currency:'USD',stage:'Lead',owner:'Demo User',closeDate:'2026-10-15'})});if(!response.ok)throw new Error(await response.text())}});
  await page.goto(base+'/deals',{waitUntil:'networkidle2'});await page.waitForSelector('.deal-card');
  const search=await page.$('input[aria-label="Search deals"]');assert.ok(search);await search.type('Progressive browser');
  await page.waitForFunction(()=>document.querySelector('.deals-page-scope')?.textContent.includes('50 of 65'));
  assert.equal(await page.$$eval('.deal-card',cards=>cards.length),50);
  assert.ok(await page.$eval('.deals-summary',el=>el.textContent.includes('650')));
  await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent==='Load more deals').click());
  await page.waitForFunction(()=>document.querySelector('.deals-page-scope')?.textContent.includes('65 of 65'));
  assert.equal(await page.$$eval('.deal-card',cards=>cards.length),65);assert.deepEqual(errors,[]);
 }finally{await browser?.close();if(server.exitCode===null){server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve))}fs.rmSync(directory,{recursive:true,force:true})}
});
