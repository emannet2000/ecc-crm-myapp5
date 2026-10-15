'use strict';
(()=>{
 const make=(tag,text,attrs={})=>{const element=document.createElement(tag);if(text!=null)element.textContent=String(text);for(const[k,v]of Object.entries(attrs))element.setAttribute(k,v);return element};
 class AssignmentReview extends HTMLElement{
  constructor(){super();this.attachShadow({mode:'open'});this.generation=0;this.offset=0}
  connectedCallback(){this.load()}
  disconnectedCallback(){this.generation++}
  async request(path,options={}){const response=await window.CRMAuthenticatedFetch(path,{credentials:'same-origin',...options});const out=await response.json();if(!response.ok)throw new Error(out.error||'Could not save mapping. Your selection is kept.');return out}
  async load(){const generation=++this.generation;this.shadowRoot.replaceChildren(make('link',null,{rel:'stylesheet',href:'/public/center.css'}),make('link',null,{rel:'stylesheet',href:'/public/components.css'}));
   const root=make('section',null,{class:'tools'}),notice=make('p','Loading historical assignments…',{role:'status','aria-live':'polite'}),refresh=make('button','Refresh assignment review',{type:'button',class:'secondary'});refresh.onclick=()=>this.load();
   root.append(make('h2','Historical staff assignments'),make('p','Review each old name or unavailable account. A suggestion is an exact, unique name match, not an automatic change. Mappings preserve record ownership and access; use application handoffs when transferring responsibility.'),refresh,notice);this.shadowRoot.append(root);
   try{const out=await this.request('/api/assignments/review?'+new URLSearchParams({limit:'25',offset:String(this.offset)}));if(!this.isConnected||generation!==this.generation)return;notice.textContent=out.total+' assignments need review';
    if(!out.items.length)root.append(make('p','No historical assignments in this view.'));
    for(const item of out.items){const form=make('form',null,{class:'card'});form.append(make('a',item.label,{href:item.route}),make('p',item.entity+' · Existing assignment: '+item.previous));
     if(!item.editable){form.append(make('p','An authorized record owner or manager must review this mapping.'));root.append(form);continue}
     const label=make('label','Correct staff account'),select=make('select',null,{required:'',name:'staffId'});select.append(make('option','Choose the staff account',{value:''}));for(const person of item.staff)select.append(make('option',person.name+' · '+person.id,{value:person.id}));select.value=item.suggestedId||'';label.append(select);
     const confirmed=make('input',null,{type:'checkbox',name:'confirmed',required:''}),confirmation=make('label','I reviewed this record and confirmed this is the same person.');confirmation.prepend(confirmed);const save=make('button','Save reviewed mapping',{type:'submit'}),status=make('p',null,{role:'status'});
     form.append(make('p',item.suggestedId?'One exact name match suggested. Confirm it before saving.':'No unique exact match. Review the record and choose the correct account.'),label,confirmation,save,status);
     form.onsubmit=async event=>{event.preventDefault();if(save.disabled)return;save.disabled=true;try{await this.request('/api/assignments/'+item.entity+'/'+encodeURIComponent(item.id),{method:'PATCH',headers:{'Content-Type':'application/json','If-Match':item.revision},body:JSON.stringify({staffId:select.value,confirmed:confirmed.checked})});if(generation!==this.generation)return;window.CRMSessionDrafts?.saved?.(form);form.replaceChildren(make('p','Mapped to '+select.selectedOptions[0].textContent+'; record ownership was preserved.'),make('a','Open record',{href:item.route}));window.dispatchEvent(new CustomEvent('crm:record-changed',{detail:item.id}));}catch(error){status.textContent=error.message+' Your selection is kept. A changed assignment requires refreshing this review.'}finally{save.disabled=false}};root.append(form);
    }
    const pager=make('div',null,{class:'actions'});for(const[label,next,enabled]of [['Previous assignments',this.offset-25,this.offset>0],['Next assignments',this.offset+25,this.offset+25<out.total]])if(enabled){const button=make('button',label,{type:'button'});button.onclick=()=>{this.offset=next;this.load()};pager.append(button)}root.append(pager);
   }catch(error){if(generation===this.generation)notice.textContent=error.message}
  }
 }
 customElements.define('crm-assignment-review',AssignmentReview);
})();
