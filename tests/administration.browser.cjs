'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const {spawn} = require('node:child_process');
const puppeteer = require('puppeteer');
const root = path.resolve(__dirname, '..');

test('native Elm administration protects drafts, confirms access changes and retains rejected saves', {timeout:180000}, async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ecc-admin-browser-'));
  const probe = net.createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const base = 'http://localhost:' + port;
  const server = spawn(path.join(root, 'build/ecc-crm'), [], {cwd:root,env:{...process.env,SEED_DEMO_DATA:'true',PORT:String(port),DATABASE_PATH:path.join(directory,'crm.sqlite3'),APP_URL:base,JWT_SECRET:'administration-local-test-only',ALLOW_SIGNUP:'false',SMTP_HOST:'',STRIPE_SECRET_KEY:'',OPENAI_API_KEY:''},stdio:'pipe'});
  let browser, output = '';
  server.stderr.on('data', data => {output += data});
  const errors = [];
  try {
    for (let attempt=0;attempt<100;attempt++) {
      if (server.exitCode !== null) throw Error(output);
      try {if ((await fetch(base+'/api/health')).ok) break} catch {}
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    browser = await puppeteer.launch({executablePath:process.env.CHROME_PATH||await puppeteer.executablePath(),headless:true,pipe:true,args:['--no-sandbox','--disable-dev-shm-usage']});
    const page = await browser.newPage();
    page.on('pageerror',error=>errors.push(error.message));
    await page.goto(base,{waitUntil:'domcontentloaded'});
    await page.waitForSelector('input[type=email]');await page.type('input[type=email]','demo@northwind.dev');
    await page.type('input[type=password]','Demo1234');
    await page.click('button[type=submit]');
    await page.waitForSelector('.app-shell');
    const user = await page.evaluate(async()=>{
      const response=await fetch('/api/admin/users',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Draft Member',email:'draft-member@test.invalid',role:'member',password:'MemberPassword123!'})});
      if(!response.ok)throw Error(await response.text());return(await response.json()).user;
    });
    await page.goto(base+'/administration',{waitUntil:'domcontentloaded'});
    await page.waitForSelector('.administration-elm table');
    assert.equal(await page.$('crm-administration'),null);
    const click=async label=>{await page.waitForFunction(label=>[...document.querySelector('.administration-elm').querySelectorAll('button')].some(button=>button.textContent===label),{},label);return page.evaluate(label=>[...document.querySelector('.administration-elm').querySelectorAll('button')].find(button=>button.textContent===label).click(),label)};
    const field=async(name,value)=>{await page.waitForSelector('.administration-elm [name='+name+']');return page.$eval('.administration-elm [name='+name+']',(element,value)=>{element.value=value;element.dispatchEvent(new Event('input',{bubbles:true}))},value)};
    const manage=()=>page.click('.administration-elm button[aria-label="Manage Draft Member"]');
    await manage();await field('name','Unsaved member');
    await click('Teams');
    assert.equal(await page.$eval('.administration-elm [name=name]',element=>element.value),'Unsaved member');
    await page.waitForFunction(()=>document.querySelector('.administration-elm').textContent.includes('Unsaved changes'));
    await click('Stay');
    assert.equal(await page.$eval('.administration-elm [name=name]',element=>element.value),'Unsaved member');
    await click('Workspace settings');await click('Save');
    await page.waitForSelector('.administration-elm [name=timezone]');
    assert.equal(await page.$eval('.administration-elm nav [aria-current=page]',element=>element.textContent),'Workspace settings');
    await field('name','Workspace draft');await click('Refresh');await click('Stay');
    assert.equal(await page.$eval('.administration-elm [name=name]',element=>element.value),'Workspace draft');
    await click('Users');await click('Discard');
    await page.waitForSelector('.administration-elm button[aria-label="Manage Unsaved member"]');await page.click('.administration-elm button[aria-label="Manage Unsaved member"]');
    await field('role','manager');await click('Teams');await click('Save');
    await page.waitForFunction(()=>document.querySelector('.administration-elm').textContent.includes('Confirm account change'));
    await click('Cancel');
    assert.equal(await page.$eval('.administration-elm [name=role]',element=>element.value),'manager');
    await click('Close');await click('Discard');
    await page.waitForSelector('.administration-elm button[aria-label="Manage Unsaved member"]');await page.click('.administration-elm button[aria-label="Manage Unsaved member"]');
    await field('name','Kept after conflict');
    await page.evaluate(async id=>{
      const response=await fetch('/api/admin/users/'+id,{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify({name:'Concurrent server change'})});
      if(!response.ok)throw Error(await response.text());
    },user.id);
    await click('Save access');
    await page.waitForFunction(()=>document.querySelector('.administration-elm #notice').textContent.includes('access changed'));
    assert.equal(await page.$eval('.administration-elm [name=name]',element=>element.value),'Kept after conflict');
    assert.deepEqual(errors,[]);
    // Native browser unload protection is driven by Elm draft state through a port.
    await page.click('.administration-elm [name=name]');await page.type('.administration-elm [name=name]','!');
    let warned=false;
    page.once('dialog',async dialog=>{warned=dialog.type()==='beforeunload';await dialog.dismiss()});
    await page.reload({waitUntil:'domcontentloaded',timeout:10000}).catch(()=>{});
    assert.equal(warned,true);
    assert.equal(await page.$eval('.administration-elm [name=name]',element=>element.value),'Kept after conflict!');
  } finally {
    await browser?.close();
    if(server.exitCode===null){server.kill('SIGTERM');await new Promise(resolve=>server.once('exit',resolve))}
    fs.rmSync(directory,{recursive:true,force:true});
  }
});
