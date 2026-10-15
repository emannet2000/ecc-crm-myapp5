'use strict';
(() => {
  let nextId=0;
  class RecordPicker extends HTMLElement {
    static formAssociated=true;
    static get observedAttributes(){return ['entity','value','label','disabled','required'];}
    get name(){return this.getAttribute('name')||'';}
    set name(value){this.setAttribute('name',value);}
    get required(){return this.hasAttribute('required');}
    set required(value){this.toggleAttribute('required',!!value);}
    constructor(){super();this.attachShadow({mode:'open'});this.internals=this.attachInternals?.();this.generation=0;this.offset=0;this.selected='';}
    get value(){return this.getAttribute('value')||'';}
    set value(value){this.setAttribute('value',value||'');}
    get disabled(){return this.hasAttribute('disabled');}
    set disabled(value){this.toggleAttribute('disabled',!!value);}
    connectedCallback(){this.mount();}
    disconnectedCallback(){clearTimeout(this.timer);this.searchRequest?.abort();this.generation++;}
    attributeChangedCallback(name){if(!this.isConnected)return;if(name==='entity')this.mount();else if(name==='value')this.hydrate();else if(name==='label')this.search?.setAttribute('aria-label',this.getAttribute('label')||'Find a record');else this.validity();}
    validity(){this.internals?.setFormValue(this.value);this.internals?.setValidity(this.hasAttribute('required')&&!this.value?{valueMissing:true}:{},this.value?'':'Choose a record',this.search);if(this.search)this.search.disabled=this.disabled;if(this.clear)this.clear.disabled=this.disabled;for(const button of this.paging?.querySelectorAll('button')||[])button.disabled=this.disabled;for(const button of this.results?.querySelectorAll('button')||[])button.disabled=this.disabled;}
    mount(){
      clearTimeout(this.timer);this.searchRequest?.abort();this.generation++;this.shadowRoot.replaceChildren();
      const make=(tag,text,attrs={})=>{const e=document.createElement(tag);if(text!=null)e.textContent=text;for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);return e};
      const style=make('style',`:host{display:block;min-width:0}input,button{font:inherit;box-sizing:border-box;min-height:44px;border:1px solid var(--border,#ccd3df);border-radius:8px;padding:9px;background:var(--surface,#fff);color:var(--text,#172132)}input{width:100%}button{cursor:pointer}button:focus-visible,input:focus-visible{outline:3px solid var(--accent,#3266dd);outline-offset:2px}.selected{display:flex;gap:8px;align-items:center;overflow-wrap:anywhere;margin-bottom:8px}.selected span{flex:1}.results{display:grid;gap:6px;margin-top:8px;max-height:260px;overflow:auto}.results button{text-align:left}.paging{display:flex;gap:8px;margin-top:8px}.status{font-size:12px;color:var(--text-muted,#526078)}[hidden]{display:none}`);
      const listId='record-picker-'+(++nextId),selected=make('div',null,{class:'selected'});this.caption=make('span','No record selected');this.clear=make('button','Clear',{type:'button','aria-label':'Clear '+(this.getAttribute('label')||'record')});selected.append(this.caption,this.clear);
      this.search=make('input',null,{type:'search',placeholder:'Search all accessible records…','aria-label':this.getAttribute('label')||'Find a record','aria-controls':listId,'aria-expanded':'false',autocomplete:'off'});
      this.status=make('p','',{class:'status',role:'status','aria-live':'polite'});this.results=make('div',null,{class:'results',id:listId});this.paging=make('div',null,{class:'paging'});
      this.shadowRoot.append(style,selected,this.search,this.status,this.results,this.paging);this.validity();this.hydrate();
      this.clear.onclick=()=>this.choose('','No record selected');
      this.search.oninput=()=>{clearTimeout(this.timer);this.searchRequest?.abort();this.generation++;this.offset=0;this.timer=setTimeout(()=>this.load(),250)};
      this.search.onfocus=()=>{if(!this.results.children.length)this.load()};
      this.search.onkeydown=event=>{if(event.key==='ArrowDown'){event.preventDefault();this.results.querySelector('button')?.focus()}if(event.key==='Escape'){this.results.replaceChildren();this.paging.replaceChildren();this.search.setAttribute('aria-expanded','false')}};
      this.results.onkeydown=event=>{const buttons=[...this.results.querySelectorAll('button')],i=buttons.indexOf(this.shadowRoot.activeElement);if(['ArrowDown','ArrowUp','Escape'].includes(event.key)){event.preventDefault();if(event.key==='Escape')this.search.focus();else (buttons[i+(event.key==='ArrowDown'?1:-1)]||this.search).focus()}};
    }
    async get(url,signal){const response=await window.CRMAuthenticatedFetch(url,{credentials:'same-origin',signal});const out=await response.json();if(!response.ok)throw new Error(out.error||'Could not load records. Try again.');return out;}
    label(record){const main=record.name||record.legalCompanyName||record.docName||record.reference||record.caseNumber||record.invoiceNumber||record.title||record.id;const detail=record.email||record.studentCode||record.clientName||record.program||'';return main+(detail?' · '+detail:'')+' · '+record.id;}
    choose(id,label){if(this.disabled)return;clearTimeout(this.timer);this.searchRequest?.abort();this.generation++;this.value=id;this.caption.textContent=label;this.search.value='';this.results.replaceChildren();this.paging.replaceChildren();this.status.textContent='';this.search.setAttribute('aria-expanded','false');this.dispatchEvent(new Event('input',{bubbles:true,composed:true}));this.dispatchEvent(new Event('change',{bubbles:true,composed:true}));this.search.focus();}
    async hydrate(){this.validity();const value=this.value,entity=this.getAttribute('entity');if(!value){this.caption.textContent='No record selected';return}this.caption.textContent='Selected record: '+value;try{const out=await this.get('/api/'+entity+'/'+encodeURIComponent(value));if(this.isConnected&&this.value===value&&this.getAttribute('entity')===entity){const record=Object.values(out).find(v=>v&&typeof v==='object'&&v.id===value);if(record)this.caption.textContent=this.label(record)}}catch(error){if(this.value===value)this.status.textContent=error.message+' The selection has been kept.'}}
    async load(){this.searchRequest?.abort();const controller=new AbortController();this.searchRequest=controller;const generation=++this.generation,entity=this.getAttribute('entity');if(!['contacts','students','cases','invoices','partners','agents','schools','documents','deals','leads','tasks','activities','payments'].includes(entity))return;this.status.textContent='Searching…';this.results.replaceChildren();this.paging.replaceChildren();try{const out=await this.get('/api/'+entity+'?'+new URLSearchParams({q:this.search.value,limit:'20',offset:String(this.offset)}),controller.signal);if(!this.isConnected||generation!==this.generation)return;const records=out[entity]||[];this.status.textContent=records.length?`${this.offset+1}–${Math.min(this.offset+20,out.total)} of ${out.total} accessible records`:'No matching accessible records.';for(const record of records){const button=document.createElement('button');button.type='button';button.disabled=this.disabled;button.textContent=this.label(record);button.onclick=()=>!this.disabled&&this.choose(record.id,this.label(record));this.results.append(button)}this.search.setAttribute('aria-expanded',String(records.length>0));for(const[label,offset,enabled]of [['Previous',this.offset-20,this.offset>0],['Next',this.offset+20,this.offset+20<out.total]])if(enabled){const button=document.createElement('button');button.type='button';button.textContent=label;button.disabled=this.disabled;button.onclick=()=>{if(this.disabled)return;this.offset=offset;this.load()};this.paging.append(button)}}catch(error){if(error.name==='AbortError'||!this.isConnected||generation!==this.generation)return;this.status.textContent=error.message;const retry=document.createElement('button');retry.type='button';retry.textContent='Retry search';retry.onclick=()=>this.load();this.paging.append(retry)}}
  }
  customElements.define('crm-record-picker',RecordPicker);
})();

