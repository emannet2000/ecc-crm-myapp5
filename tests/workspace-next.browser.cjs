const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const net=require('node:net');
const {spawn,execFileSync}=require('node:child_process');
const puppeteer=require('puppeteer');
const root=path.join(__dirname,'..');

test('grouped navigation, requirement filters, representative loading and isolated restore',{timeout:300000},async()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-workspace-next-'));
 const database=path.join(directory,'fixture.sqlite3');
 execFileSync('go',['test','-run','^TestWriteRepresentativeBrowserFixture$','-count=1'],{cwd:path.join(root,'golang-backend'),env:{...process.env,SEED_DEMO_DATA:'true',ECC_BROWSER_FIXTURE_DATABASE:database},timeout:180000,stdio:'pipe'});
 const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
 const base='http://127.0.0.1:'+port;
 let server,browser,log='';
 const start=async(binary,db)=>{
  server=spawn(binary,[],{cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',PORT:String(port),DATABASE_PATH:db,JWT_SECRET:'next-workspace-test-only',APP_URL:base,ALLOW_SIGNUP:'false',SMTP_HOST:'',OPENAI_API_KEY:'',STRIPE_SECRET_KEY:'',WHATSAPP_ORG_ID:'',GRAPH_ORG_ID:'',VAPID_PUBLIC_KEY:'',ECC_ACCEPTANCE_SEND:'false'},stdio:'pipe'});
  server.stderr.on('data',data=>log+=data);
  for(let i=0;i<150;i++){try{if((await fetch(base+'/api/health')).ok)return}catch{}if(server.exitCode!==null)throw new Error(log);await new Promise(resolve=>setTimeout(resolve,100))}throw new Error('Server did not start');
 };
 const stop=async()=>{if(server&&server.exitCode===null){server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve))}};
 const login=async(page,email='demo@northwind.dev',password='Demo1234')=>{await page.goto(base);await page.waitForSelector('input[type=email]');await page.type('input[type=email]',email);await page.type('input[type=password]',password);await page.click('button[type=submit]');await page.waitForSelector('.app-shell')};
 const api=async(page,url,method='GET',body,revision)=>page.evaluate(async(url,method,body,revision)=>{const response=await fetch(url,{method,headers:{'Content-Type':'application/json',...(revision?{'If-Match':revision}:{})},body:body===undefined?undefined:JSON.stringify(body)});const data=await response.json();if(!response.ok)throw new Error(response.status+': '+JSON.stringify(data));return data},url,method,body,revision);
 const artifacts=path.join(root,'tests/artifacts');fs.mkdirSync(artifacts,{recursive:true});
 const report={dataset:{contacts:5000,applications:5000,requiredDocuments:5000,foreignWorkspaceFraction:0.2},browser:{},validation:{staffSessions:'pending: actual participants required'}};
 try{
  const local=path.join(os.homedir(),'.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||(fs.existsSync(local)?local:await puppeteer.executablePath()),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  const errors=[];
  for(const[label,binary]of [['before',process.env.ECC_BASELINE_BINARY],['after',path.join(root,'build/ecc-crm')]]){
   if(!binary)continue;
   const db=path.join(directory,label,'crm.sqlite3');fs.mkdirSync(path.dirname(db),{recursive:true});fs.copyFileSync(database,db);await start(binary,db);
   const context=await browser.createBrowserContext(),page=await context.newPage();page.setDefaultTimeout(45000);page.on('pageerror',error=>errors.push(error.message));await page.setViewport({width:1280,height:900});await login(page);
   report.browser[label]=[];
   for(let i=0;i<3;i++){
    await page.goto(base,{waitUntil:'load'});await page.waitForFunction(()=>document.querySelector('.daily-work')?.textContent.includes('work items'));
    const usableWorkMs=await page.evaluate(()=>performance.now());
    await page.waitForFunction(()=>[...document.querySelectorAll('.home-secondary > summary')].every(summary=>summary.textContent.includes(' · ')&&!summary.textContent.includes('Loading')&&!summary.textContent.includes('Unavailable')));
    report.browser[label].push(await page.evaluate(usableWorkMs=>({usableWorkMs,completeHomeMs:performance.now(),navigationLoadMs:performance.getEntriesByType('navigation')[0].loadEventEnd,requests:performance.getEntriesByType('resource').filter(r=>r.name.includes('/api/')).map(r=>({path:new URL(r.name).pathname,durationMs:r.duration,transferBytes:r.transferSize}))}),usableWorkMs));
   }
   fs.writeFileSync(path.join(artifacts,'next-workspace-report.json'),JSON.stringify(report,null,2));
   await page.goto(base+'/workspace?tab=documents');await page.waitForSelector('crm-workspace >>> .workspace-nav-group');
   const groups=await page.$eval('crm-workspace',host=>[...host.shadowRoot.querySelectorAll('.workspace-nav-group h3')].map(h=>h.textContent));assert.deepEqual(groups,['Daily work','Finance','Data','Administration']);
   await page.waitForSelector('crm-workspace >>> [aria-label="Document filters"] button[data-filter=missing]');await page.$eval('crm-workspace',host=>host.shadowRoot.querySelector('[aria-label="Document filters"] button[data-filter=missing]').click());
   assert.ok(await page.$eval('crm-workspace',host=>host.shadowRoot.querySelector('[data-filter=missing]').getAttribute('aria-pressed')==='true'));
   if(label==='before'){await context.close();await stop();continue}
   const application=(await api(page,'/api/cases?limit=1')).cases[0];
   await page.goto(base+'/cases/'+application.id);await page.waitForSelector('.application-essentials');await page.waitForFunction(()=>document.querySelector('crm-application-blockers')?.shadowRoot.querySelector('[data-filter=missing]'));
   await page.waitForFunction(()=>document.querySelector('crm-record-tools')?.shadowRoot.querySelector('#title')?.textContent==='Overview');assert.ok(await page.$eval('crm-record-tools',host=>!host.shadowRoot.textContent.includes('Could not load workspace tools')&&!host.shadowRoot.querySelector('#notice').textContent));assert.equal(await page.$$eval('crm-work-plan',hosts=>hosts.length),1);
   assert.ok(await page.$$eval('.application-controls',sections=>sections.filter(s=>['All document records and uploads','Workflow progress and stage controls','Alerts and document activity'].includes(s.querySelector('summary')?.textContent)).every(s=>!s.open)));
   const requirements=await api(page,'/api/cases/'+application.id+'/blockers');const missing=requirements.checklist.find(row=>row.missing&&row.editable);assert.ok(missing);
   const host=await page.$('crm-application-blockers');
   await host.evaluate(host=>host.shadowRoot.querySelector('[data-filter=missing]').click());
   await host.evaluate((host,{id,staff})=>{const card=[...host.shadowRoot.querySelectorAll('.requirement-item')].find(card=>card.querySelector('a')?.href.includes('document='+id));card.querySelector('details').open=true;const form=card.querySelector('form');form.querySelector('select').value=staff;form.querySelector('input[type=date]').value='2000-01-01';form.querySelector('input[type=date]').dispatchEvent(new Event('input',{bubbles:true}));host.shadowRoot.querySelector('[data-filter=overdue]').click()},{id:missing.id,staff:missing.assignees[0].id});
   assert.ok(await host.evaluate(host=>host.shadowRoot.textContent.includes('Save it before changing filters')));
   await host.evaluate(host=>host.shadowRoot.querySelector('[data-dirty=true]').requestSubmit());
   await page.waitForFunction(async id=>{const out=await(await fetch('/api/cases/'+id+'/blockers')).json();return out.checklist.some(row=>row.documentDueDate==='2000-01-01'&&row.overdue)}, {},application.id);
   await page.waitForFunction(()=>document.querySelector('crm-application-blockers').shadowRoot.querySelector('[data-filter=overdue]')&&!document.querySelector('crm-application-blockers').shadowRoot.querySelector('[data-dirty=true]'));
   await host.evaluate(host=>host.shadowRoot.querySelector('[data-filter=overdue]').click());assert.equal(await host.evaluate(host=>host.shadowRoot.querySelector('[data-filter=overdue]').getAttribute('aria-pressed')),'true');
   // Upload a real fixture so restoration exercises file relocation and checksums.
   await page.evaluate(async id=>{const out=await(await fetch('/api/records/documents/'+id)).json();const form=new FormData();form.append('file',new Blob(['isolated restore fixture'],{type:'text/plain'}),'restore.txt');const response=await fetch('/api/documents/'+id+'/files',{method:'POST',headers:{'If-Match':out.record._revision},body:form});if(!response.ok)throw new Error(await response.text())},missing.id);
   await page.setViewport({width:390,height:844});await page.screenshot({path:path.join(artifacts,'next-application-phone.png'),fullPage:true});assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
   for(const role of ['member','viewer','manager']){
    const email='next-'+role+'@example.test',password='NextRoleFixture123!';await api(page,'/api/admin/users','POST',{name:'Next '+role,email,password,role});
    const roleContext=await browser.createBrowserContext(),rolePage=await roleContext.newPage();rolePage.setDefaultTimeout(45000);await rolePage.setViewport({width:390,height:844});await login(rolePage,email,password);await rolePage.goto(base+'/workspace?tab=recovery');await rolePage.waitForSelector('crm-workspace >>> .workspace-nav-group');
    const text=await rolePage.$eval('crm-workspace',host=>host.shadowRoot.querySelector('#tabs').textContent);assert.ok(!text.includes('Backup & restore'));if(role!=='manager')assert.ok(!text.includes('Team & access'));if(role==='viewer')assert.ok(!text.includes('Finance review')&&!text.includes('Workflows')&&!text.includes('Trash'));assert.ok(await rolePage.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));await roleContext.close();
   }
   const assessmentPath=path.join(artifacts,'next-integration-assessment.json');execFileSync('node',['tests/live-integrations.cjs'],{cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',ECC_ACCEPTANCE_URL:base,ECC_ACCEPTANCE_EMAIL:'demo@northwind.dev',ECC_ACCEPTANCE_PASSWORD:'Demo1234',ECC_ACCEPTANCE_SEND:'false',ECC_ACCEPTANCE_REPORT:assessmentPath},timeout:90000,stdio:'pipe'});report.validation.integrations=JSON.parse(fs.readFileSync(assessmentPath,'utf8'));
   await context.close();await stop();
   const archive=path.join(directory,'backup.tar.gz');execFileSync('python3',['scripts/backup.py',db,archive],{cwd:root,stdio:'pipe'});
   report.validation.restore=JSON.parse(execFileSync('python3',['scripts/verify_backup.py',archive],{cwd:root,encoding:'utf8'}));assert.equal(report.validation.restore.state,'verified');assert.ok(report.validation.restore.documentFiles>0);
   const restored=path.join(directory,'restored');execFileSync('python3',['scripts/restore.py',archive,restored],{cwd:root,stdio:'pipe'});await start(path.join(root,'build/ecc-crm'),path.join(restored,'crm.sqlite3'));
   const restoredContext=await browser.createBrowserContext(),restoredPage=await restoredContext.newPage();await login(restoredPage);const saved=(await api(restoredPage,'/api/records/documents/'+missing.id)).record;assert.equal(saved.dueDate,'2000-01-01');assert.equal(saved.responsibleId,missing.assignees[0].id);
   const content=await restoredPage.evaluate(async id=>{const response=await fetch('/api/documents/'+id+'/files/1');if(!response.ok)throw new Error('Restored download failed');return response.text()},missing.id);assert.equal(content,'isolated restore fixture');report.validation.restoredApplicationLoginAndDownload='passed';await restoredContext.close();await stop();
  }
  assert.deepEqual(errors,[]);fs.writeFileSync(path.join(artifacts,'next-workspace-report.json'),JSON.stringify(report,null,2));console.log('Representative browser measurements:',JSON.stringify(Object.fromEntries(Object.entries(report.browser).map(([key,rows])=>[key,rows.map(({usableWorkMs,completeHomeMs})=>({usableWorkMs,completeHomeMs}))]))));
 }finally{await browser?.close();await stop();fs.rmSync(directory,{recursive:true,force:true})}
});
