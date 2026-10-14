'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const path=require('node:path');
const {createRequire}=require('node:module');
const {acceptanceOptions,evaluateAcceptance}=require('./integration-acceptance-policy.cjs');

test('strict acceptance rejects missing configuration and every partial evidence status',()=>{
 for(const status of ['not_configured','pending','provider_accepted','callback_observed','response_observed','unknown',undefined]){
  const verdict=evaluateAcceptance([{integration:'email',status}],{strict:true,required:['email']});
  assert.equal(verdict.exitCode,1,status);assert.equal(verdict.complete,false,status);
 }
 assert.equal(evaluateAcceptance([],{strict:true,required:['email']}).exitCode,1);
 assert.equal(evaluateAcceptance([{integration:'email',status:'passed'},{integration:'email',status:'passed'}],{strict:true,required:['email']}).exitCode,1);
});

test('strict acceptance requires each selected provider and always fails actual errors',()=>{
 const options=acceptanceOptions({ECC_ACCEPTANCE_REQUIRED:'email,payments'},['--strict']);
 assert.equal(evaluateAcceptance([{integration:'email',status:'passed'}],options).exitCode,1);
 const passed=[{integration:'email',status:'passed'},{integration:'payments',status:'passed'}];
 assert.equal(evaluateAcceptance(passed,options).complete,true);
 assert.equal(evaluateAcceptance(passed,options).exitCode,0);
 assert.equal(evaluateAcceptance([...passed,{integration:'ai',status:'failed'}],options).exitCode,1);
 for(const required of ['', 'email,email', 'emali'])assert.throws(()=>acceptanceOptions({ECC_ACCEPTANCE_REQUIRED:required}));
 assert.throws(()=>acceptanceOptions({ECC_ACCEPTANCE_STRICT:'tru'}));
});

test('read-only assessment stays explicit about incomplete acceptance without failing setup probes',()=>{
 const verdict=evaluateAcceptance([{integration:'email',status:'not_configured'}],{strict:false,required:['email']});
 assert.equal(verdict.exitCode,0);assert.equal(verdict.complete,false);assert.equal(verdict.state,'incomplete');
});

test('the real runner writes an incomplete strict report and sends no messages during assessment',async()=>{
 const filename=path.join(__dirname,'live-integrations.cjs'),realRequire=createRequire(filename),requests=[];
 let report,writeOptions;
 const processStub={env:{ECC_ACCEPTANCE_URL:'http://crm.test',ECC_ACCEPTANCE_EMAIL:'fixture@test.invalid',ECC_ACCEPTANCE_PASSWORD:'fixture-secret',ECC_ACCEPTANCE_REPORT:'fixture-report.json'},argv:['node',filename,'--strict'],exitCode:0};
 await new Promise((resolve,reject)=>{
  vm.runInNewContext(fs.readFileSync(filename,'utf8'),{
   require:name=>name==='node:fs'?{writeFileSync(_path,data,options){report=JSON.parse(data);writeOptions=options}}:realRequire(name),
   process:processStub,URL,AbortSignal,setTimeout,console:{log(){resolve()},error(message){if(message.startsWith('Acceptance setup failed'))reject(new Error(message))}},
   fetch:async(url,options)=>{
    requests.push({path:url.pathname,method:options.method});
    return{ok:true,headers:{getSetCookie:()=>[]},json:async()=>url.pathname==='/api/login'?{}:{integrations:['email','whatsapp','payments','ai'].map(id=>({id,state:'needs_configuration'}))}};
   },
  },{filename});
 });
 // console.log is synchronous; main sets exitCode before the promise resolves.
 assert.equal(processStub.exitCode,1);assert.equal(report.acceptance.complete,false);assert.equal(report.acceptance.mode,'strict');
 assert.equal(report.sendingEnabled,false);assert.ok(report.results.every(row=>row.status==='not_configured'));
 assert.deepEqual(requests,[{path:'/api/login',method:'POST'},{path:'/api/integrations/status',method:'GET'}]);
 assert.equal(writeOptions.mode,0o600);assert.ok(!JSON.stringify(report).includes('fixture-secret'));
});