(()=>{
 class StaffPicker extends HTMLElement{
  static get observedAttributes(){return ['value','disabled','entity','record-id']}
  constructor(){super();this.attachShadow({mode:'open'});this.people=[];this.generation=0}
  get value(){return this.getAttribute('value')||''}
  set value(value){this.setAttribute('value',value)}
  connectedCallback(){this.render();this.load()}
  disconnectedCallback(){this.generation++}
  attributeChangedCallback(name){if(!this.isConnected)return;if(name==='entity'||name==='record-id')this.load();else this.sync()}
  render(){this.shadowRoot.innerHTML='<style>:host{display:block}label{display:grid;gap:6px}select,button{font:inherit;color:inherit;background:var(--panel,#fff);min-height:44px;border:1px solid var(--border,#ccc);border-radius:8px;padding:8px}select:focus-visible,button:focus-visible{outline:3px solid var(--primary,#3266dd)}p{font-size:12px}[hidden]{display:none}</style><label><span></span><select></select></label><p role="status"></p><button type="button" hidden>Retry staff list</button>';this.select=this.shadowRoot.querySelector('select');this.notice=this.shadowRoot.querySelector('p');this.retry=this.shadowRoot.querySelector('button');this.shadowRoot.querySelector('span').textContent=this.getAttribute('label')||'Assigned staff';this.select.onchange=()=>{this.value=this.select.value;this.dispatchEvent(new Event('input',{bubbles:true,composed:true}))};this.retry.onclick=()=>this.load();this.sync()}
  sync(){if(!this.select)return;this.select.replaceChildren(new Option('Unassigned',''));for(const person of this.people)this.select.append(new Option(person.name+' · '+person.id,person.id));if(this.value&&!this.people.some(p=>p.id===this.value))this.select.append(new Option(this.value+' (existing assignment)',this.value));this.select.value=this.value;this.select.disabled=this.hasAttribute('disabled')||this.loading}
  async load(){if(!this.select)return;const generation=++this.generation;this.loading=true;this.sync();this.notice.textContent='Loading active staff…';this.retry.hidden=true;try{const query=new URLSearchParams({entity:this.getAttribute('entity')||'',id:this.getAttribute('record-id')||''});const response=await window.CRMAuthenticatedFetch('/api/staff-options?'+query,{credentials:'same-origin'});const out=await response.json();if(!response.ok)throw new Error(out.error||'Could not load staff');if(!this.isConnected||generation!==this.generation)return;this.people=out.staff||[];this.notice.textContent='Choose an active account. Existing assignments are kept until you change them.';}catch(error){if(generation===this.generation){this.notice.textContent=error.message+'. Your selection is kept.';this.retry.hidden=false}}finally{if(generation===this.generation){this.loading=false;this.sync()}}}
 }
 customElements.define('crm-staff-picker',StaffPicker);
})();

