const {test}=require('node:test');
const assert=require('node:assert/strict');
const {parseHTML}=require('linkedom');
const vm=require('node:vm');
const fs=require('node:fs');
const path=require('node:path');
const wait=()=>new Promise(resolve=>setTimeout(resolve,20));
const tableHTML='<table class="data-table"><thead><tr><th>Name</th><th>Status</th><th></th></tr></thead><tbody><tr><td><a href="/contacts/client">Client One</a></td><td>Active</td><td><button>Edit</button></td></tr></tbody></table>';

async function mount(markup=tableHTML){
  const {window}=parseHTML('<html><body><div class="app-shell"><aside class="sidebar"><button class="sidebar__close">Close</button><button class="nav-item">Cases</button></aside><div class="app-main"><header class="topbar"><button id="menu">Menu</button></header><main class="content">'+markup+'</main></div><nav class="mobile-nav"><button>Home</button></nav><crm-connection-status></crm-connection-status></div></body></html>');
  const {document}=window;let active=document.body,resize;
  Object.defineProperty(document,'activeElement',{get:()=>active});
  window.HTMLElement.prototype.focus=function(){active=this};
  window.HTMLElement.prototype.getClientRects=function(){return [{}]};
  const media={matches:true,addEventListener:(event,fn)=>{resize=fn}};
  window.matchMedia=()=>media;window.scrollTo=()=>{};
  const navigator={onLine:true},timers=new Set();
  const raf=fn=>{const timer=setTimeout(()=>{timers.delete(timer);fn()},0);timers.add(timer);return timer};
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../public/mobile.js'),'utf8'),vm.createContext({window,document,navigator,HTMLElement:window.HTMLElement,customElements:window.customElements,MutationObserver:window.MutationObserver,requestAnimationFrame:raf,WeakSet}));
  await wait();
  return {window,document,media,navigator,resize:()=>resize(),cleanup(){for(const timer of timers)clearTimeout(timer);document.querySelector('crm-connection-status')?.remove()}};
}

test('mobile cards preserve record links and edit actions as records and headings change',async()=>{
  const app=await mount();try{
    const table=app.document.querySelector('table'),link=table.querySelector('a'),edit=table.querySelector('button');let clicks=0;edit.onclick=()=>clicks++;
    assert.ok(table.hasAttribute('data-mobile-cards'));assert.equal(table.getAttribute('role'),'table');
    assert.deepEqual([...table.querySelectorAll('td')].map(cell=>cell.getAttribute('data-label')),['Name','Status','Actions']);
    edit.click();assert.equal(clicks,1);assert.equal(table.querySelector('a'),link);assert.equal(link.getAttribute('href'),'/contacts/client');
    table.querySelectorAll('th')[1].textContent='Stage ↓';
    const row=app.document.createElement('tr');row.innerHTML='<td>Next client</td><td>Applying</td><td><button>Open</button></td>';table.querySelector('tbody').replaceChildren(row);await wait();
    assert.deepEqual([...row.children].map(cell=>cell.getAttribute('data-label')),['Name','Stage','Actions']);
    assert.ok(row.lastElementChild.hasAttribute('data-mobile-actions'));
  }finally{app.cleanup()}
});

test('tables with grouped or spanning cells keep their full table layout',async()=>{
  const app=await mount('<table><thead><tr><th>Group</th><th>Count</th></tr></thead><tbody><tr><td colspan="2">No records</td></tr></tbody></table>');try{
    assert.equal(app.document.querySelector('table').hasAttribute('data-mobile-cards'),false);
    assert.equal(app.document.querySelector('td').getAttribute('data-label'),null);
  }finally{app.cleanup()}
});

