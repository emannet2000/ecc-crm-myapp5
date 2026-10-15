'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../public/session.js'), 'utf8');
function client(fetch, extras = {}) {
  const window = {...extras};
  vm.runInNewContext(source, {window, fetch, CustomEvent:class {constructor(type){this.type=type;}}});
  return window.CRMAuthenticatedFetch;
}
test('concurrent expired reads and writes share refresh and preserve write options', async () => {
  let refreshed = false, refreshes = 0;
  const attempts = new Map();
  const options = {method:'POST', headers:{'If-Match':'original'}, body:'draft'};
  const request = client(async (path, actual) => {
    if (path === '/api/session/refresh') {
      refreshes++;
      await new Promise(resolve => setTimeout(resolve, 10));
      refreshed = true;
      return {ok:true};
    }
    attempts.set(path, (attempts.get(path) || 0) + 1);
    if (path === '/api/write') {
      assert.equal(actual.body, options.body);
      assert.equal(actual.headers, options.headers);
      assert.equal(actual.method, 'POST');
    }
    return {status:refreshed ? 200 : 401};
  });
  assert.deepEqual((await Promise.all([request('/api/read'),request('/api/write', options)])).map(r=>r.status), [200,200]);
  assert.equal(refreshes, 1);
  assert.equal(attempts.get('/api/write'), 2);
});
test('failed refresh and repeated 401 stop without navigating or losing drafts', async () => {
  for (const refreshOK of [false, true]) {
    let calls = 0;
    const request = client(async path => {calls++;return path === '/api/session/refresh' ? {ok:refreshOK,status:refreshOK ? 200 : 401} : {status:401};});
    await assert.rejects(request('/api/write', {method:'POST',body:'unsaved'}), error => error.status === 401 && error.message.includes('Your entries are kept'));
    assert.equal(calls, refreshOK ? 3 : 2);
  }
});
test('network failures and non-authentication failures never replay writes', async () => {
  for (const status of [409, 500, 'network']) {
    let calls = 0;
    const request = client(async () => {calls++;if(status === 'network')throw new Error('offline');return {status};});
    if (status === 'network') await assert.rejects(request('/api/write'), /offline/);
    else assert.equal((await request('/api/write')).status, status);
    assert.equal(calls, 1);
  }
});
test('late 401 after a completed refresh retries with the current session', async () => {
  let release, refreshes = 0, slowCalls = 0;
  const request = client(async path => {
    if (path === '/api/session/refresh') {refreshes++;return {ok:true};}
    if (path === '/api/slow' && ++slowCalls === 1) return new Promise(resolve=>{release=()=>resolve({status:401});});
    return {status:refreshes ? 200 : 401};
  });
  const slow = request('/api/slow');
  await request('/api/fast');
  release();
  assert.equal((await slow).status, 200);
  assert.equal(refreshes, 1);
});

test('refresh server and policy failures retain their status without replaying the write', async () => {
  for (const status of [403, 500, 503]) {
    let writes = 0;
    const request = client(async path => {
      if (path === '/api/session/refresh') return {ok:false,status};
      writes++;
      return {status:401};
    });
    await assert.rejects(request('/api/write', {method:'POST',body:'draft'}), error =>
      error.status === status && !error.message.includes('session expired') && error.message.includes('Try again'));
    assert.equal(writes, 1);
  }
});

test('refresh for a different account cannot replay the original write',async()=>{
 let writes=0,changed=false;
 const request=client(async path=>{
  if(path==='/api/session/refresh')return {ok:true,clone:()=>({json:async()=>({user:{id:'new-owner'}})})};
  writes++;return {status:401};
 },{document:{querySelector:()=>({getAttribute:()=> 'original-owner'})},dispatchEvent:event=>{changed=event.type==='crm:account-changed';}});
 await assert.rejects(request('/api/write',{method:'POST',body:'original-owner draft'}),/account changed/);
 assert.equal(writes,1);assert.equal(changed,true);
});
