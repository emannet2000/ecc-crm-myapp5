'use strict';
(() => {
  const node = (tag, text, attrs = {}) => {
    const element = document.createElement(tag);
    if (text != null) element.textContent = String(text);
    for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, value);
    return element;
  };
  async function request(path, options = {}) {
    let response = await window.CRMAuthenticatedFetch(path, {credentials: 'same-origin', ...options});

    const out = await response.json();
    if (!response.ok) { const error=new Error((out.fields ? Object.values(out.fields).join(' ') : '') || out.error || 'Could not load lead work. Refresh and try again.');error.status=response.status;throw error; }
    return out;
  }
  class LeadWork extends HTMLElement {
    static get observedAttributes() { return ['record-id']; }
    constructor() { super(); this.attachShadow({mode: 'open'}); this.generation = 0; this.offset = 0; }
    connectedCallback() {
      this.changed = event => { if (!this.busy && !this.dirty && (!event.detail || event.detail === this.getAttribute('record-id'))) this.load(); };
      window.addEventListener('crm:record-changed', this.changed);
      this.load();
    }
    attributeChangedCallback() { if (this.isConnected) { this.offset = 0; this.load(); } }
    disconnectedCallback() { this.generation++; window.removeEventListener('crm:record-changed', this.changed); }
    async load() {
      const generation = ++this.generation, id = this.getAttribute('record-id');
      const root = node('section', null, {class: 'tools'}), notice = node('p', 'Loading lead work…', {role: 'status', 'aria-live': 'polite'});
      this.shadowRoot.replaceChildren(node('link', null, {rel: 'stylesheet', href: '/public/center.css'}), node('link', null, {rel: 'stylesheet', href: '/public/components.css'}), root);
      const refresh = node('button', 'Refresh lead work', {type: 'button', class: 'secondary'}); refresh.onclick = () => {if(!this.dirty||confirm('Discard the unsaved draft and reload this lead?'))this.load()};
      root.append(node('h2', 'Next action and activity'), refresh, notice);
      try {
        const [detail, timeline, staff] = await Promise.all([request('/api/records/leads/' + encodeURIComponent(id)), request('/api/leads/' + encodeURIComponent(id) + '/timeline?limit=25&offset=' + this.offset),request('/api/staff-options?'+new URLSearchParams({entity:'leads',id}))]);
        if (!this.isConnected || generation !== this.generation) return;
        notice.textContent = '';
        let lead = detail.record;this.dirty=false;
        root.append(node('p', 'Responsible consultant: ' + ((staff.staff||[]).find(person=>person.id===lead.assignedTo)?.name || lead.assignedTo || timeline.owner || 'Unassigned') + ' · Follow-up: ' + (lead.followUpDate || 'Not set')), node('p', 'Next action: ' + (lead.nextAction || 'Set the next staff action')));
        const submit = async (form, url, data, method) => {
          if (this.busy) return;
          this.busy = true;
          const buttons = [...root.querySelectorAll('button')]; buttons.forEach(button => { button.disabled = true; });
          try {
            const result = await request(url, {method, headers: {'Content-Type': 'application/json', 'If-Match': lead._revision}, body: JSON.stringify(data)});
            if (!this.isConnected || generation !== this.generation) return;
            window.CRMSessionDrafts?.saved?.(form,result);
            this.offset = 0;
            window.dispatchEvent(new CustomEvent('crm:record-changed', {detail: id}));
            this.load();
          } catch (error) { if (generation === this.generation){notice.textContent=error.message+' Your draft has been kept.';if(error.status===409||error.status===428){const recovery=node('button','Load current version and keep draft',{type:'button',class:'secondary'});recovery.onclick=async()=>{try{const latest=await request('/api/records/leads/'+encodeURIComponent(id));if(generation!==this.generation)return;lead=latest.record;notice.textContent='Current saved next action: '+(lead.nextAction||'Not set')+' · Status: '+lead.status+'. Your draft is kept. Compare it before saving again.';recovery.remove()}catch(e){notice.textContent=e.message+' Your draft has been kept.'}};notice.append(recovery)}} }
          finally { this.busy = false; buttons.forEach(button => { button.disabled = false; }); }
        };
        if (detail.editable) {
          const form = node('form', null, {class: 'card'}), fields = node('div', null, {class: 'fields'});
          for (const [key, label, type] of [['nextAction', 'Next staff action', 'text'], ['assignedTo', 'Responsible consultant', 'select'], ['followUpDate', 'Follow-up date', 'date'], ['status', 'Lead status', 'select']]) {
            const labelNode = node('label', label), input = node(type === 'select' ? 'select' : 'input', null, {name: key, ...(type === 'select' ? {} : {type})});
            if(key==='assignedTo'){input.append(node('option','Unassigned',{value:''}));for(const person of staff.staff||[])input.append(node('option',person.name+' · '+person.id,{value:person.id}));if(lead.assignedTo&&!(staff.staff||[]).some(p=>p.id===lead.assignedTo))input.append(node('option',lead.assignedTo+' (existing assignment)',{value:lead.assignedTo}));}
            if(key==='status')for(const status of lead.status==='Converted'?['Converted']:['New','Contacted','Qualified','Consultation Booked','Proposal Sent','Closed/Lost'])input.append(node('option',status,{value:status}));
            input.value = lead[key] || '';
            if (key === 'nextAction') { input.required = true; input.maxLength = 1000; }
            labelNode.append(input); fields.append(labelNode);
          }
          form.oninput=()=>{this.dirty=true};
          form.append(node('h3', 'Follow-up plan'), fields, node('button', 'Save next action', {type: 'submit'}));
          form.onsubmit = event => { event.preventDefault(); submit(form, '/api/leads/' + encodeURIComponent(id), {...lead, ...Object.fromEntries(new FormData(form)), duplicateConfirmed: false}, 'PUT'); };
          root.append(form);
          const log = node('form', null, {class: 'card'}), kindLabel = node('label', 'Activity type'), kind = node('select', null, {name: 'kind'});
          for (const value of ['call', 'message', 'note']) kind.append(node('option', value, {value})); kindLabel.append(kind);
          const bodyLabel = node('label', 'What happened?'), body = node('textarea', null, {name: 'body', required: '', maxlength: '4000', rows: '3'}); bodyLabel.append(body);
          const followLabel = node('label', 'This was an actual client follow-up'), follow = node('input', null, {type: 'checkbox', name: 'followUp'}); followLabel.append(follow);
          kind.onchange = () => { follow.disabled = kind.value === 'note'; if (follow.disabled) follow.checked = false; };
          log.append(node('h3', 'Log a call, message or note'), node('p', 'Record activity already performed. Logging a message does not send it. Only calls or messages explicitly marked as a follow-up contribute to first-follow-up reporting.'), kindLabel, bodyLabel, followLabel, node('button', 'Log activity', {type: 'submit'}));
          log.oninput=()=>{this.dirty=true};
          log.onsubmit = event => { event.preventDefault(); submit(log, '/api/leads/' + encodeURIComponent(id) + '/timeline', {kind: kind.value, body: body.value, followUp: follow.checked}, 'POST'); };
          root.append(log);
        }
        root.append(node('crm-followup-templates',null,{name:lead.name,'next-action':lead.nextAction||'','follow-up-date':lead.followUpDate||''}));
        root.append(node('h3', 'Lead activity timeline'));
        if (!timeline.events.length) root.append(node('p', 'No activity recorded yet.'));
        for (const event of timeline.events) {
          const card = node('article', null, {class: 'card'});
          card.append(node('strong', event.title), node('p', event.body));
          if (event.actor || event.at) card.append(node('small', [event.actor, event.at ? new Date(event.at).toLocaleString() : ''].filter(Boolean).join(' · ')));
          if (event.followUp) card.append(node('p', 'Recorded client follow-up'));
          root.append(card);
        }
        const pagination = node('div', null, {class: 'actions'});
        pagination.append(node('span', timeline.total + ' events'));
        for (const [text, offset, enabled] of [['Previous activities', this.offset - 25, this.offset > 0], ['Next activities', this.offset + 25, this.offset + 25 < timeline.total]]) if (enabled) {
          const button = node('button', text, {type: 'button', class: 'secondary'}); button.onclick = () => { this.offset = offset; this.load(); }; pagination.append(button);
        }
        root.append(pagination);
      } catch (error) { if (generation === this.generation) notice.textContent = error.message; }
    }
  }
  customElements.define('crm-lead-work', LeadWork);
})();