(()=>{
 let directory,directoryKey;
 const staff=()=>{const focus=document.querySelector('#workspace-navigation');const key=(focus?.getAttribute('data-org-id')||'')+':'+(focus?.getAttribute('data-user-id')||'');if(key!==directoryKey){directory=null;directoryKey=key}if(!directory)directory=window.CRMAuthenticatedFetch('/api/staff-directory',{credentials:'same-origin'}).then(async response=>{if(!response.ok)throw new Error('Staff directory unavailable');return (await response.json()).staff||[]}).catch(error=>{directory=null;throw error});return directory};
 window.addEventListener('crm:record-changed',()=>{directory=null});
 class StaffName extends HTMLElement{
  static get observedAttributes(){return ['value']}
  connectedCallback(){this.changed=()=>this.render();window.addEventListener('crm:record-changed',this.changed);this.render()}
  disconnectedCallback(){window.removeEventListener('crm:record-changed',this.changed)}
  attributeChangedCallback(){if(this.isConnected)this.render()}
  async render(){const value=this.getAttribute('value')||'';this.textContent=value||'Unassigned';try{const people=await staff();if(!this.isConnected||this.getAttribute('value')!==value)return;const person=people.find(p=>p.id===value);if(person)this.textContent=person.name+(person.disabled?' (inactive)':'');}catch{}}
 }
 class StaffFilter extends HTMLElement{
  static get observedAttributes(){return ['value','owners']}
  constructor(){super();this.attachShadow({mode:'open'});this.people=[]}
  get value(){return this.getAttribute('value')||''}
  connectedCallback(){this.shadowRoot.innerHTML='<style>select{font:inherit;min-height:44px;max-width:100%;color:inherit;background:var(--panel,#fff);border:1px solid var(--border,#ccc);border-radius:8px;padding:8px}</style><select aria-label="Owner filter"></select>';this.select=this.shadowRoot.querySelector('select');this.select.onchange=()=>{this.setAttribute('value',this.select.value);this.dispatchEvent(new Event('input',{bubbles:true,composed:true}))};this.render();staff().then(people=>{if(this.isConnected){this.people=people;this.render()}}).catch(()=>{})}
  attributeChangedCallback(){this.render()}
  render(){if(!this.select)return;let owners=[];try{owners=JSON.parse(this.getAttribute('owners')||'[]')}catch{}this.select.replaceChildren(new Option('All owners',''),new Option('My deals','__mine__'));for(const value of owners){const person=this.people.find(p=>p.id===value);this.select.append(new Option(person?person.name+(person.disabled?' (inactive)':''):value,value))}this.select.value=this.value}
 }
 customElements.define('crm-staff-filter',StaffFilter);
 customElements.define('crm-staff-name',StaffName);
})();
