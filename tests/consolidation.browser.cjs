const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const net = require('node:net');
const crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const puppeteer = require('puppeteer');
const root = path.join(__dirname, '..');

test('live consolidated communication, calendar, bulk selection, fixed navigation and directory', {timeout: 180000}, async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ecc-consolidation-'));
  const probe = net.createServer();
  await new Promise(resolve => probe.listen(0, '127.0.0.1', resolve));
  const port = probe.address().port;
  await new Promise(resolve => probe.close(resolve));
  const base = 'http://localhost:' + port;
  const secret = 'consolidation-inbound-fixture';
  const server = spawn(path.join(root, 'build/ecc-crm'), [], {cwd: root, env: {
    ...process.env,SEED_DEMO_DATA:'true', PORT: String(port), DATABASE_PATH: path.join(directory, 'crm.sqlite3'),
    JWT_SECRET: 'consolidation-session-fixture', APP_URL: base, ALLOW_SIGNUP: 'false',
    INBOUND_EMAIL_SECRET: secret, SMTP_HOST: '', GRAPH_ORG_ID: '', WHATSAPP_ORG_ID: '',
    STRIPE_SECRET_KEY: '', OPENAI_API_KEY: ''
  }, stdio: 'pipe'});
  let output = '', browser;
  server.stderr.on('data', data => { output += data; });
  try {
    for (let i = 0; i < 100; i++) {
      try { if ((await fetch(base + '/api/health')).ok) break; } catch {}
      if (i === 99) throw new Error('Server failed: ' + output);
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    const local = path.join(os.homedir(), '.cache/ms-playwright/chromium-1234/chrome-linux64/chrome');
    browser = await puppeteer.launch({executablePath: process.env.CHROME_PATH || (fs.existsSync(local) ? local : await puppeteer.executablePath()), headless: true, pipe: true, args: ['--no-sandbox', '--disable-dev-shm-usage']});
    const page = await browser.newPage(), errors = [];
    await page.setViewport({width:1280,height:900});
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(base, {waitUntil: 'networkidle2'});
    await page.waitForSelector('input[type=email]');
    await page.type('input[type=email]', 'demo@northwind.dev');
    await page.type('input[type=password]', 'Demo1234');
    await page.click('button[type=submit]');
    await page.waitForSelector('.app-shell');
    const api = (url, method = 'GET', data, headers = {}) => page.evaluate(async (url, method, data, headers) => {
      const response = await fetch(url, {method, headers: {'Content-Type': 'application/json', ...headers}, ...(data === undefined ? {} : {body: JSON.stringify(data)})});
      const result = await response.json();
      if (!response.ok) throw new Error(response.status + ' ' + JSON.stringify(result));
      return result;
    }, url, method, data, headers);
    const clickText = text => page.evaluate(text => {
      const root = document.querySelector('crm-workspace').shadowRoot;
      const button = [...root.querySelectorAll('button')].find(button => button.textContent === text);
      if (!button) throw new Error('Button missing: ' + text);
      button.click();
    }, text);

    // Use real records beyond the first contact page, then cause a genuine
    // revision conflict after review. No live provider is configured.
    const created = [];
    for (let i = 0; i < 27; i++) {
      const out = await api('/api/contacts', 'POST', {name: 'Consolidation client ' + String(i).padStart(2, '0'), email: `consolidation-${i}@example.com`, stage: 'Lead'});
      created.push(out.contact);
    }
    await page.goto(base + '/workspace?tab=data', {waitUntil: 'networkidle2'});
    await page.waitForSelector('crm-workspace >>> input[aria-label="Search contacts to update"]');
    await page.bringToFront();
    await page.click('crm-workspace >>> input[aria-label="Search contacts to update"]');
    await page.keyboard.type('Consolidation client');
    await clickText('Search contacts');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('27 matching contacts'));
    await page.click('crm-workspace >>> input[aria-label="Select Consolidation client 00"]');
    await page.evaluate(() => {
      const card = document.querySelector('crm-workspace').shadowRoot.querySelector('input[aria-label="Search contacts to update"]').closest('section');
      [...card.querySelectorAll('button')].find(button => button.textContent === 'Next').click();
    });
    await page.waitForSelector('crm-workspace >>> input[aria-label="Select Consolidation client 25"]');
    await page.click('crm-workspace >>> input[aria-label="Select Consolidation client 25"]');
    await page.select('crm-workspace >>> select[aria-label="New contact stage"]', 'Client');
    await clickText('Review selected contacts');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Review: change 2 contacts to Client'));
    const current = (await api('/api/records/contacts/' + created[0].id)).record;
    await api('/api/contacts/' + created[0].id, 'PUT', {...current, notes: 'Edited after review'}, {'If-Match': current._revision});
    await clickText('Update reviewed contacts');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Selection is kept'));
    assert.equal((await api('/api/records/contacts/' + created[25].id)).record.stage, 'Lead');
    await clickText('Review selected contacts');
    await page.waitForFunction(() => [...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('button')].some(button => button.textContent === 'Update reviewed contacts' && !button.disabled));
    await clickText('Update reviewed contacts');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Contacts updated.'));
    assert.equal((await api('/api/records/contacts/' + created[0].id)).record.stage, 'Client');
    assert.equal((await api('/api/records/contacts/' + created[25].id)).record.stage, 'Client');
    assert.equal((await api('/api/records/contacts/' + created[1].id)).record.stage, 'Lead');

    // Seed channel history using the public app endpoints. SMTP stays disabled.
    const application = (await api('/api/cases')).cases[0];
    const client = (await api('/api/records/contacts/' + application.clientId)).record;
    await api('/api/mail', 'POST', {contactId: client.id, recipient: client.email, subject: 'Consolidated queued email', body: 'Email fixture'});
    const invite = await api('/api/portal/invitations', 'POST', {contactId: client.id, email: client.email});
    const token = new URLSearchParams(new URL(invite.url).hash.slice(1)).get('invite');
    await api('/api/portal/session', 'POST', {token});
    await api('/api/portal/messages', 'POST', {caseId: application.id, body: 'Consolidated portal reply'});
    const user = (await api('/api/control-center')).user;
    const inbound = JSON.stringify({id: 'consolidation-unmatched', orgId: user.orgId, from: 'unknown-consolidation@example.com', subject: 'Consolidated unmatched email', body: 'Incoming fixture'});
    const stamp = String(Math.floor(Date.now() / 1000));
    const signature = crypto.createHmac('sha256', secret).update(stamp + '.' + inbound).digest('hex');
    const incoming = await fetch(base + '/api/inbound/email', {method: 'POST', headers: {'Content-Type': 'application/json', 'X-ECC-Timestamp': stamp, 'X-ECC-Signature': signature}, body: inbound});
    assert.equal(incoming.status, 202, await incoming.text());
    await page.click('.sidebar a[href="/workspace?tab=communication"]');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Consolidated portal reply'));
    assert.ok(await page.$eval('crm-workspace', host => host.shadowRoot.textContent.includes('Consolidated queued email')));
    assert.equal(await page.$eval('crm-workspace >>> .communication-compose button[type=submit]', button => button.disabled), true);
    await page.select('crm-workspace >>> select[aria-label="Communication channel"]', 'portal');
    await page.waitForFunction(() => !document.querySelector('crm-workspace').shadowRoot.textContent.includes('Consolidated queued email'));
    await page.goto(base + '/workspace?tab=inbox', {waitUntil: 'networkidle2'});
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Consolidated unmatched email'));
    assert.equal(await page.$eval('crm-workspace >>> select[aria-label="Message scope"]', select => select.value), 'unmatched');
    const unmatchedPicker = 'crm-workspace >>> article crm-record-picker';
    await page.type(unmatchedPicker + ' >>> input', client.name);
    await page.waitForSelector(unmatchedPicker + ' >>> .results button');
    await page.click(unmatchedPicker + ' >>> .results button');
    await clickText('Attach message');
    await page.waitForFunction(() => !document.querySelector('crm-workspace').shadowRoot.textContent.includes('Consolidated unmatched email'));
    const history = await api('/api/communication?contactId=' + client.id);
    assert.ok(history.messages.some(message => message.subject.includes('Consolidated unmatched email')));

    await api('/api/tasks', 'POST', {title: 'Consolidation calendar task', status: 'todo', dueDate: '2026-11-15', contactId: client.id});
    const caseNow = (await api('/api/records/cases/' + application.id)).record;
    await api('/api/cases/' + application.id, 'PUT', {...caseNow, nextDeadline: '2026-11-16'}, {'If-Match': caseNow._revision});
    await page.click('.sidebar a[href="/workspace?tab=calendar"]');
    await page.waitForSelector('crm-workspace >>> input[aria-label="Calendar month"]');
    await page.$eval('crm-workspace >>> input[aria-label="Calendar month"]', input => { input.value = '2026-11'; input.dispatchEvent(new Event('change')); });
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('Consolidation calendar task'));
    assert.ok(await page.$eval('crm-workspace', host => host.shadowRoot.textContent.includes('2026-11-16')));
    await page.select('crm-workspace >>> select[aria-label="Calendar event type"]', 'task');
    await page.waitForFunction(() => !document.querySelector('crm-workspace').shadowRoot.textContent.includes('2026-11-16'));
    await clickText('Next month');
    assert.equal(await page.$eval('crm-workspace >>> input[aria-label="Calendar month"]', input => input.value), '2026-12');

    // Fixed navigation exposes modules without focus or optional-tool controls.
    assert.equal(await page.$('crm-nav-focus'), null);
    await page.$eval('.navigation-more', details => { details.open = true; });
    assert.notEqual(await page.$eval('.sidebar [data-nav-label="Deals"]', element => getComputedStyle(element).display), 'none');
    await page.waitForFunction(() => [...document.querySelector('crm-workspace').shadowRoot.querySelectorAll('#tabs button')].some(button => button.textContent === 'Scan QR'));
    await clickText('Scan QR');
    await page.waitForSelector('crm-workspace >>> video');
    await page.$eval('.navigation-more', details => { details.open = true; });
    await page.click('.sidebar a[href="/workspace?tab=directory"]');
    await page.waitForSelector('crm-workspace >>> article a[href^="/agents/"]');
    assert.ok(await page.$('crm-workspace >>> article a[href^="/partners/"]'));
    await page.select('crm-workspace >>> select[aria-label="Directory type"]', 'partners');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.querySelector('article a[href^="/partners/"]') && !document.querySelector('crm-workspace').shadowRoot.querySelector('article a[href^="/agents/"]'));
    assert.ok(await page.$('.sidebar a[href="/workspace?tab=directory"]'));
    await page.setViewport({width: 390, height: 844});
    assert.ok(await page.$eval('main.content', element => element.scrollWidth <= element.clientWidth + 2));
    await page.goto(base + '/workspace?tab=data', {waitUntil: 'networkidle2'});
    await page.waitForSelector('crm-workspace >>> input[aria-label="Search contacts to update"]');
    await page.click('crm-workspace >>> input[aria-label="Search contacts to update"]');
    await page.keyboard.type('Consolidation client');
    await clickText('Search contacts');
    await page.waitForFunction(() => document.querySelector('crm-workspace').shadowRoot.textContent.includes('27 matching contacts'));
    assert.ok(await page.$eval('main.content', element => element.scrollWidth <= element.clientWidth + 2));
    assert.deepEqual(errors, []);
  } catch (error) {
    if (browser) { const pages = await browser.pages(); const current = pages[pages.length - 1]; if (current) { await current.screenshot({path:'/tmp/ecc-consolidation-failure.png'});console.error(await current.evaluate(() => ({url: location.href, search: document.querySelector('crm-workspace')?.shadowRoot.querySelector('input[aria-label="Search contacts to update"]')?.value, content: document.querySelector('crm-workspace')?.shadowRoot.textContent.slice(0,3500)})));} }
    throw error;
  } finally {
    await browser?.close();
    server.kill('SIGTERM');
    await new Promise(resolve => { if (server.exitCode != null) resolve(); else server.once('exit', resolve); });
    fs.rmSync(directory, {recursive: true, force: true});
  }
});
