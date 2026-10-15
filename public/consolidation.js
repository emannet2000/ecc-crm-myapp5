'use strict';
(() => {
  const node = (tag, text, attrs = {}) => {
    const element = document.createElement(tag);
    if (text != null) element.textContent = String(text);
    for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, value);
    return element;
  };
  const button = (text, run) => {
    const element = node('button', text, {type: 'button', class: 'secondary'});
    element.onclick = run;
    return element;
  };
  const choice = (label, options) => {
    const select = node('select', null, {'aria-label': label});
    for (const [value, text] of options) select.append(node('option', text, {value}));
    return select;
  };
  function pages(host, offset, total, load) {
    const bar = node('div', null, {class: 'actions', 'aria-label': 'Pagination'});
    const previous = button('Previous', () => load(offset - 25));
    const next = button('Next', () => load(offset + 25));
    previous.disabled = offset === 0;
    next.disabled = offset + 25 >= total;
    bar.append(previous, node('span', `${total} items · Page ${Math.floor(offset / 25) + 1}`), next);
    host.append(bar);
  }
  function labeled(form, label, input) {
    const wrapper = node('label', label);
    wrapper.append(input);
    form.append(wrapper);
    return input;
  }
  function communication(main, options) {
    const {request, context, features, editable, manager, portalTools} = options;
    const section = node('section', null, {class: 'communication-workspace'});
    const notice = node('p', '', {role: 'status', 'aria-live': 'polite'});
    const toolbar = node('form', null, {class: 'toolbar'});
    const search = node('input', null, {type: 'search', placeholder: 'Search messages or client names', 'aria-label': 'Search communication'});
    const channel = choice('Communication channel', [['', 'All channels'], ['email', 'Email'], ['whatsapp', 'WhatsApp'], ['portal', 'Client portal']]);
    const mode = choice('Message scope', [['', 'All accessible messages'], ...(manager ? [['unmatched', 'Unmatched messages']] : [])]);
    if (options.unmatched && manager) mode.value = 'unmatched';
    if (options.channel) channel.value = options.channel;
    const handling=choice('Handling filter',[['','All handling states'],['needs_reply','Needs reply'],['assigned','Assigned'],['resolved','Resolved']]);
 const assigned=choice('Assignment filter',[['','All assignments'],['me','Assigned to me']]);
 handling.value=options.handling||'';
 toolbar.append(search, channel, mode, handling, assigned, button('Refresh messages', () => load(0)));
    section.append(node('h2', 'Communication'), node('p', 'Email, WhatsApp and client portal responses in one history. Delivery status remains specific to each channel.'), toolbar, notice);
    main.append(section);
    let contact = context.contact, generation = 0;
    const history = node('div');
    const composer = node('details');
    composer.append(node('summary', 'Write to a client'));
    section.append(composer, history);

    function compose() {
      composer.querySelector('form')?.remove();
      const form = node('form', null, {class: 'communication-compose'});
      const picker = node('crm-record-picker', null, {entity: 'contacts', name: 'contactId', 'aria-label': 'Client', label: 'Client'});
      if (contact) { picker.value = contact.id; picker.setAttribute('label', contact.name || 'Client'); }
      labeled(form, 'Client', picker);
      const recipient = labeled(form, 'Recipient email', node('input', null, {name: 'recipient', type: 'email'}));
      recipient.value = contact?.email || '';
      const sendChannel = labeled(form, 'Send using', choice('Send using', [...(features.smtp ? [['email', 'Email']] : []), ...(features.whatsapp ? [['whatsapp', 'WhatsApp']] : [])]));
      const subject = labeled(form, 'Subject', node('input', null, {name: 'subject', maxlength: '200'}));
      const body = labeled(form, 'Message', node('textarea', null, {name: 'body', required: '', maxlength: '100000', rows: '5'}));
      const message = node('p', '', {role: 'status'});
      const send = node('button', 'Queue message', {type: 'submit'});
      send.disabled = !editable || (!features.smtp && !features.whatsapp);
      if (!editable) message.textContent = 'Your access is read-only.';
      else if (!features.smtp && !features.whatsapp) message.textContent = 'Sending is unavailable until an administrator connects email or WhatsApp in Integrations.';
      const updateChannel = () => {
        const email = sendChannel.value === 'email';
        recipient.disabled = subject.disabled = !email;
        recipient.required = subject.required = email;
      };
      sendChannel.onchange = updateChannel;
      updateChannel();
      let selecting = 0;
      picker.addEventListener('change', async () => {
        const current = ++selecting;
        try {
          const out = await request('/api/records/contacts/' + encodeURIComponent(picker.value));
          if (!form.isConnected || current !== selecting) return;
          contact = out.record;
          recipient.value = contact.email || '';
        } catch (error) { if (form.isConnected) message.textContent = error.message; }
      });
      form.append(message, send);
      form.oninput = () => { section.dataset.dirty = String(!!body.value || !!subject.value); };
      form.onsubmit = async event => {
        event.preventDefault();
        if (send.disabled || !form.reportValidity()) return;
        if (!picker.value) { message.textContent = 'Choose a client.'; return; }
        send.disabled = true;
        try {
          const email = sendChannel.value === 'email';
          const result = await request(email ? '/api/mail' : '/api/contacts/' + encodeURIComponent(picker.value) + '/whatsapp', {
            method: 'POST', headers: {'Content-Type': 'application/json'},
            body: JSON.stringify(email ? {contactId: picker.value, recipient: recipient.value, subject: subject.value, body: body.value} : {body: body.value})
          });
          if (!form.isConnected) return;
          body.value = ''; section.dataset.dirty = 'false';
          message.textContent = result.message || 'Message queued. Check its delivery status below.';
          load(0);
        } catch (error) { if (form.isConnected) message.textContent = error.message + ' Your message is kept.'; }
        finally { if (form.isConnected) send.disabled = !editable; }
      };
      composer.append(form);
      window.crmFollowupTemplates?.attach(form, () => ({name: contact?.name || ''}));
    }
    compose();
    if (portalTools) {
      const access = node('details');
      access.append(node('summary', 'Client portal access'));
      section.append(access);
      portalTools(access);
    }
    const invoices = node('details');
    invoices.append(node('summary', 'Send an invoice PDF'));
    if (editable && features.smtp) {
      const form = node('form'), picker = node('crm-record-picker', null, {entity: 'invoices', label: 'Invoice', name: 'invoiceId'});
      labeled(form, 'Invoice', picker);
      const send = node('button', 'Queue invoice', {type: 'submit'}), message = node('p', '', {role: 'status'});
      form.append(send, message);
      form.onsubmit = async event => {
        event.preventDefault(); if (send.disabled) return;
        if (!picker.value) { message.textContent = 'Choose an invoice.'; return; }
        send.disabled = true;
        try { await request('/api/invoices/' + encodeURIComponent(picker.value) + '/email', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'}); message.textContent = 'Invoice queued.'; load(0); }
        catch (error) { message.textContent = error.message; }
        finally { send.disabled = false; }
      };
      invoices.append(form);
    } else invoices.append(node('p', 'Invoice sending requires edit access and configured email.'));
    section.append(invoices);
    if (manager) {
      const sync = node('details'), status = node('p', 'Loading inbox connection…', {role: 'status'});
      sync.append(node('summary', 'Inbox connection'), status); section.append(sync);
      request('/api/mail/sync-status').then(out => { if (sync.isConnected) status.textContent = 'Microsoft inbox: ' + out.status + (out.detail ? ' · ' + out.detail : ''); })
        .catch(error => { if (sync.isConnected) status.textContent = error.message; });
    }

    async function load(offset) {
      const current = ++generation;
      notice.textContent = 'Loading communication…';
      const query = new URLSearchParams({limit: '25', offset: String(offset), q: search.value, channel: channel.value});
      query.set('handling',handling.value);query.set('assigned',assigned.value);
      if (mode.value === 'unmatched') query.set('unmatched', 'true');
      if (context.entity === 'cases') query.set('caseId', context.id);
      else if (context.entity === 'students') query.set('studentId', context.id);
      else if (context.entity === 'invoices') query.set('invoiceId', context.id);
      else if (context.contact) query.set('contactId', context.contact.id);
      try {
        const out = await request('/api/communication?' + query);
        if (!section.isConnected || current !== generation) return;
        history.replaceChildren();
        for (const row of out.messages || []) {
          const card = node('article', null, {class: 'card'});
          card.append(node('h3', row.subject || 'Message'), node('p', `${row.channel} · ${row.direction} · ${row.createdAt}`), node('p', row.body, {class: 'message-body'}), node('p', row.deliveryExplanation || row.status));
          if (row.recipient) card.append(node('p', 'To: ' + row.recipient));
          if (row.lastError) card.append(node('p', row.lastError));
          if (row.recordRoute?.startsWith('/') && !row.recordRoute.startsWith('//')) card.append(node('a', row.linkedRecord || 'Open record', {href: row.recordRoute}));
          if (row.unmatched && manager) {
            const form = node('form'), picker = node('crm-record-picker', null, {entity: 'contacts', label: 'Attach to client'});
            labeled(form, 'Attach to client', picker);
            const save = node('button', 'Attach message', {type: 'submit'}), status = node('p', '', {role: 'status'});
            form.append(save, status);
            form.onsubmit = async event => {
              event.preventDefault(); if (save.disabled || !picker.value) return;
              save.disabled = true;
              try { await request('/api/inbound/unmatched/' + encodeURIComponent(row.id) + '/link', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({contactId: picker.value})}); load(offset); }
              catch (error) { status.textContent = error.message; save.disabled = false; }
            };
            card.append(form);
          }
          if (row.canRetry && editable) card.append(button('Retry email', async event => {
            event.target.disabled = true;
            try { await request('/api/mail/' + encodeURIComponent(row.id.replace(/^mail:/, '')) + '/retry', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'}); load(offset); }
            catch (error) { notice.textContent = error.message; event.target.disabled = false; }
          }));
          window.CRMEveryday?.handling(card,row,{request,editable},()=>load(offset));
          history.append(card);
        }
        if (!(out.messages || []).length) history.append(node('p', 'No messages match these filters.'));
        pages(history, offset, out.total || 0, load);
        notice.textContent = `${out.total || 0} accessible messages`;
      } catch (error) { if (section.isConnected && current === generation) notice.textContent = error.message + ' Use Refresh messages to retry.'; }
    }
    toolbar.onsubmit = event => { event.preventDefault(); load(0); };
    channel.onchange = mode.onchange = handling.onchange = assigned.onchange = () => load(0);
    search.onchange = () => load(0);
    load(0);
  }

  function calendar(main, {request, timezone = 'UTC',editable=true}) {
    const section = node('section'), toolbar = node('form', null, {class: 'toolbar'}), notice = node('p', '', {role: 'status'}), results = node('div');
    const month = node('input', null, {type: 'month', 'aria-label': 'Calendar month', required: ''});
    const parts = new Intl.DateTimeFormat('en-US', {timeZone: timezone, year: 'numeric', month: '2-digit'}).formatToParts(new Date());
    month.value = parts.find(part => part.type === 'year').value + '-' + parts.find(part => part.type === 'month').value;
    const kind = choice('Calendar event type', [['', 'All events'], ['task', 'Tasks'], ['application', 'Application deadlines'], ['followup', 'Lead follow-ups'], ['consultation', 'Consultations'], ['document', 'Document deadlines'], ['expiry', 'Document expiry'], ['invoice', 'Invoice due dates'], ['student', 'Student next actions'], ['travel', 'Travel']]);
    const move = amount => {
      const [year, current] = month.value.split('-').map(Number), date = new Date(year, current - 1 + amount, 1);
      month.value = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`; load(0);
    };
    toolbar.append(button('Previous month', () => move(-1)), month, button('Next month', () => move(1)), kind, button('Refresh calendar', () => load(0)));
    section.append(node('h2', 'Calendar'), node('p', 'Tasks, deadlines and recorded consultations together. Open the source record to make changes.'), toolbar, notice, results); main.append(section);
    window.CRMEveryday?.consultations(section,{request,editable},()=>load(0));
    let generation = 0;
    async function load(offset) {
      if (!/^\d{4}-\d{2}$/.test(month.value)) return;
      const current = ++generation, [year, index] = month.value.split('-').map(Number);
      const last = new Date(year, index, 0).getDate();
      const query = new URLSearchParams({from: month.value + '-01', to: month.value + '-' + last, kind: kind.value, limit: '25', offset: String(offset)});
      notice.textContent = 'Loading calendar…';
      try {
        const out = await request('/api/workspace-calendar?' + query);
        if (!section.isConnected || current !== generation) return;
        results.replaceChildren();
        for (const row of out.events || []) {
          const card = node('article', null, {class: 'card'});
          const time = row.occurredAt ? new Date(row.occurredAt).toLocaleTimeString(undefined, {timeZone: out.timezone, hour: '2-digit', minute: '2-digit'}) : '';
          card.append(node('h3', row.title), node('p', `${row.date}${time ? ' · ' + time : ''} · ${row.kind} · ${row.status || ''}`), node('a', 'Open source record', {href: row.route})); if(row.kind==='consultation')window.CRMEveryday?.consultations(card,{request,editable},()=>load(offset),row);results.append(card);
        }
        if (!(out.events || []).length) results.append(node('p', 'No events in this month match the selected type.'));
        pages(results, offset, out.total || 0, load);
        notice.textContent = `${out.total || 0} events · Times use ${out.timezone}`;
      } catch (error) { if (section.isConnected && current === generation) notice.textContent = error.message + ' Use Refresh calendar to retry.'; }
    }
    toolbar.onsubmit = event => { event.preventDefault(); load(0); };
    month.onchange = kind.onchange = () => load(0); load(0);
  }

  function directory(main, {request}) {
    const section = node('section'), toolbar = node('form', null, {class: 'toolbar'}), results = node('div'), notice = node('p', '', {role: 'status'});
    const search = node('input', null, {type: 'search', 'aria-label': 'Search agents and partners', placeholder: 'Name, contact or agent code'});
    const type = choice('Directory type', [['', 'Agents and partners'], ['agents', 'Agents'], ['partners', 'Partners']]);
    toolbar.append(search, type, button('Search directory', () => load(0)));
    const links = node('nav', null, {class: 'links', 'aria-label': 'Directory record types'});
    links.append(node('a', 'Manage agents', {href: '/agents'}), node('a', 'Manage partners', {href: '/partners'}));
    section.append(node('h2', 'Agents & partners'), node('p', 'A combined directory. Each record retains its own commission, agreement and payout history.'), toolbar, links, notice, results); main.append(section);
    let generation = 0;
    async function load(offset) {
      const current = ++generation; notice.textContent = 'Loading directory…';
      try {
        const out = await request('/api/referral-directory?' + new URLSearchParams({q: search.value, entity: type.value, limit: '25', offset: String(offset)}));
        if (!section.isConnected || current !== generation) return;
        results.replaceChildren();
        for (const row of out.items || []) {
          const card = node('article', null, {class: 'card'});
          card.append(node('h3', row.name), node('p', `${row.type} · ${row.status || 'Contract status not set'}`));
          if (row.commissionRate != null) card.append(node('p', 'Commission rate: ' + row.commissionRate + '%'));
          if (row.agreementExpiry) card.append(node('p', `Agreement: ${row.agreementStart || 'Start not set'} → ${row.agreementExpiry}`));
          card.append(node('a', 'Open ' + (row.entity === 'agents' ? 'agent' : 'partner'), {href: row.route})); results.append(card);
        }
        if (!(out.items || []).length) results.append(node('p', 'No agents or partners match this search.'));
        pages(results, offset, out.total || 0, load); notice.textContent = `${out.total || 0} accessible records`;
      } catch (error) { if (section.isConnected && current === generation) notice.textContent = error.message; }
    }
    toolbar.onsubmit = event => { event.preventDefault(); load(0); };
    type.onchange = () => load(0); load(0);
  }

  function bulkContacts({request, tell}) {
    const card = node('section', null, {class: 'card'}), toolbar = node('form', null, {class: 'toolbar'}), results = node('div'), selectedList = node('div'), reviewList = node('div'), notice = node('p', '', {role: 'status'});
    const search = node('input', null, {type: 'search', 'aria-label': 'Search contacts to update', placeholder: 'Search name, email or company'});
    const stage = choice('New contact stage', [['Lead', 'Lead'], ['Prospect', 'Prospect'], ['Client', 'Client'], ['Customer', 'Customer']]);
    const selected = new Map(); let preview = null, generation = 0, reviewing = false, saving = false;
    const review = button('Review selected contacts', () => prepare());
    const save = button('Update reviewed contacts', () => submit()); save.disabled = review.disabled = true;
    function invalidate() { preview = null; save.disabled = true; reviewList.replaceChildren(); }
    function selection() {
      card.dataset.dirty = String(!!selected.size);
      selectedList.replaceChildren(node('h3', `${selected.size} selected contacts`));
      for (const [id, row] of selected) selectedList.append(button('Remove ' + row.name, () => { selected.delete(id); invalidate(); selection(); load(0); }));
      review.disabled = !selected.size || reviewing || saving;
    }
    toolbar.append(search, button('Search contacts', () => load(0)));
    card.append(node('h2', 'Bulk contact update'), node('p', 'Select up to 500 contacts across search pages, then review their current details before saving. A changed record rejects the whole update.'), toolbar, notice, results, selectedList);
    const form = node('form'); labeled(form, 'New stage', stage); form.append(review, reviewList, save); card.append(form);
    stage.onchange = invalidate;
    async function load(offset) {
      const current = ++generation; notice.textContent = 'Searching contacts…';
      try {
        const out = await request('/api/contacts?' + new URLSearchParams({q: search.value, limit: '25', offset: String(offset), sort: 'name'}));
        if (!card.isConnected || current !== generation) return;
        results.replaceChildren();
        for (const row of out.contacts || []) {
          const label = node('label', `${row.name} · ${row.email || 'No email'} · ${row.stage || ''}`, {class: 'bulk-contact-choice'});
          const checkbox = node('input', null, {type: 'checkbox', 'aria-label': 'Select ' + row.name}); checkbox.checked = selected.has(row.id);
          checkbox.disabled = saving || reviewing;
          checkbox.onchange = () => {
            if (checkbox.checked && selected.size >= 500) { checkbox.checked = false; notice.textContent = 'Select up to 500 contacts.'; return; }
            if (checkbox.checked) selected.set(row.id, row); else selected.delete(row.id);
            invalidate(); selection();
          };
          label.prepend(checkbox); results.append(label);
        }
        if (!(out.contacts || []).length) results.append(node('p', 'No contacts match this search.'));
        pages(results, offset, out.total || 0, load); notice.textContent = `${out.total || 0} matching contacts`;
      } catch (error) { if (card.isConnected && current === generation) notice.textContent = error.message; }
    }
    async function prepare() {
      if (reviewing || saving || !selected.size) return;
      reviewing = true; review.disabled = true; invalidate();
      const ids = [...selected.keys()], reviewedStage = stage.value;
      try {
        const revisions = {}, rows = [];
        for (const id of ids) {
          const out = await request('/api/records/contacts/' + encodeURIComponent(id));
          if (!card.isConnected) return;
          if (!out.editable) throw new Error('You cannot edit ' + (out.record.name || 'a selected contact') + '. Remove it from your selection.');
          if (!out.record._revision) throw new Error('Could not load the saved version. Review again.');
          revisions[id] = out.record._revision; rows.push(out.record);
        }
        if (ids.join('|') !== [...selected.keys()].join('|') || stage.value !== reviewedStage) throw new Error('Selection or stage changed. Review again.');
        preview = {revisions, stage: reviewedStage}; reviewList.replaceChildren(node('h3', 'Review: change ' + rows.length + ' contacts to ' + reviewedStage));
        for (const row of rows) reviewList.append(node('p', `${row.name} · ${row.email || 'No email'} · ${row.stage} → ${reviewedStage}`));
        save.disabled = false;
      } catch (error) { if (card.isConnected) notice.textContent = error.message; }
      finally { reviewing = false; if (card.isConnected) selection(); }
    }
    async function submit() {
      if (!preview || saving || preview.stage !== stage.value) return;
      saving = true; save.disabled = review.disabled = true;
      try {
        await request('/api/contacts/bulk', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ids: Object.keys(preview.revisions), stage: preview.stage, revisions: preview.revisions})});
        if (!card.isConnected) return;
        selected.clear(); invalidate(); selection(); load(0); tell('Contacts updated.');
        window.dispatchEvent(new CustomEvent('crm:record-changed'));
      } catch (error) { if (card.isConnected) { invalidate(); notice.textContent = error.message + ' Selection is kept. Review current versions before retrying.'; } }
      finally { saving = false; if (card.isConnected) selection(); }
    }
    toolbar.onsubmit = event => { event.preventDefault(); load(0); };
    form.onsubmit = event => event.preventDefault();
    selection(); Promise.resolve().then(() => { if (card.isConnected) load(0); }); return card;
  }
  window.CRMConsolidation = {communication, calendar, directory, bulkContacts};
})();