test('sortable headers and selection controls remain available above mobile cards',async()=>{
  const app=await mount('<table><thead><tr><th><button>Name ↑</button></th><th>Status</th></tr></thead><tbody><tr><td>Client</td><td>Active</td></tr></tbody></table>');try{
    const table=app.document.querySelector('table');assert.ok(table.hasAttribute('data-mobile-controls'));assert.ok(table.querySelector('th').hasAttribute('data-mobile-control'));
    let sorted=false;table.querySelector('button').onclick=()=>{sorted=true};table.querySelector('button').click();assert.equal(sorted,true);assert.equal(table.querySelector('td').getAttribute('data-label'),'Name');
  }finally{app.cleanup()}
});

test('record and administration shadow tables adapt after asynchronous rendering',async()=>{
  const app=await mount('');try{
    const host=app.document.createElement('crm-record-tools'),root=host.attachShadow({mode:'open'});app.document.querySelector('main').append(host);await wait();
    root.innerHTML='<section class="tools">'+tableHTML+'</section>';await wait();
    assert.ok(root.querySelector('table').hasAttribute('data-mobile-cards'));
    assert.equal(root.querySelector('td').getAttribute('data-label'),'Name');
    host.remove();
  }finally{app.cleanup()}
});

test('mobile navigation traps focus and returns it when closed',async()=>{
  const app=await mount();try{
    const sidebar=app.document.querySelector('.sidebar'),main=app.document.querySelector('.app-main'),menu=app.document.getElementById('menu');
    assert.ok(sidebar.hasAttribute('inert'));assert.equal(sidebar.getAttribute('aria-hidden'),'true');menu.focus();
    sidebar.classList.add('is-open');await wait();
    assert.equal(sidebar.hasAttribute('inert'),false);assert.ok(main.hasAttribute('inert'));assert.ok(app.document.documentElement.classList.contains('crm-scroll-locked'));
    assert.equal(app.document.activeElement,sidebar.querySelector('.sidebar__close'));
    sidebar.querySelector('.nav-item').focus();const tab=new app.window.Event('keydown',{bubbles:true,cancelable:true});tab.key='Tab';app.document.dispatchEvent(tab);
    assert.equal(app.document.activeElement,sidebar.querySelector('.sidebar__close'));assert.ok(tab.defaultPrevented);
    sidebar.classList.remove('is-open');await wait();
    assert.equal(main.hasAttribute('inert'),false);assert.equal(app.document.activeElement,menu);assert.equal(app.document.documentElement.classList.contains('crm-scroll-locked'),false);
  }finally{app.cleanup()}
});

test('desktop resize releases drawer restrictions and dialogs lock background scrolling',async()=>{
  const app=await mount();try{
    const sidebar=app.document.querySelector('.sidebar');sidebar.classList.add('is-open');await wait();app.media.matches=false;app.resize();await wait();
    assert.equal(sidebar.hasAttribute('inert'),false);assert.equal(app.document.querySelector('.app-main').hasAttribute('inert'),false);assert.equal(app.document.documentElement.classList.contains('crm-scroll-locked'),false);
    const modal=app.document.createElement('section');modal.className='modal';app.document.querySelector('main').append(modal);await wait();
    assert.ok(app.document.querySelector('.mobile-nav').hasAttribute('inert'));assert.ok(app.document.documentElement.classList.contains('crm-scroll-locked'));
    modal.remove();await wait();assert.equal(app.document.documentElement.classList.contains('crm-scroll-locked'),false);
  }finally{app.cleanup()}
});

test('offline status clears when the connection returns',async()=>{
  const app=await mount();try{
    const banner=app.document.querySelector('crm-connection-status');assert.equal(banner.textContent,'');
    app.navigator.onLine=false;app.window.dispatchEvent(new app.window.Event('offline'));assert.ok(banner.hasAttribute('data-offline'));assert.match(banner.textContent,/Reconnect before saving/);
    app.navigator.onLine=true;app.window.dispatchEvent(new app.window.Event('online'));assert.equal(banner.hasAttribute('data-offline'),false);assert.equal(banner.textContent,'');
  }finally{app.cleanup()}
});
