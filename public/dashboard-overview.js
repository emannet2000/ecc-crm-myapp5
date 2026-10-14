'use strict';
// Operational overview for the home dashboard. Every figure comes from
// GET /api/dashboard/overview, which applies the same record visibility and
// assignment rules as My work today. Cards only select a filtered record list;
// they never change a record.
(function () {
  const node = (tag, text, attrs = {}) => {
    const element = document.createElement(tag);
    if (text !== undefined && text !== null) element.textContent = String(text);
    for (const [key, value] of Object.entries(attrs)) element.setAttribute(key, value);
    return element;
  };
  const style = root => {
    root.append(node('link', null, {rel: 'stylesheet', href: '/public/center.css'}));
    root.append(node('link', null, {rel: 'stylesheet', href: '/public/components.css'}));
    root.append(node('link', null, {rel: 'stylesheet', href: '/public/mobile-tables.css'}));
  };
  async function request(path, options = {}) {
    let response = await fetch(path, {credentials: 'same-origin', ...options});
    if (response.status === 401) {
      const refresh = await fetch('/api/session/refresh', {method: 'POST', credentials: 'same-origin'});
      if (refresh.ok) response = await fetch(path, {credentials: 'same-origin', ...options});
    }
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'The overview could not be loaded. Use Refresh overview to retry.');
    return result;
  }
  const money = (currency, amount) => `${currency} ${Number(amount || 0).toLocaleString(undefined, {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
  const panel = (title, note) => {
    const section = node('details', null, {class: 'dashboard-panel'});
    section.append(node('summary', title));
    if (note) section.append(node('p', note, {class: 'dashboard-note'}));
    return section;
  };
  const empty = text => node('p', text, {class: 'dashboard-note'});
  // Cells may be plain text or a ready-made element. The first cell of every row
  // becomes a row header so screen readers announce each figure with its label.
  const dataTable = (headers, rows, rowAttributes = []) => {
    const table = node('table', null, {class: 'dashboard-table'});
    const head = node('thead'), headRow = node('tr');
    for (const header of headers) headRow.append(node('th', header, {scope: 'col'}));
    head.append(headRow);
    const body = node('tbody');
    rows.forEach((cells, index) => {
      const row = node('tr');
      for (const [key, value] of Object.entries(rowAttributes[index] || {})) row.setAttribute(key, value);
      cells.forEach((cell, position) => {
        if (position > 0) { row.append(typeof cell === 'object' ? cell : node('td', cell)); return; }
        const header = node('th', null, {scope: 'row'});
        if (typeof cell === 'object') header.append(cell); else header.textContent = String(cell);
        row.append(header);
      });
      body.append(row);
    });
    table.append(head, body);
    return table;
  };

  class DashboardOverview extends HTMLElement {
    constructor() { super(); this.attachShadow({mode: 'open'}); this.generation = 0; this.scope = 'mine'; this.team = ''; }
    connectedCallback() {
      if (this.mounted) return;
      this.mounted = true;
      this.changed = () => this.load();
      window.addEventListener('crm:record-changed', this.changed);
      window.addEventListener('ecc-navigation-focus', this.changed);
      this.mount();
      this.load();
    }
    disconnectedCallback() {
      this.generation++;
      window.removeEventListener('crm:record-changed', this.changed);
      window.removeEventListener('ecc-navigation-focus', this.changed);
      this.shadowRoot.replaceChildren();
      this.mounted = false;
    }
    mount() {
      const generation = ++this.generation;
      this.shadowRoot.replaceChildren();
      style(this.shadowRoot);
      const root = node('section', null, {class: 'tools dashboard-overview'});
      this.status = node('p', null, {role: 'status', 'aria-live': 'polite'});
      this.toolbar = node('div', null, {class: 'toolbar'});
      this.refresh = node('button', 'Refresh overview', {type: 'button', class: 'secondary'});
      this.refresh.onclick = () => this.load();
      this.body = node('div', null, {'aria-busy': 'true'});
      this.body.append(node('p', 'Loading the operational overview…'));
      root.append(node('h2', 'Workspace overview'),node('p', 'Use these figures to filter My work today. Expand a breakdown for stages, documents, balances or branches.'),this.toolbar, this.status, this.body);
      this.shadowRoot.append(root);
      void generation;
    }
    // Selecting a card never navigates away: it asks My work today for the
    // matching filtered records, so both panels always agree.
    focus(category, stage, label) {
      window.dispatchEvent(new CustomEvent('crm:dashboard-focus', {detail: {category, stage: stage || '', label: label || '', scope: this.scope, team: this.team, teamName: this.teamName || ''}}));
    }
    buildToolbar(data) {
      this.toolbar.replaceChildren();
      const scopeLabel = node('label', 'Show work'), scope = node('select', null, {name: 'scope'});
      for (const [value, text] of [['mine', 'Mine and unassigned'], ['unassigned', 'Unassigned'], ['all', 'All accessible work']]) scope.append(node('option', text, {value}));
      scope.value = this.scope;
      scopeLabel.append(scope);
      scope.onchange = () => { this.scope = scope.value; this.load(); };
      this.toolbar.append(scopeLabel);
      if (data.teamSelectable) {
        const teamLabel = node('label', 'Branch'), team = node('select', null, {name: 'team'});
        team.append(node('option', 'All branches', {value: ''}));
        for (const branch of data.teams || []) team.append(node('option', branch.name, {value: branch.id}));
        team.value = this.team;
        team.onchange = () => { this.team = team.value; this.load(); };
        teamLabel.append(team);
        this.toolbar.append(teamLabel);
      } else if (data.teamName) {
        this.toolbar.append(node('p', 'Branch: ' + data.teamName, {class: 'dashboard-note'}));
      }
      this.toolbar.append(this.refresh);
    }
    kpiGrid(data) {
      const grid = node('div', null, {class: 'kpi-grid'});
      for (const card of data.kpi || []) {
        const button = node('button', null, {type: 'button', class: 'kpi' + (card.severity ? ' kpi--attention' : ''), 'data-category': card.category, 'data-stage': card.stage || ''});
        button.append(node('span', card.label, {class: 'kpi__label'}), node('strong', String(card.value), {class: 'kpi__value'}), node('span', card.hint, {class: 'kpi__hint'}));
        button.setAttribute('aria-label', `${card.label}: ${card.value}. ${card.hint}. Show matching records`);
        button.onclick = () => this.focus(card.category, card.stage, card.label);
        grid.append(button);
      }
      return grid;
    }
    stagePanel(data) {
      const rows = data.caseStages || [];
      const section = panel('Applications by stage', 'Every stage your account can read. Choose a stage to open those applications.');
      if (!rows.length) { section.append(empty('No applications are visible to this account.')); return section; }
      const highest = rows.reduce((max, row) => Math.max(max, row.count), 0);
      const list = node('ul', null, {class: 'stage-list'});
      for (const row of rows) {
        const item = node('li');
        const button = node('button', null, {type: 'button', 'aria-label': `${row.stage}: ${row.count} applications. Show matching records`});
        button.append(node('span', row.stage, {class: 'stage-list__name'}), node('span', String(row.count), {class: 'stage-list__count'}));
        const bar = node('span', null, {class: 'stage-list__bar', 'aria-hidden': 'true'});
        const fill = node('span', null, {style: 'width:' + (highest > 0 ? Math.round((row.count / highest) * 100) : 0) + '%'});
        bar.append(fill);
        button.append(bar);
        button.onclick = () => this.focus('caseStages', row.stage, row.stage);
        item.append(button);
        list.append(item);
      }
      section.append(list);
      return section;
    }
    documentPanel(data) {
      const complete = data.documentCompleteness || {};
      const section = panel('Document completeness', 'Accessible required documents only. An empty checklist is reported separately and is not treated as complete.');
      if (!complete.applications) { section.append(empty('No active applications are visible to this account.')); return section; }
      const bar = node('div', null, {class: 'completeness', role: 'img', 'aria-label': `${complete.completePercent}% of active applications have every accessible required document verified`});
      const fill = node('span', null, {style: 'width:' + (complete.completePercent || 0) + '%'});
      bar.append(fill);
      section.append(bar);
      const rows = [
        ['Applications with every required file verified', complete.complete || 0, 'documentsComplete'],
        ['Applications still missing a required file', complete.incomplete || 0, 'documents'],
        ['Applications with no required files recorded', complete.noRequirements || 0, ''],
      ];
      const list = node('ul', null, {class: 'stage-list'});
      for (const [label, value, category] of rows) {
        const item = node('li');
        const content = node('span', null, {class: 'stage-list__row'});
        content.append(node('span', label, {class: 'stage-list__name'}), node('span', String(value), {class: 'stage-list__count'}));
        item.append(content);
        if (category) {
          const open = node('button', 'Show records', {type: 'button', class: 'secondary', 'aria-label': label + '. Show matching records'});
          open.onclick = () => this.focus(category, '', label);
          item.append(open);
        }
        list.append(item);
      }
      section.append(list);
      section.append(empty(`${complete.requiredDocuments || 0} required documents recorded · ${complete.verifiedDocuments || 0} verified · ${complete.expiredDocuments || 0} expired · ${complete.outstandingFiles || 0} still outstanding`));
      return section;
    }
    paymentsPanel(data) {
      const payments = data.paymentsDue || {};
      const section = panel('Payments due', 'Amounts stay in their own currency and are never added together. Overdue is measured against the workspace date.');
      const summary = node('ul', null, {class: 'stage-list'});
      for (const [label, value, category] of [['Overdue', payments.overdueCount || 0, 'invoicesOverdue'], ['Due within seven days', payments.dueSoonCount || 0, 'invoicesDueSoon'], ['Outstanding invoices in total', payments.openCount || 0, 'invoices'], ['Receipts awaiting approval', payments.pendingApprovals || 0, 'pendingApprovals']]) {
        const item = node('li');
        const content = node('span', null, {class: 'stage-list__row'});
        content.append(node('span', label, {class: 'stage-list__name'}), node('span', String(value), {class: 'stage-list__count'}));
        item.append(content);
        const open = node('button', 'Show records', {type: 'button', class: 'secondary', 'aria-label': label + '. Show matching records'});
        open.onclick = () => this.focus(category, '', label);
        item.append(open);
        summary.append(item);
      }
      section.append(summary);
      const buckets = [['Overdue', payments.overdue || []], ['Due within seven days', payments.dueSoon || []], ['Later', payments.later || []], ['No due date recorded', payments.noDueDate || []]];
      for (const [label, rows] of buckets) {
        if (!rows.length) continue;
        section.append(node('h4', label));
        section.append(dataTable(['Currency', 'Outstanding', 'Invoices'], rows.map(row => [row.currency, money(row.currency, row.amount), String(row.count)])));
      }
      if (!buckets.some(([, rows]) => rows.length)) section.append(empty('No outstanding balances are visible to this account.'));
      return section;
    }
    branchPanel(data) {
      const teams = data.teams || [];
      const section = panel(data.teamSelectable ? 'Branch overview' : 'My branch', data.teamSelectable ? 'Operational figures per branch, limited to records each viewer may read.' : 'Operational figures for your branch.');
      if (!teams.length) { section.append(empty('No branch is assigned to this account.')); return section; }
      const rows = teams.map(team => {
        const name = node('th', null, {scope: 'row'});
        name.append(node('span', team.name));
        if (data.teamSelectable) {
          const select = node('button', team.selected ? 'Viewing' : 'View', {type: 'button', class: 'secondary', 'aria-label': `Show the operational overview for ${team.name}`});
          select.disabled = !!team.selected;
          select.onclick = () => { this.team = team.id; this.load(); };
          name.append(select);
        }
        const cells = [name, String(team.members), String(team.activeCases), String(team.openLeads), String(team.followUpsDue), String(team.documentsIncomplete), String(team.invoicesOverdue)];
        return {cells, attributes: team.selected ? {'aria-current': 'true'} : {}};
      });
      section.append(dataTable(['Branch', 'Staff', 'Active applications', 'Open leads', 'Follow-ups due', 'Documents missing', 'Payments overdue'], rows.map(row => row.cells), rows.map(row => row.attributes)));
      return section;
    }
    async load() {
      if (!this.body) return;
      const generation = ++this.generation;
      this.refresh.disabled = true;
      this.body.setAttribute('aria-busy', 'true');
      this.status.textContent = 'Loading the operational overview…';
      const query = new URLSearchParams({scope: this.scope});
      if (this.team) query.set('team', this.team);
      try {
        const data = await request('/api/dashboard/overview?' + query);
        if (!this.isConnected || generation !== this.generation) return;
        this.teamName=data.teamName||'';
        this.buildToolbar(data);
        this.body.replaceChildren(this.kpiGrid(data));
        const grid = node('div', null, {class: 'dashboard-grid'});
        grid.append(this.stagePanel(data), this.documentPanel(data));
        this.body.append(grid);
        this.body.append(this.paymentsPanel(data), this.branchPanel(data));
        this.body.setAttribute('aria-busy', 'false');
        this.status.textContent = `${data.today} · figures for records you can read${data.teamName ? ' in ' + data.teamName : ''}. Choose any figure to open the matching records.`;
      } catch (error) {
        if (!this.isConnected || generation !== this.generation) return;
        this.body.setAttribute('aria-busy', 'false');
        this.body.replaceChildren(node('p', error.message + ' Use Refresh overview to retry.'));
        this.status.textContent = 'Unavailable · open to retry';
      } finally {
        if (generation === this.generation) this.refresh.disabled = false;
      }
    }
  }
  if (!customElements.get('crm-dashboard-overview')) customElements.define('crm-dashboard-overview', DashboardOverview);
  const themeTargets = 'crm-dashboard-overview';
  document.addEventListener('crm:theme-changed', () => {
    const theme = localStorage.getItem('theme') || 'light';
    for (const element of document.querySelectorAll(themeTargets)) element.dataset.theme = theme;
  });
})();