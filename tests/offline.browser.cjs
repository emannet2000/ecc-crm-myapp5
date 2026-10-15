const {test}=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const fs=require('node:fs');
const path=require('node:path');
const os=require('node:os');
const puppeteer=require('puppeteer');
const root=path.join(__dirname,'..');

async function fixture(context, options={}){
 const user={id:'staff-one',orgId:'org-one',role:'admin',name:'Staff One'};
 const state={offline:false,user,record:{id:'contact-one',orgId:'org-one',ownerId:'staff-one',name:'Original',stage:'Lead',_revision:'version-one'},writes:0};
 const server=http.createServer(async(req,res)=>{
  const url=new URL(req.url,'http://localhost');
  if(url.pathname.startsWith('/api/')){
   if(state.offline){req.socket.destroy();return}
   res.setHeader('Content-Type','application/json');
   if(url.pathname==='/api/me'){res.end(JSON.stringify({user:state.user}));return}
   if(url.pathname==='/api/session/logout'){res.end('{}');return}
   if(url.pathname==='/api/contacts'&&req.method==='GET'){res.end(JSON.stringify({contacts:[state.record],total:1}));return}
   if((url.pathname==='/api/records/contacts/contact-one'||url.pathname==='/api/contacts/contact-one')&&req.method==='GET'){res.end(JSON.stringify(url.pathname.startsWith('/api/records/')?{record:state.record,editable:true}:{contact:state.record}));return}
   if(url.pathname==='/api/contacts/contact-one'&&req.method==='PUT'){
    let raw='';for await(const chunk of req)raw+=chunk;
    if(req.headers['if-match']!==state.record._revision){res.statusCode=409;res.end(JSON.stringify({message:'Record changed'}));return}
    state.record={...state.record,...JSON.parse(raw),_revision:'version-'+(++state.writes+1)};res.end(JSON.stringify({contact:state.record}));return;
   }
   res.statusCode=404;res.end('{}');return;
  }
  if(url.pathname==='/'){res.setHeader('Content-Type','text/html');res.end(`<!doctype html><html><body><div class="app-shell"></div><script src="/public/offline.js"></script><script>${options.oldShell ? '(async()=>{await caches.open("ecc-crm-shell-v14");await caches.open("unrelated-app-cache");await navigator.serviceWorker.register("/sw.js")})()' : 'navigator.serviceWorker.register("/sw.js")'}</script></body></html>`);return}
  let file=url.pathname==='/sw.js'?'public/pwa-sw.js':url.pathname.slice(1);
  if(!file.startsWith('public/')&&file!=='elm.js'&&file!=='manifest.webmanifest'){res.statusCode=404;res.end();return}
  const target=path.join(root,file);if(!fs.existsSync(target)){res.statusCode=404;res.end();return}
  res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.css')?'text/css':file.endsWith('.webmanifest')?'application/manifest+json':'application/octet-stream');fs.createReadStream(target).pipe(res);
 });
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
 const executable=path.join(os.homedir(),'.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');
 let browser;
 try{browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||(fs.existsSync(executable)?executable:puppeteer.executablePath()),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']})}catch(error){await new Promise(resolve=>server.close(resolve));throw error}
 let closed=false;
 const close=async()=>{if(closed)return;closed=true;await browser.close().catch(()=>{});server.closeAllConnections();await new Promise(resolve=>server.close(resolve))};
 context.after(close);
 context.signal.addEventListener('abort',()=>{void close()},{once:true});
 const page=await browser.newPage();await page.goto('http://127.0.0.1:'+server.address().port);await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
 const command=(action,extra={})=>page.evaluate((action,extra)=>window.crmOffline.command(action,extra),action,extra);
 const request=(method,url,body,revision)=>page.evaluate(async(method,url,body,revision)=>{try{const headers={'Content-Type':'application/json'};if(revision)headers['If-Match']=revision;const response=await fetch(url,{method,headers,body:body?JSON.stringify(body):undefined});return{status:response.status,data:await response.json()}}catch(error){return{error:error.message}}},method,url,body,revision);
 return{state,page,command,request,close,async setOffline(value){state.offline=value;await page.setOfflineMode(value)}};
}

test('offline opt-in, persistent drafts, conflict review and successful sync',{timeout:90000},async(context)=>{
 const app=await fixture(context);try{
  await app.command('enable');await app.request('GET','/api/contacts');
  await app.setOffline(true);
  const cached=await app.request('GET','/api/contacts');assert.equal(cached.data.contacts[0].name,'Original');
  const detail=await app.request('GET','/api/contacts/contact-one');assert.equal(detail.data.contact.id,'contact-one');
  const edit=await app.request('PUT','/api/contacts/contact-one',{name:'Offline draft'},'version-one');assert.equal(edit.status,202);
  assert.equal((await app.request('GET','/api/contacts')).data.contacts[0].name,'Offline draft');assert.equal(app.state.writes,0);
  await app.page.reload();await app.page.waitForFunction(()=>!!navigator.serviceWorker.controller);
  assert.equal((await app.command('status')).jobs.length,1);assert.equal((await app.request('GET','/api/me')).data.user.id,'staff-one');assert.equal((await app.request('POST','/api/session/refresh')).data.token,'cookie-session');
  app.state.record.name='Another staff edit';app.state.record._revision='concurrent-version';await app.setOffline(false);
  let status=await app.command('sync');assert.equal(status.jobs[0].status,'conflict');assert.equal(app.state.record.name,'Another staff edit');
  const review=await app.command('review',{key:status.jobs[0].key});assert.equal(review.record.name,'Another staff edit');assert.equal(review.job.draft.name,'Offline draft');
  await app.command('retry',{key:review.job.key,revision:review.record._revision,confirmed:true});status=await app.command('sync');assert.equal(status.jobs.length,0);assert.equal(app.state.record.name,'Offline draft');assert.equal(app.state.writes,1);
 }finally{await app.close()}
});

test('offline account changes and sign-out clear private views and queued edits',{timeout:90000},async(context)=>{
 const app=await fixture(context);try{
  await app.command('enable');await app.request('GET','/api/contacts');await app.setOffline(true);
  assert.equal((await app.request('PUT','/api/contacts/contact-one',{name:'Private draft'},'version-one')).status,202);
  await app.setOffline(false);app.state.user={id:'staff-two',orgId:'org-two',role:'admin'};
  await app.request('GET','/api/me');let status=await app.command('status');assert.equal(status.enabled,false);assert.equal(status.jobs.length,0);
  assert.deepEqual(await app.page.evaluate(async()=> (await caches.keys()).filter(n=>n.startsWith('ecc-private-'))),[]);
  await app.command('enable');await app.request('GET','/api/contacts');await app.request('POST','/api/session/logout');status=await app.command('status');assert.equal(status.enabled,false);
  assert.deepEqual(await app.page.evaluate(async()=> (await caches.keys()).filter(n=>n.startsWith('ecc-private-'))),[]);
 }finally{await app.close()}
});

test('offline edits require cached versions and exclude financial and bulk writes',{timeout:90000},async(context)=>{
 const app=await fixture(context);try{
  await app.command('enable');await app.request('GET','/api/contacts');await app.setOffline(true);
  assert.equal((await app.request('PUT','/api/contacts/contact-one',{name:'No version'})).status,428);
  assert.equal((await app.request('PUT','/api/contacts/contact-one',{name:'Wrong version'},'wrong')).status,428);
  for(const [method,url]of [['POST','/api/contacts'],['POST','/api/deals/bulk'],['POST','/api/invoices/invoice-one/payments'],['DELETE','/api/contacts/contact-one']])assert.equal((await app.request(method,url,{ids:['contact-one']},'version-one')).status,503);
  assert.equal((await app.command('status')).jobs.length,0);
 }finally{await app.close()}
});

test('live Elm contact edits survive offline reload and synchronize to the Go API',{skip:process.env.ECC_BROWSER_LIVE!=='true',timeout:90000},async()=>{
 const {spawn}=require('node:child_process');const net=require('node:net');
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'ecc-offline-live-'));
 const probe=net.createServer();await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
 const base='http://localhost:'+port;let server,output='';
 const start=async()=>{server=spawn(path.join(root,'build/ecc-crm'),[],{cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',PORT:String(port),DATABASE_PATH:path.join(directory,'crm.sqlite3'),JWT_SECRET:'offline-test-only',APP_URL:base,ALLOW_SIGNUP:'false',GRAPH_ORG_ID:'',WHATSAPP_ORG_ID:''},stdio:'pipe'});server.stderr.on('data',data=>output+=data);for(let i=0;i<100;i++){try{if((await fetch(base+'/api/health')).ok)return}catch{}await new Promise(resolve=>setTimeout(resolve,100))}throw new Error('Server failed to start: '+output)};
 const stop=async()=>{if(!server||server.exitCode!==null)return;server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve))};
 const executable=path.join(os.homedir(),'.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');
 const browser=await puppeteer.launch({executablePath:process.env.CHROME_PATH||(fs.existsSync(executable)?executable:puppeteer.executablePath()),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']});const page=await browser.newPage();const errors=[];page.on('pageerror',error=>errors.push(error.message));
 try{
  await start();await page.goto(base,{waitUntil:'networkidle2'});await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');await page.type('input[type=password]','Demo1234');await page.click('button[type=submit]');await page.waitForSelector('.app-shell');await page.waitForFunction(()=>!!navigator.serviceWorker.controller);
  const contact=await page.evaluate(async()=>{const response=await fetch('/api/contacts',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Offline original',email:'offline-test@example.com',stage:'Lead'})});if(!response.ok)throw new Error(await response.text());return(await response.json()).contact});
  await page.evaluate(()=>window.crmOffline.command('enable'));await page.goto(base+'/contacts/'+contact.id,{waitUntil:'networkidle2'});await page.waitForFunction(()=>[...document.querySelectorAll('button')].some(b=>b.textContent.trim()==='Edit'));
  await stop();await page.setOfflineMode(true);
  await page.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.textContent.trim()==='Edit').click());await page.waitForSelector('#cf-name');await page.$eval('#cf-name',input=>{input.value='Offline updated';input.dispatchEvent(new Event('input',{bubbles:true}))});
  await page.click('.modal button[type=submit]');await page.waitForFunction(()=>!document.querySelector('.modal'));
  assert.equal((await page.evaluate(()=>window.crmOffline.command('status'))).jobs.length,1);
  await page.reload({waitUntil:'domcontentloaded'});await page.waitForSelector('.app-shell');await page.waitForFunction(()=>document.querySelector('main')?.textContent.includes('Offline updated'));
  await start();await page.setOfflineMode(false);await page.evaluate(()=>window.crmOffline.command('sync'));
  await page.waitForFunction(async()=>!(await window.crmOffline.command('status')).jobs.length);
  const saved=await page.evaluate(async id=>(await(await fetch('/api/contacts/'+id)).json()).contact,contact.id);assert.equal(saved.name,'Offline updated');assert.deepEqual(errors,[]);
 }finally{await page.close();await browser.close();await stop();fs.rmSync(directory,{recursive:true,force:true})}
});


test('PWA upgrade removes obsolete shells and preserves unrelated caches',{timeout:90000},async context=>{
 const app=await fixture(context,{oldShell:true});
 const keys=await app.page.evaluate(()=>caches.keys());
 assert.ok(!keys.includes('ecc-crm-shell-v14'));
 assert.equal(keys.filter(key=>key.startsWith('ecc-crm-shell-')).length,1);
 assert.ok(keys.includes('unrelated-app-cache'));
 for(const asset of ['/elm.js','/public/work-dashboard-elm.css','/public/team-chat-elm.css']){
  assert.ok(await app.page.evaluate(async asset=>{const response=await caches.match(asset);return response?.ok&&!!(await response.text())},asset),asset);
 }
});
