const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseHTML}=require('linkedom');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
async function mount(observations,canReviewAll){
 const {window}=parseHTML('<html><body></body></html>');
 Object.defineProperty(window.HTMLSelectElement.prototype,'value',{configurable:true,get(){return this.querySelector('option')?.getAttribute('value')||''}});
 const context=vm.createContext({window,document:window.document,HTMLElement:window.HTMLElement,customElements:window.customElements,FormData,fetch:async()=>({ok:true,json:async()=>({observations,canReviewAll})})});
 for (const file of ['session.js','usability.js']) vm.runInContext(fs.readFileSync(path.join(__dirname,'../public',file),'utf8'),context);
 const element=window.document.createElement('crm-usability');window.document.body.append(element);await new Promise(resolve=>setTimeout(resolve,0));return element;
}
const observation=(task,completed,neededHelp=false,errors=0,userId='staff-a')=>({userId,createdAt:'2026-10-11',data:JSON.stringify({role:task==='invoice-receipt'?'finance':'adviser',task,completed,neededHelp,errors,seconds:30,comments:'Observed obstacle'})});
test('manager review ranks incomplete tasks before help and errors and limits candidates to three',async()=>{
 const element=await mount([observation('daily-priority',true,true),observation('student-review',false),observation('invoice-receipt',true,false,2),observation('lead-intake',true,false,1),observation('application-handoff',true)],true);
 try{const cards=[...element.shadowRoot.querySelectorAll('.review-priority')];assert.equal(cards.length,3);assert.ok(cards[0].textContent.includes('Find a student'));assert.ok(cards[1].textContent.includes('most urgent application'));assert.ok(cards[2].textContent.includes('create its invoice'));assert.ok(element.shadowRoot.querySelector(".tools").textContent.includes('Run the two staff sessions'));assert.ok(element.shadowRoot.querySelector(".tools").textContent.includes('candidates for review'));}finally{element.remove()}
});
test('review does not fabricate problems without observations or expose manager summaries to staff',async()=>{
 const empty=await mount([],true);try{assert.equal(empty.shadowRoot.querySelectorAll('.review-priority').length,0);assert.ok(empty.shadowRoot.querySelector(".tools").textContent.includes('No task failures'));}finally{empty.remove()}
 const member=await mount([observation('student-review',false)],false);try{assert.equal(member.shadowRoot.querySelectorAll('.review-priority').length,0);assert.ok(!member.shadowRoot.querySelector(".tools").textContent.includes('Three tasks to review first'));assert.ok(member.shadowRoot.querySelector(".tools").textContent.includes('Your observations'));}finally{member.remove()}
});
