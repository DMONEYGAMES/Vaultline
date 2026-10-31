'use strict';

const THEME_KEY = 'vaultlineDesktopTheme';
const CATEGORIES = ['Personal', 'Work', 'Banking', 'Email', 'Social', 'Shopping', 'Gaming', 'Travel', 'Other'];
let entries = [];
let cards = [];
let notes = [];
let identities = [];
let selectedNoteFull = null;
let selectedIdentityFull = null;
let viewMode = 'logins';
let itemFilter = 'all';
let editingCardId = null;
let revealedCardId = null;
let revealedCardNumber = '';
let cardRevealTimer = null;
let selectedId = null;
let editingId = null;
let targetTabId = -1;
let targetUrl = '';
let targetHost = '';
let theme = 'system';
let revealedId = null;
let revealedPassword = '';
let revealTimer = null;
let toastTimer = null;

const $ = (selector) => document.querySelector(selector);

function normalizeHost(value) {
  try {
    const parsed = new URL(value.includes('://') ? value : `https://${value}`);
    if (!['https:', 'http:'].includes(parsed.protocol)) return '';
    return parsed.hostname.toLowerCase().replace(/\.$/, '');
  } catch { return ''; }
}

function normalizeWebsite(value) {
  const raw = String(value || '').trim();
  if (!raw) throw new Error('Enter the website for this login.');
  let parsed;
  try { parsed = new URL(raw.includes('://') ? raw : `https://${raw}`); }
  catch { throw new Error('Enter a valid website, such as https://example.com.'); }
  if (!['https:', 'http:'].includes(parsed.protocol) || !parsed.hostname) throw new Error('Only HTTP or HTTPS website addresses can be saved.');
  if (parsed.protocol === 'http:' && !['localhost', '127.0.0.1'].includes(parsed.hostname)) {
    if (!window.confirm('This website uses unencrypted HTTP. Save it anyway? HTTPS is safer.')) throw new Error('Save cancelled.');
  }
  return parsed.origin;
}

function desktopRequest(command, payload = {}) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage({ type: 'VAULTLINE_DESKTOP_REQUEST', command, payload }, (response) => {
      const lastError = chrome.runtime.lastError;
      if (lastError) { reject(new Error(lastError.message)); return; }
      if (!response?.ok) {
        const reason = response?.error || 'Vaultline Desktop request failed.';
        if (reason.includes('Could not establish connection') || reason.includes('native messaging host')) {
          reject(new Error('Vaultline Desktop connection is unavailable. Check the native host installation and restart Chrome.'));
        } else if (reason === 'authentication-required-or-cancelled') {
          reject(new Error('Mac authentication was cancelled or unavailable. Try again and approve the prompt.'));
        } else if (reason === 'website-mismatch') {
          reject(new Error('Vaultline blocked this request because the saved website did not match.'));
        } else if (reason === 'login-not-found') {
          reject(new Error('That login is no longer in your Mac Keychain. Refresh the list.'));
        } else {
          reject(new Error(reason));
        }
        return;
      }
      resolve(response);
    });
  });
}

function showToast(message, duration = 3500) {
  const node = $('#toast');
  node.textContent = message;
  node.classList.add('visible');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => node.classList.remove('visible'), duration);
}

function setTheme(next) {
  theme = next;
  const dark = theme === 'dark' || (theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  chrome.storage.local.set({ [THEME_KEY]: theme });
}

function currentItems() { return ({ logins: entries, cards, notes, identities })[viewMode] || entries; }

function visibleEntries() {
  const query = $('#search-input').value.trim().toLowerCase();
  let items = currentItems();
  if (itemFilter === 'favorites') items = items.filter(entry => !!entry.favorite);
  if (itemFilter === 'recent' && viewMode === 'logins') items = items.filter(entry => Number(entry.lastUsedAt || 0) > 0).sort((a,b) => Number(b.lastUsedAt || 0) - Number(a.lastUsedAt || 0));
  if (viewMode === 'logins' && targetHost) items = [...items].sort((a,b) => Number(normalizeHost(a.host || a.website) === targetHost) * -1 - (Number(normalizeHost(b.host || b.website) === targetHost) * -1));
  return items.filter((entry) => !query || [entry.title, entry.username, entry.website, entry.host, entry.category, entry.cardholder, entry.last4, entry.content, entry.fullName, entry.email, ...(entry.tags || [])].some((value) => String(value || '').toLowerCase().includes(query)));
}

function renderList() {
  const list = $('#login-list'); list.replaceChildren();
  const shown = visibleEntries(); const total = currentItems().length;
  $('#login-count').textContent = String(total);
  $('#tab-login-count').textContent = String(entries.length); $('#tab-card-count').textContent = String(cards.length);
  $('#tab-note-count').textContent = String(notes.length); $('#tab-identity-count').textContent = String(identities.length);
  $('#list-eyebrow').textContent = ({logins:'SAVED LOGINS',cards:'PAYMENT METHODS',notes:'PRIVATE NOTES',identities:'PERSONAL PROFILES'})[viewMode];
  $('#list-title').childNodes[0].textContent = ({logins:'Your accounts ',cards:'Your cards ',notes:'Secure notes ',identities:'Identities '})[viewMode];
  for (const mode of ['logins','cards','notes','identities']) $(`#view-${mode}`).classList.toggle('active', viewMode === mode);
  $('#filter-recent').hidden = viewMode !== 'logins';
  for (const filter of ['all','recent','favorites']) $(`#filter-${filter}`).classList.toggle('active', itemFilter === filter);
  chrome.storage.local.get({showCards:true,showNotes:true,showIdentities:true}).then(v=>{$('#view-cards').hidden=!v.showCards;$('#view-notes').hidden=!v.showNotes;$('#view-identities').hidden=!v.showIdentities});
  $('#add-card-button').hidden = viewMode !== 'cards'; $('#add-button').hidden = viewMode !== 'logins'; $('#capture-button').hidden = viewMode !== 'logins';
  $('#add-note-button').hidden = viewMode !== 'notes'; $('#add-identity-button').hidden = viewMode !== 'identities';
  $('#empty-state').hidden = shown.length > 0; list.hidden = shown.length === 0;
  const emptyCopy = {logins:"Add your first login. It will be stored in your Mac's Keychain.",cards:"Add a payment card to your Mac's Keychain.",notes:"Create a private note stored in your Mac's Keychain.",identities:"Create a personal profile for form autofill."};
  $('#empty-title').textContent = ({logins:'Your vault is ready',cards:'No cards saved yet',notes:'No secure notes yet',identities:'No identities yet'})[viewMode];
  $('#empty-copy').textContent = emptyCopy[viewMode]; $('#empty-add-button').textContent = ({logins:'Add a login',cards:'Add a card',notes:'Add a note',identities:'Add an identity'})[viewMode];
  for (const entry of shown) {
    const button=document.createElement('button');button.type='button';button.className=`login-row${entry.id===selectedId?' selected':''}`;button.dataset.id=entry.id;
    const icon=document.createElement('span');icon.className='favicon';icon.textContent=({logins:(entry.title||entry.host||'?').trim().charAt(0).toUpperCase(),cards:'▤',notes:'✎',identities:'ID'})[viewMode];
    const copy=document.createElement('span');copy.className='row-copy';const title=document.createElement('strong');title.textContent=entry.title||entry.host;
    const sub=document.createElement('span');sub.textContent=viewMode==='cards'?`•••• ${entry.last4} · ${String(entry.expiryMonth).padStart(2,'0')}/${String(entry.expiryYear).slice(-2)}`:viewMode==='logins'?(entry.username?`${entry.username} · ${entry.host}`:entry.host):viewMode==='notes'?(entry.category||'Private note'):(entry.email||entry.fullName||'Personal profile');
    copy.append(title,sub);button.append(icon,copy);if(entry.favorite){const star=document.createElement('span');star.className='row-star';star.textContent='★';button.append(star)}list.append(button);
  }
}

function makeField(label, value, action, actionLabel = 'Copy') {
  const row = document.createElement('div'); row.className = 'detail-field';
  const main = document.createElement('div'); main.className = 'field-main';
  const small = document.createElement('small'); small.textContent = label;
  const strong = document.createElement('strong'); strong.textContent = value || '—';
  main.append(small, strong);
  const actions = document.createElement('div'); actions.className = 'detail-actions';
  if (action) {
    const button = document.createElement('button'); button.type = 'button'; button.className = 'inline-button'; button.dataset.action = action; button.textContent = actionLabel; actions.append(button);
  }
  row.append(main, actions);
  return row;
}

function renderDetail() {
  if (viewMode === 'cards') { renderCardDetail(); return; }
  if (viewMode === 'notes') { renderNoteDetail(); return; }
  if (viewMode === 'identities') { renderIdentityDetail(); return; }
  const panel = $('#detail-panel');
  panel.replaceChildren();
  const entry = entries.find((item) => item.id === selectedId);
  if (!entry) {
    const empty = document.createElement('div'); empty.className = 'detail-empty';
    const icon = document.createElement('div'); icon.className = 'detail-empty-icon'; icon.textContent = '⌑';
    const heading = document.createElement('h2'); heading.textContent = 'Select a login';
    const copy = document.createElement('p'); copy.textContent = 'Choose an account to view its details, copy a field, or fill the matching website.';
    empty.append(icon, heading, copy); panel.append(empty); return;
  }
  const header = document.createElement('div'); header.className = 'detail-header';
  const logo = document.createElement('div'); logo.className = 'detail-logo'; logo.textContent = (entry.title || '?').charAt(0).toUpperCase();
  const titleWrap = document.createElement('div'); titleWrap.className = 'detail-title';
  const title = document.createElement('h2'); title.textContent = entry.title;
  const host = document.createElement('p'); host.textContent = entry.host;
  titleWrap.append(title, host); header.append(logo, titleWrap); panel.append(header);

  const info = document.createElement('div'); info.className = 'detail-section'; info.textContent = 'LOGIN INFORMATION'; panel.append(info);
  panel.append(makeField('WEBSITE', entry.website, 'open-site', 'Open'));
  panel.append(makeField('USERNAME', entry.username, 'copy-username'));
  const passValue = revealedId === entry.id && revealedPassword ? revealedPassword : 'Stored securely on this Mac · ••••••••••••';
  panel.append(makeField('PASSWORD', passValue, revealedId === entry.id && revealedPassword ? 'hide-password' : 'reveal-password', revealedId === entry.id && revealedPassword ? 'Hide' : 'Reveal'));
  const meta = document.createElement('div'); meta.className = 'detail-section'; meta.textContent = `CATEGORY · ${entry.category || 'Personal'}${entry.tags?.length ? ' · TAGS · ' + entry.tags.join(', ') : ''}`; panel.append(meta);
  if (entry.passwordHistoryCount > 0) { const history=document.createElement('button');history.className='inline-button';history.dataset.action='view-history';history.textContent=`View password history (${entry.passwordHistoryCount})`;panel.append(history); }

  const footer = document.createElement('div'); footer.className = 'detail-footer';
  const note = document.createElement('p');
  note.textContent = targetHost === entry.host ? `This login matches ${targetHost}.` : (targetHost ? `This login is for ${entry.host}, not ${targetHost}.` : 'Open the extension from a website to enable autofill.');
  const actions = document.createElement('div'); actions.className = 'detail-footer-actions';
  const edit = document.createElement('button'); edit.className = 'button subtle small'; edit.textContent = 'Edit'; edit.dataset.action = 'edit';
  const fill = document.createElement('button'); fill.className = 'button primary small'; fill.textContent = 'Autofill'; fill.dataset.action = 'autofill'; fill.disabled = !targetHost || targetHost !== entry.host || targetTabId < 0;
  actions.append(edit, fill); footer.append(note, actions); panel.append(footer);
  const deleteWrap = document.createElement('div'); deleteWrap.style.marginTop = '12px';
  const del = document.createElement('button'); del.className = 'inline-button'; del.dataset.action = 'delete'; del.textContent = 'Delete login'; deleteWrap.append(del); panel.append(deleteWrap);
}

function renderCardDetail() {
  const panel = $('#detail-panel');
  panel.replaceChildren();
  const card = cards.find((item) => item.id === selectedId);
  if (!card) {
    const empty = document.createElement('div'); empty.className = 'detail-empty';
    const icon = document.createElement('div'); icon.className = 'detail-empty-icon'; icon.textContent = '▤';
    const heading = document.createElement('h2'); heading.textContent = 'Select a payment card';
    const copy = document.createElement('p'); copy.textContent = 'Choose a card to view or edit its saved details.';
    empty.append(icon, heading, copy); panel.append(empty); return;
  }
  const header = document.createElement('div'); header.className = 'detail-header';
  const logo = document.createElement('div'); logo.className = 'detail-logo card-logo'; logo.textContent = '▤';
  const titleWrap = document.createElement('div'); titleWrap.className = 'detail-title';
  const title = document.createElement('h2'); title.textContent = card.title;
  const subtitle = document.createElement('p'); subtitle.textContent = `Payment card · ending in ${card.last4}`;
  titleWrap.append(title, subtitle); header.append(logo, titleWrap); panel.append(header);
  const visual = document.createElement('div'); visual.className = 'payment-card-visual';
  const brand = document.createElement('strong'); brand.textContent = 'VAULTLINE';
  const digits = document.createElement('div'); digits.className = 'payment-card-number'; digits.textContent = revealedCardId === card.id && revealedCardNumber ? revealedCardNumber.replace(/(.{4})/g, '$1 ').trim() : `••••  ••••  ••••  ${card.last4}`;
  const bottom = document.createElement('div'); bottom.className = 'payment-card-bottom';
  const holder = document.createElement('span'); holder.textContent = (card.cardholder || 'CARDHOLDER').toUpperCase();
  const expiry = document.createElement('span'); expiry.textContent = `EXP ${String(card.expiryMonth).padStart(2,'0')}/${String(card.expiryYear).slice(-2)}`;
  bottom.append(holder, expiry); visual.append(brand, digits, bottom); panel.append(visual);
  const info = document.createElement('div'); info.className = 'detail-section'; info.textContent = `PAYMENT CARD DETAILS${card.tags?.length ? ' · TAGS · ' + card.tags.join(', ') : ''}`; panel.append(info);
  panel.append(makeField('CARD NUMBER', revealedCardId === card.id && revealedCardNumber ? revealedCardNumber : `•••• •••• •••• ${card.last4}`, revealedCardId === card.id ? 'hide-card-number' : 'reveal-card-number', revealedCardId === card.id ? 'Hide' : 'Reveal'));
  const numberCopy = document.createElement('button'); numberCopy.type = 'button'; numberCopy.className = 'inline-button'; numberCopy.dataset.action = 'copy-card-number'; numberCopy.textContent = 'Copy card number'; numberCopy.style.marginBottom = '8px'; panel.append(numberCopy);
  panel.append(makeField('CARDHOLDER', card.cardholder, 'copy-cardholder'));
  panel.append(makeField('EXPIRATION', `${String(card.expiryMonth).padStart(2,'0')}/${card.expiryYear}`, 'copy-expiration'));
  panel.append(makeField('BILLING ZIP', card.billingZip, 'copy-card-zip'));
  if (card.notes) panel.append(makeField('NOTES', card.notes, 'copy-card-notes'));
  const footer = document.createElement('div'); footer.className = 'detail-footer';
  const note = document.createElement('p'); note.textContent = 'Card details are stored in your Mac Keychain. CVV/CVC and PINs are not stored.';
  const actions = document.createElement('div'); actions.className = 'detail-footer-actions';
  const edit = document.createElement('button'); edit.className = 'button subtle small'; edit.textContent = 'Edit'; edit.dataset.action = 'edit-card';
  const autofill=document.createElement('button');autofill.className='button primary small';autofill.textContent='Autofill card';autofill.dataset.action='autofill-card';autofill.disabled=targetTabId<0;actions.append(edit,autofill); footer.append(note, actions); panel.append(footer);
  const del = document.createElement('button'); del.className = 'inline-button'; del.dataset.action = 'delete-card'; del.textContent = 'Delete card'; del.style.marginTop = '12px'; panel.append(del);
}

function renderNoteDetail() {
  const panel=$('#detail-panel');panel.replaceChildren();const note=selectedNoteFull?.id===selectedId?selectedNoteFull:notes.find(x=>x.id===selectedId);
  if(!note){panel.innerHTML='<div class="detail-empty"><div class="detail-empty-icon">✎</div><h2>Select a secure note</h2><p>Choose a private note or create a new one.</p></div>';return;}
  const header=document.createElement('div');header.className='detail-header';const logo=document.createElement('div');logo.className='detail-logo';logo.textContent='✎';const wrap=document.createElement('div');wrap.className='detail-title';const h=document.createElement('h2');h.textContent=note.title;const sub=document.createElement('p');sub.textContent=note.category||'Private note';wrap.append(h,sub);header.append(logo,wrap);panel.append(header);
  const body=document.createElement('pre');body.className='secure-note-content';body.textContent=note.content||'';panel.append(body);
  if(note.tags?.length){const tags=document.createElement('p');tags.className='muted';tags.textContent='Tags: '+note.tags.join(', ');panel.append(tags)}
  const footer=document.createElement('div');footer.className='detail-footer';const copy=document.createElement('p');copy.textContent='This note is stored in your Mac Keychain.';const actions=document.createElement('div');actions.className='detail-footer-actions';const edit=document.createElement('button');edit.className='button subtle small';edit.dataset.action='edit-note';edit.textContent='Edit';actions.append(edit);footer.append(copy,actions);panel.append(footer);
  const del=document.createElement('button');del.className='inline-button';del.dataset.action='delete-note';del.textContent='Delete note';panel.append(del);
}
function renderIdentityDetail() {
  const panel=$('#detail-panel');panel.replaceChildren();const item=selectedIdentityFull?.id===selectedId?selectedIdentityFull:identities.find(x=>x.id===selectedId);
  if(!item){panel.innerHTML='<div class="detail-empty"><div class="detail-empty-icon">ID</div><h2>Select an identity</h2><p>Save your contact details for forms you choose to autofill.</p></div>';return;}
  const header=document.createElement('div');header.className='detail-header';const logo=document.createElement('div');logo.className='detail-logo';logo.textContent='ID';const wrap=document.createElement('div');wrap.className='detail-title';const h=document.createElement('h2');h.textContent=item.title;const sub=document.createElement('p');sub.textContent=item.fullName||'Personal identity';wrap.append(h,sub);header.append(logo,wrap);panel.append(header);
  for(const [label,value,action] of [['FULL NAME',item.fullName,'copy-identity-name'],['EMAIL',item.email,'copy-identity-email'],['PHONE',item.phone,'copy-identity-phone'],['COMPANY',item.company,'copy-identity-company'],['ADDRESS',`${item.addressLine1||''} ${item.addressLine2||''}`.trim(),'copy-identity-address'],['CITY',item.city,'copy-identity-city'],['REGION',item.region,'copy-identity-region'],['POSTAL CODE',item.postalCode,'copy-identity-postal'],['COUNTRY',item.country,'copy-identity-country']]) panel.append(makeField(label,value,action));
  if(item.tags?.length){const tags=document.createElement('p');tags.className='muted';tags.textContent='Tags: '+item.tags.join(', ');panel.append(tags)}
  const footer=document.createElement('div');footer.className='detail-footer';const copy=document.createElement('p');copy.textContent='Identity information is stored in your Mac Keychain.';const actions=document.createElement('div');actions.className='detail-footer-actions';const fill=document.createElement('button');fill.className='button primary small';fill.dataset.action='autofill-identity';fill.textContent='Autofill profile';fill.disabled=targetTabId<0;const edit=document.createElement('button');edit.className='button subtle small';edit.dataset.action='edit-identity';edit.textContent='Edit';actions.append(fill,edit);footer.append(copy,actions);panel.append(footer);
  const del=document.createElement('button');del.className='inline-button';del.dataset.action='delete-identity';del.textContent='Delete identity';panel.append(del);
}

function render() {
  renderList(); renderDetail();
  $('#site-banner').hidden = viewMode !== 'logins';
  $('#site-title').textContent = targetHost ? targetHost : 'No website selected';
  $('#site-subtitle').textContent = targetHost ? 'Vaultline checks the exact hostname before autofilling.' : 'Click the Vaultline icon while viewing a login page to use autofill.';
  const count = targetHost ? entries.filter((item) => item.host === targetHost).length : 0;
  $('#site-match-count').textContent = targetHost ? `${count} match${count === 1 ? '' : 'es'}` : '—';
}

function showConnect(message, title = 'Connect to Vaultline Desktop') {
  $('#app-screen').hidden = true;
  $('#connect-screen').hidden = false;
  $('#connect-title').textContent = title;
  $('#connect-error').textContent = message || '';
  $('#connect-error').hidden = !message;
}

async function refreshLogins() {
  const [loginResponse, cardResponse, noteResponse, identityResponse] = await Promise.all([desktopRequest('listLogins'), desktopRequest('listCards'), desktopRequest('listNotes'), desktopRequest('listIdentities')]);
  if (![loginResponse, cardResponse, noteResponse, identityResponse].every(r => Array.isArray(r.records))) throw new Error('Vaultline Desktop returned an invalid vault list.');
  entries = loginResponse.records.map((record) => ({
    id: String(record.id), type: 'login', title: String(record.title || ''), website: String(record.website || ''),
    host: String(record.host || normalizeHost(record.website || '')), username: String(record.username || ''),
    category: CATEGORIES.includes(record.category) ? record.category : 'Personal', favorite: !!record.favorite, tags: Array.isArray(record.tags) ? record.tags : [], passwordHistoryCount: Number(record.passwordHistoryCount || 0), lastUsedAt: Number(record.lastUsedAt || 0),
    createdAt: Number(record.createdAt || Date.now()), updatedAt: Number(record.updatedAt || Date.now())
  })).filter((item) => item.id && item.host);
  cards = cardResponse.records.map((record) => ({
    id: String(record.id), type: 'card', title: String(record.title || ''), cardholder: String(record.cardholder || ''),
    last4: String(record.last4 || ''), expiryMonth: Number(record.expiryMonth || 0), expiryYear: Number(record.expiryYear || 0),
    billingZip: String(record.billingZip || ''), notes: String(record.notes || ''), favorite: !!record.favorite,
    tags: Array.isArray(record.tags) ? record.tags : [],
    createdAt: Number(record.createdAt || Date.now()), updatedAt: Number(record.updatedAt || Date.now())
  })).filter((item) => item.id && item.last4);
  notes = noteResponse.records.map(r => ({ ...r, id:String(r.id), title:String(r.title||''), contentPreview:String(r.preview||''), tags:Array.isArray(r.tags)?r.tags:[], favorite:!!r.favorite }));
  identities = identityResponse.records.map(r => ({ ...r, id:String(r.id), title:String(r.title||''), fullName:String(r.fullName||''), email:String(r.email||''), tags:Array.isArray(r.tags)?r.tags:[], favorite:!!r.favorite }));
  if (!currentItems().some((entry) => entry.id === selectedId)) selectedId = currentItems()[0]?.id || null;
  if(viewMode==='logins'&&targetHost){const matches=entries.filter(e=>e.host===targetHost);if(matches.length===1)selectedId=matches[0].id;}
  $('#connection-status').innerHTML = '<i></i> Desktop connected';
  render();
}

async function connect() {
  $('#retry-connect').disabled = true;
  $('#retry-connect').textContent = 'Connecting…';
  try {
    const ping = await desktopRequest('ping');
    if (!ping.ok) throw new Error('Vaultline Desktop did not respond.');
    await refreshLogins();
    $('#connect-screen').hidden = true;
    $('#app-screen').hidden = false;
    showToast('Connected to Vaultline Desktop. Your logins are stored on this Mac.');
  } catch (error) {
    showConnect(error.message || 'Could not connect to Vaultline Desktop. Check the native host installation and restart Chrome.');
  } finally {
    $('#retry-connect').disabled = false;
    $('#retry-connect').textContent = 'Connect to desktop';
  }
}

async function getLogin(id, host) {
  const result = await desktopRequest('getLogin', { id, host });
  const cached = entries.find(item => item.id === id);
  if (cached) cached.lastUsedAt = Date.now();
  if (viewMode === 'logins' && (itemFilter === 'recent' || itemFilter === 'all')) renderList();
  return result;
}

function closeModal() {
  $('#login-modal').hidden = true;
  $('#login-form').reset();
  $('#field-password').value = '';
  editingId = null;
}

function openModal(record = null) {
  editingId = record?.id || null;
  $('#modal-title').textContent = record ? 'Edit login' : 'Add a login';
  $('#form-error').hidden = true;
  $('#login-form').reset();
  $('#field-title').value = record?.title || (targetHost ? targetHost : '');
  $('#field-website').value = record?.website || (targetUrl ? new URL(targetUrl).origin : '');
  $('#field-username').value = record?.username || '';
  $('#field-password').value = record?.password || '';
  $('#field-category').value = record?.category || 'Personal';
  $('#field-favorite').checked = !!record?.favorite;
  $('#field-tags').value = (record?.tags || []).join(', ');
  $('#field-password').type = 'password';
  $('#login-modal').hidden = false;
  $('#field-title').focus();
}

async function editSelected() {
  const record = entries.find((entry) => entry.id === selectedId);
  if (!record) return;
  try {
    const full = await getLogin(record.id, record.host);
    openModal({ ...record, username: full.username, password: full.password });
  } catch (error) { showToast(error.message || 'Could not load login for editing.'); }
}

async function saveLogin(event) {
  event.preventDefault();
  $('#form-error').hidden = true;
  try {
    const website = normalizeWebsite($('#field-website').value);
    const title = $('#field-title').value.trim();
    const username = $('#field-username').value.trim();
    const password = $('#field-password').value;
    if (!title) throw new Error('Enter an account name.');
    if (!password) throw new Error('Enter a password.');
    const old = entries.find((entry) => entry.id === editingId);
    const record = {
      id: editingId || crypto.randomUUID(), type: 'login', title, website, username, password,
      category: CATEGORIES.includes($('#field-category').value) ? $('#field-category').value : 'Personal',
      favorite: $('#field-favorite').checked, tags: $('#field-tags').value.split(',').map(v=>v.trim()).filter(Boolean).slice(0,12), createdAt: old?.createdAt || Date.now(), updatedAt: Date.now()
    };
    const response = await desktopRequest('saveLogin', { record });
    if (!response.record?.id) throw new Error('Desktop did not confirm the saved login.');
    $('#login-modal').hidden = true;
    $('#login-form').reset();
    $('#field-password').value = '';
    selectedId = record.id;
    await refreshLogins();
    showToast(old ? 'Login updated in your Mac Keychain.' : 'Login saved in your Mac Keychain.');
  } catch (error) {
    $('#form-error').textContent = error.message || 'Could not save this login.';
    $('#form-error').hidden = false;
  }
}

function closeCardModal() {
  $('#card-modal').hidden = true; $('#card-form').reset(); $('#card-number').value = ''; editingCardId = null;
}

function openCardModal(record = null) {
  editingCardId = record?.id || null;
  $('#card-modal-title').textContent = record ? 'Edit payment card' : 'Add a payment card';
  $('#card-form-error').hidden = true; $('#card-form').reset();
  $('#card-title').value = record?.title || '';
  $('#card-cardholder').value = record?.cardholder || '';
  $('#card-number').value = record?.number || '';
  $('#card-month').value = record ? String(record.expiryMonth) : '';
  $('#card-year').value = record?.expiryYear || '';
  $('#card-zip').value = record?.billingZip || '';
  $('#card-notes').value = record?.notes || '';
  $('#card-favorite').checked = !!record?.favorite;
  $('#card-tags').value = Array.isArray(record?.tags) ? record.tags.join(', ') : '';
  $('#card-number').type = 'password'; $('#card-number-toggle').textContent = 'Show';
  $('#card-modal').hidden = false; $('#card-title').focus();
}

function cardLuhnValid(value) {
  const digits = String(value).replace(/\D/g, '');
  if (digits.length < 12 || digits.length > 19) return false;
  let sum = 0; let doubleDigit = false;
  for (let i = digits.length - 1; i >= 0; i--) {
    let n = Number(digits[i]);
    if (doubleDigit) { n *= 2; if (n > 9) n -= 9; }
    sum += n; doubleDigit = !doubleDigit;
  }
  return sum % 10 === 0;
}

async function editSelectedCard() {
  const card = cards.find((item) => item.id === selectedId); if (!card) return;
  const full = await desktopRequest('getCard', { id: card.id });
  openCardModal({ ...card, ...full });
}

async function saveCard(event) {
  event.preventDefault(); $('#card-form-error').hidden = true;
  try {
    const title = $('#card-title').value.trim();
    const number = $('#card-number').value.replace(/\D/g, '');
    const month = Number($('#card-month').value); const year = Number($('#card-year').value);
    if (!title) throw new Error('Enter a nickname for this card.');
    if (!cardLuhnValid(number)) throw new Error('Check the card number and try again.');
    if (!Number.isInteger(month) || month < 1 || month > 12 || !Number.isInteger(year) || year < 2020 || year > 2099) throw new Error('Enter a valid expiration month and year.');
    const old = cards.find((item) => item.id === editingCardId);
    const record = { id: editingCardId || crypto.randomUUID(), type: 'card', title,
      cardholder: $('#card-cardholder').value.trim(), number, expiryMonth: month, expiryYear: year,
      billingZip: $('#card-zip').value.trim(), notes: $('#card-notes').value.trim(), favorite: $('#card-favorite').checked, tags: $('#card-tags').value.split(',').map(x=>x.trim()).filter(Boolean).slice(0,12),
      createdAt: old?.createdAt || Date.now(), updatedAt: Date.now() };
    await desktopRequest('saveCard', { record });
    closeCardModal(); selectedId = record.id; viewMode = 'cards';
    await refreshLogins(); showToast(old ? 'Payment card updated in your Mac Keychain.' : 'Payment card saved in your Mac Keychain.');
  } catch (error) { $('#card-form-error').textContent = error.message || 'Could not save this card.'; $('#card-form-error').hidden = false; }
}

async function revealCardNumber() {
  const card = cards.find((item) => item.id === selectedId); if (!card) return;
  try {
    const full = await desktopRequest('getCard', { id: card.id });
    revealedCardId = card.id; revealedCardNumber = String(full.number || ''); renderCardDetail();
    clearTimeout(cardRevealTimer); cardRevealTimer = setTimeout(() => { revealedCardId = null; revealedCardNumber = ''; renderCardDetail(); }, 20000);
    showToast('Card number revealed for 20 seconds.');
  } catch (error) { showToast(error.message || 'Could not reveal card number.'); }
}

async function cardAction(action) {
  const card = cards.find((item) => item.id === selectedId); if (!card) return;
  if (action === 'edit-card') { await editSelectedCard(); return; }
  if (action === 'delete-card') {
    if (!window.confirm(`Delete “${card.title}” ending in ${card.last4} from this Mac?`)) return;
    await desktopRequest('deleteCard', { id: card.id }); cards = cards.filter((item) => item.id !== card.id); selectedId = cards[0]?.id || null; revealedCardId = null; revealedCardNumber = ''; clearTimeout(cardRevealTimer); render(); showToast('Payment card deleted from your Mac Keychain.'); return;
  }
  if (action === 'autofill-card') { await fillSelectedCard(); return; }
  if (action === 'reveal-card-number') { await revealCardNumber(); return; }
  if (action === 'hide-card-number') { revealedCardId = null; revealedCardNumber = ''; clearTimeout(cardRevealTimer); renderCardDetail(); return; }
  let value = '';
  if (action === 'copy-cardholder') value = card.cardholder;
  if (action === 'copy-expiration') value = `${String(card.expiryMonth).padStart(2,'0')}/${card.expiryYear}`;
  if (action === 'copy-card-zip') value = card.billingZip;
  if (action === 'copy-card-notes') value = card.notes;
  if (action === 'copy-card-number') value = String((await desktopRequest('getCard', { id: card.id })).number || '');
  if (value) { await writeClipboard(value,'Card detail'); }
}

async function loadSelectedNote(){const item=notes.find(x=>x.id===selectedId);if(!item)return;try{selectedNoteFull=await desktopRequest('getNote',{id:item.id});renderDetail()}catch(e){showToast(e.message||'Could not load secure note.')}}
async function loadSelectedIdentity(){const item=identities.find(x=>x.id===selectedId);if(!item)return;try{selectedIdentityFull=await desktopRequest('getIdentity',{id:item.id});renderDetail()}catch(e){showToast(e.message||'Could not load identity.')}}
let editingNoteId=null, editingIdentityId=null;
function openNoteModal(record=null){editingNoteId=record?.id||null;$('#note-modal-title').textContent=record?'Edit secure note':'Add secure note';$('#note-error').hidden=true;$('#note-form').reset();$('#note-title').value=record?.title||'';$('#note-category').value=record?.category||'Personal';$('#note-tags').value=(record?.tags||[]).join(', ');$('#note-content').value=record?.content||'';$('#note-favorite').checked=!!record?.favorite;$('#note-modal').hidden=false;$('#note-title').focus()}
function closeNoteModal(){ $('#note-modal').hidden=true;$('#note-form').reset();editingNoteId=null; }
async function saveNote(event){event.preventDefault();try{const old=notes.find(x=>x.id===editingNoteId);const record={id:editingNoteId||crypto.randomUUID(),type:'note',title:$('#note-title').value.trim(),content:$('#note-content').value,category:$('#note-category').value.trim()||'Personal',tags:$('#note-tags').value.split(',').map(x=>x.trim()).filter(Boolean).slice(0,12),favorite:$('#note-favorite').checked,createdAt:old?.createdAt||Date.now(),updatedAt:Date.now()};if(!record.title||!record.content)throw new Error('Enter a title and note content.');await desktopRequest('saveNote',{record});closeNoteModal();viewMode='notes';selectedId=record.id;await refreshLogins();showToast('Secure note saved to your Mac.')}catch(e){$('#note-error').textContent=e.message;$('#note-error').hidden=false}}
function openIdentityModal(record=null){editingIdentityId=record?.id||null;$('#identity-modal-title').textContent=record?'Edit identity':'Add identity';$('#identity-error').hidden=true;$('#identity-form').reset();const fields={title:'title',name:'fullName',email:'email',phone:'phone',company:'company',country:'country',address1:'addressLine1',address2:'addressLine2',city:'city',region:'region',postal:'postalCode',notes:'notes'};for(const [id,key] of Object.entries(fields))$(`#identity-${id}`).value=record?.[key]||'';$('#identity-tags').value=(record?.tags||[]).join(', ');$('#identity-favorite').checked=!!record?.favorite;$('#identity-modal').hidden=false;$('#identity-title').focus()}
function closeIdentityModal(){$('#identity-modal').hidden=true;$('#identity-form').reset();editingIdentityId=null}
async function saveIdentity(event){event.preventDefault();try{const old=identities.find(x=>x.id===editingIdentityId);const record={id:editingIdentityId||crypto.randomUUID(),type:'identity',title:$('#identity-title').value.trim(),fullName:$('#identity-name').value.trim(),email:$('#identity-email').value.trim(),phone:$('#identity-phone').value.trim(),company:$('#identity-company').value.trim(),country:$('#identity-country').value.trim(),addressLine1:$('#identity-address1').value.trim(),addressLine2:$('#identity-address2').value.trim(),city:$('#identity-city').value.trim(),region:$('#identity-region').value.trim(),postalCode:$('#identity-postal').value.trim(),notes:$('#identity-notes').value.trim(),tags:$('#identity-tags').value.split(',').map(x=>x.trim()).filter(Boolean).slice(0,12),favorite:$('#identity-favorite').checked,createdAt:old?.createdAt||Date.now(),updatedAt:Date.now()};if(!record.title)throw new Error('Enter a profile name.');await desktopRequest('saveIdentity',{record});closeIdentityModal();viewMode='identities';selectedId=record.id;await refreshLogins();showToast('Identity saved to your Mac.')}catch(e){$('#identity-error').textContent=e.message;$('#identity-error').hidden=false}}
async function identityAction(action){const item=identities.find(x=>x.id===selectedId);if(!item)return;if(action==='edit-identity'){const full=await desktopRequest('getIdentity',{id:item.id});openIdentityModal({...item,...full});return}if(action==='delete-identity'){if(!confirm(`Delete identity “${item.title}”?`))return;await desktopRequest('deleteIdentity',{id:item.id});identities=identities.filter(x=>x.id!==item.id);selectedId=identities[0]?.id||null;render();showToast('Identity deleted.');return}if(action==='autofill-identity'){await autofillIdentity(item);return}const map={'copy-identity-name':item.fullName,'copy-identity-email':item.email,'copy-identity-phone':item.phone,'copy-identity-company':item.company,'copy-identity-address':[item.addressLine1,item.addressLine2].filter(Boolean).join(', '),'copy-identity-city':item.city,'copy-identity-region':item.region,'copy-identity-postal':item.postalCode,'copy-identity-country':item.country};if(map[action])await writeClipboard(map[action],'Identity field')}
async function deleteNote(){const note=notes.find(x=>x.id===selectedId);if(!note||!confirm(`Delete secure note “${note.title}”?`))return;await desktopRequest('deleteNote',{id:note.id});notes=notes.filter(x=>x.id!==note.id);selectedId=notes[0]?.id||null;render();showToast('Secure note deleted.')}
async function viewPasswordHistory(){const entry=entries.find(x=>x.id===selectedId);if(!entry)return;const full=await getLogin(entry.id,entry.host);const list=$('#history-list');list.replaceChildren();const values=Array.isArray(full.passwordHistory)?full.passwordHistory:[];if(!values.length){list.textContent='No previous passwords recorded.'}else values.forEach((value,index)=>{const row=document.createElement('div');row.className='detail-field';const label=document.createElement('strong');label.textContent=`Previous password ${index+1} · ••••••••`;const b=document.createElement('button');b.className='inline-button';b.textContent='Reveal';b.addEventListener('click',()=>{label.textContent=value;b.textContent='Hide';b.onclick=()=>{label.textContent=`Previous password ${index+1} · ••••••••`;b.textContent='Reveal';b.onclick=null}});row.append(label,b);list.append(row)});$('#history-modal').hidden=false}
async function autofillIdentity(item){if(targetTabId<0)throw new Error('Open Vaultline from the form page first.');const currentTab=await chrome.tabs.get(targetTabId);if(!currentTab.url||!/^https?:\/\//i.test(currentTab.url))throw new Error('Identity autofill is available only on HTTP or HTTPS pages.');if(targetUrl&&new URL(currentTab.url).origin!==new URL(targetUrl).origin)throw new Error('The website tab changed. Reopen Vaultline from the form page.');const full=await desktopRequest('getIdentity',{id:item.id});const results=await chrome.scripting.executeScript({target:{tabId:targetTabId},func:(data)=>{const visible=el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'&&!el.disabled&&!el.readOnly};const fields=[...document.querySelectorAll('input,select,textarea')].filter(visible);const hints=[['name',data.fullName],['email',data.email],['tel',data.phone],['organization',data.company],['address-line1',data.addressLine1],['address-line2',data.addressLine2],['address-level2',data.city],['address-level1',data.region],['postal-code',data.postalCode],['country-name',data.country]];let filled=0;for(const [token,value] of hints){if(!value)continue;const el=fields.find(x=>(x.autocomplete||'').toLowerCase().includes(token));if(!el)continue;const proto=el instanceof HTMLTextAreaElement?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(setter)setter.call(el,value);else el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));filled++}return {filled}},args:[full]});showToast(`Filled ${results?.[0]?.result?.filled||0} profile fields. Review them before submitting.`)}
async function fillSelectedCard(){const card=cards.find(x=>x.id===selectedId);if(!card||targetTabId<0)throw new Error('Open Vaultline from a secure checkout page first.');const currentTab=await chrome.tabs.get(targetTabId);if(!currentTab.url||!/^https:\/\//i.test(currentTab.url))throw new Error('Payment-card autofill is available only on HTTPS pages.');if(targetUrl&&new URL(currentTab.url).origin!==new URL(targetUrl).origin)throw new Error('The website tab changed. Reopen Vaultline from the checkout page.');const full=await desktopRequest('getCard',{id:card.id});const result=await chrome.scripting.executeScript({target:{tabId:targetTabId},func:data=>{const visible=el=>{const r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.display!=='none'&&s.visibility!=='hidden'&&!el.disabled&&!el.readOnly};const fields=[...document.querySelectorAll('input,select')].filter(visible);const set=(tokens,value)=>{if(!value)return false;const el=fields.find(x=>tokens.includes((x.autocomplete||'').toLowerCase()))||fields.find(x=>tokens.some(t=>`${x.name} ${x.id} ${x.placeholder}`.toLowerCase().includes(t)));if(!el)return false;const proto=el instanceof HTMLSelectElement?HTMLSelectElement.prototype:HTMLInputElement.prototype;const setter=Object.getOwnPropertyDescriptor(proto,'value')?.set;if(setter)setter.call(el,value);else el.value=value;el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return true};let count=0;count+=+set(['cc-number'],data.number);count+=+set(['cc-name'],data.cardholder);count+=+set(['cc-exp-month'],String(data.expiryMonth).padStart(2,'0'));count+=+set(['cc-exp-year'],String(data.expiryYear));count+=+set(['cc-postal-code'],data.billingZip);return {count}},args:[full]});showToast(`Filled ${result?.[0]?.result?.count||0} card fields. CVV was not stored or filled; review checkout yourself.`)}
async function writeClipboard(value,label='Value'){if(!value)throw new Error('Nothing to copy.');await navigator.clipboard.writeText(value);const prefs=await chrome.storage.local.get({clipboardClearSeconds:45});const seconds=Number(prefs.clipboardClearSeconds ?? 45);if(seconds>0){setTimeout(async()=>{try{if(await navigator.clipboard.readText()===value)await navigator.clipboard.writeText('')}catch{}},seconds*1000);showToast(`${label} copied. Clipboard clear scheduled in ${seconds}s.`)}else showToast(`${label} copied.`)}

async function captureFromPage() {
  if (targetTabId < 0) { showToast('Open Vaultline from a login page first.'); return; }
  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: targetTabId },
      func: () => {
        const visible = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled; };
        const password = [...document.querySelectorAll('input[type="password"]')].find(visible);
        if (!password) return { ok: false, reason: 'No visible password field was found. Fill in the login form first.' };
        const form = password.form || password.closest('form') || document;
        const candidates = [...form.querySelectorAll('input')].filter((el) => visible(el) && el !== password && ['text','email','tel'].includes((el.type || 'text').toLowerCase()));
        const score = (el) => { const hint = `${el.autocomplete} ${el.name} ${el.id} ${el.placeholder}`.toLowerCase(); return (el.autocomplete === 'username' ? 100 : 0) + (el.type === 'email' ? 30 : 0) + (/user|email|login|account/.test(hint) ? 20 : 0) - (/search|coupon|promo|zip|postal|address/.test(hint) ? 80 : 0); };
        candidates.sort((a,b) => score(b)-score(a));
        return { ok: true, title: document.title || location.hostname, website: location.origin, username: candidates[0]?.value || '', password: password.value || '' };
      }
    });
    const captured = results?.[0]?.result;
    if (!captured?.ok) { showToast(captured?.reason || 'Could not read login fields from this page.'); return; }
    openModal({ title: captured.title.slice(0, 120), website: captured.website, username: captured.username, password: captured.password, category: 'Personal', favorite: false });
    showToast('Review the captured fields, then choose Save to Mac.');
  } catch (error) {
    showToast('Could not read this page. Some browser pages and restricted sites block extension access.');
  }
}

async function fillSelected() {
  const record = entries.find((entry) => entry.id === selectedId);
  if (!record) return;
  if (targetTabId < 0 || !targetHost) { showToast('Open Vaultline from the login page first.'); return; }
  if (record.host !== targetHost) { showToast('Autofill blocked: the saved hostname does not match this tab.'); return; }
  try {
    const tab = await chrome.tabs.get(targetTabId);
    if (!tab.url || normalizeHost(tab.url) !== record.host) throw new Error('The website tab changed. Reopen Vaultline from the matching sign-in page.');
    const credentials = await getLogin(record.id, record.host);
    if (credentials.host !== record.host || !credentials.password) throw new Error('Vaultline did not return a matching credential.');
    const results = await chrome.scripting.executeScript({
      target: { tabId: targetTabId },
      func: (expectedHost, username, password) => {
        const norm = (value) => String(value || '').toLowerCase().replace(/\.$/, '');
        if (norm(location.hostname) !== norm(expectedHost)) return { ok: false, reason: 'website-mismatch' };
        const visible = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled && !el.readOnly; };
        const passwordInputs = [...document.querySelectorAll('input[type="password"],input[autocomplete="current-password"]')].filter(visible);
        if (!passwordInputs.length) return { ok: false, reason: 'no-password-field' };
        const passField = passwordInputs.find((el) => el.autocomplete === 'current-password') || passwordInputs[0];
        const form = passField.form || passField.closest('form') || document;
        const users = [...form.querySelectorAll('input')].filter((el) => visible(el) && el !== passField && ['text','email','tel'].includes((el.type || 'text').toLowerCase()));
        const score = (el) => { const h = `${el.autocomplete} ${el.name} ${el.id} ${el.placeholder}`.toLowerCase(); return (el.autocomplete === 'username' ? 100 : 0) + (el.type === 'email' ? 30 : 0) + (/user|email|login|account/.test(h) ? 20 : 0) - (/search|coupon|promo|zip|postal|address/.test(h) ? 80 : 0); };
        users.sort((a,b) => score(b)-score(a));
        const set = (el, value) => { const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set; if (setter) setter.call(el, value); else el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); el.dispatchEvent(new Event('change', { bubbles: true })); };
        if (username && users.length) set(users[0], username);
        set(passField, password); passField.focus({ preventScroll: true });
        return { ok: true, usernameFilled: !!username && users.length > 0 };
      },
      args: [record.host, credentials.username || '', credentials.password]
    });
    const result = results?.[0]?.result;
    if (!result?.ok) {
      if (result?.reason === 'no-password-field') throw new Error('No visible password field was found. Open the sign-in form and try again.');
      throw new Error('The page hostname did not match. Autofill was blocked.');
    }
    showToast('Login filled. Review it and submit the website form yourself.');
  } catch (error) { showToast(error.message || 'Could not autofill this page.'); }
}

async function copyField(field) {
  const entry = entries.find((item) => item.id === selectedId);
  if (!entry) return;
  try {
    let value = '';
    if (field === 'username') value = entry.username;
    if (field === 'password') value = (await getLogin(entry.id, entry.host)).password;
    if (!value) throw new Error('Nothing to copy for this field.');
    await writeClipboard(value, field === 'username' ? 'Username' : 'Password');
  } catch (error) { showToast(error.message || 'Could not copy this field.'); }
}

async function revealPassword() {
  const entry = entries.find((item) => item.id === selectedId);
  if (!entry) return;
  try {
    const credentials = await getLogin(entry.id, entry.host);
    revealedId = entry.id;
    revealedPassword = credentials.password;
    renderDetail();
    clearTimeout(revealTimer);
    revealTimer = setTimeout(() => { revealedId = null; revealedPassword = ''; renderDetail(); }, 20000);
    showToast('Password revealed for 20 seconds.');
  } catch (error) { showToast(error.message || 'Could not reveal password.'); }
}

async function deleteSelected() {
  if (viewMode === 'cards') { await cardAction('delete-card'); return; }
  const entry = entries.find((item) => item.id === selectedId);
  if (!entry) return;
  if (!window.confirm(`Delete “${entry.title}” for ${entry.host} from this Mac? This cannot be undone.`)) return;
  try {
    await desktopRequest('deleteLogin', { id: entry.id });
    entries = entries.filter((item) => item.id !== entry.id);
    selectedId = entries[0]?.id || null;
    revealedId = null; revealedPassword = ''; render();
    showToast('Login deleted from your Mac Keychain.');
  } catch (error) { showToast(error.message || 'Could not delete this login.'); }
}

async function lockVault() {
  try { await desktopRequest('lock'); } catch (_) { /* Port may already be closed. */ }
  entries = []; cards = []; notes=[]; identities=[]; selectedNoteFull=null; selectedIdentityFull=null; selectedId = null; revealedId = null; revealedPassword = ''; revealedCardId = null; revealedCardNumber = '';
  clearTimeout(revealTimer); clearTimeout(cardRevealTimer);
  showConnect('Vaultline is locked. Connect again to unlock with Mac authentication.', 'Vaultline locked');
}

function randomPassword(length = 22) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*+-_=.?';
  const limit = Math.floor(256 / alphabet.length) * alphabet.length;
  let output = '';
  while (output.length < length) {
    const bytes = new Uint8Array(Math.max(16, length - output.length));
    crypto.getRandomValues(bytes);
    for (const byte of bytes) {
      if (byte < limit) output += alphabet[byte % alphabet.length];
      if (output.length >= length) break;
    }
  }
  return output;
}

const WORDS=['amber','anchor','apricot','arch','atlas','aurora','badger','bamboo','beacon','birch','bison','bluebird','boulder','breeze','brook','cactus','camera','canary','canyon','carbon','cedar','cello','cinder','citadel','clover','comet','copper','coral','cosmos','cricket','crystal','cypress','daisy','delta','denim','dolphin','dragon','drift','eagle','echo','ember','falcon','fern','fjord','flannel','flint','forest','fossil','galaxy','garden','ginger','glacier','goblin','golden','granite','harbor','hazel','helium','heron','honey','horizon','iceberg','indigo','island','ivory','jade','jasmine','jigsaw','juniper','kettle','kiwi','lantern','laurel','lemon','lilac','lizard','lotus','magnet','maple','marble','meadow','meteor','midnight','mint','mosaic','mountain','nebula','nectar','nickel','nightjar','north','oasis','ocean','olive','onyx','orchid','otter','panda','paper','pebble','pepper','phoenix','piano','picket','pine','planet','plum','pocket','polar','prism','quartz','rabbit','radar','rainbow','raven','ripple','river','robin','rocket','saffron','sailor','saturn','scarlet','shadow','silver','sketch','slate','solar','sparrow','spruce','squirrel','starling','storm','summit','sunrise','tangerine','thistle','thunder','timber','topaz','tractor','tulip','tundra','turtle','velvet','violet','volcano','walnut','willow','winter','wizard','wren','zephyr','zinc'];
function randomIndex(max){const limit=Math.floor(256/max)*max;let v;do{const a=new Uint8Array(1);crypto.getRandomValues(a);v=a[0]}while(v>=limit);return v%max}
function randomPassphrase(){return Array.from({length:12},()=>WORDS[randomIndex(WORDS.length)]).join('-')}
async function openSecurityCenter(){
  $('#tools-title').textContent='Security Center';$('#tools-content').replaceChildren();
  const box=document.createElement('div');box.innerHTML='<p class="muted">Run a local-only review of the passwords stored on this Mac. Passwords are not sent to a web service.</p><button class="button primary" id="run-audit">Run password health check</button><div id="audit-results" class="tools-results"></div><button class="button subtle" id="show-activity">View activity history</button>';
  $('#tools-content').append(box);$('#tools-modal').hidden=false;
  box.querySelector('#run-audit').addEventListener('click',async()=>{const result=await desktopRequest('securityAudit');const node=box.querySelector('#audit-results');node.replaceChildren();const entries=[['Total logins',result.total],['Weak / short passwords',result.weak],['Reused passwords',result.reused],['HTTP websites',result.insecureSites],['Favorites',result.favorites]];for(const [label,value] of entries){const row=document.createElement('div');row.className='detail-field';const a=document.createElement('strong');a.textContent=label;const b=document.createElement('b');b.textContent=String(value??0);row.append(a,b);node.append(row)}const safe=document.createElement('p');safe.className='muted';safe.textContent='This checks password length and reuse only. It is not a breach check and does not guarantee an account is safe.';node.append(safe)});
  box.querySelector('#show-activity').addEventListener('click',async()=>{const result=await desktopRequest('listActivity');$('#tools-title').textContent='Vault activity';const node=$('#tools-content');node.replaceChildren();for(const event of (result.events||[])){const row=document.createElement('div');row.className='detail-field';const a=document.createElement('div');a.className='field-main';const t=document.createElement('strong');t.textContent=event.action;const d=document.createElement('small');d.textContent=`${event.detail} · ${new Date(event.date).toLocaleString()}`;a.append(t,d);row.append(a);node.append(row)}if(!result.events?.length)node.textContent='No recorded activity yet.'});
}
function openSettings(){
  $('#tools-title').textContent='Settings';const node=$('#tools-content');node.replaceChildren();
  const wrap=document.createElement('div');wrap.className='settings-stack';
  const themeLabel=document.createElement('label');themeLabel.className='field';themeLabel.textContent='Appearance';const select=document.createElement('select');select.id='settings-theme';for(const x of ['system','dark','light']){const opt=document.createElement('option');opt.value=x;opt.textContent=x[0].toUpperCase()+x.slice(1);select.append(opt)}select.value=theme;themeLabel.append(select);
  const clipLabel=document.createElement('label');clipLabel.className='field';clipLabel.textContent='Clear copied secrets after';const clip=document.createElement('select');clip.id='settings-clipboard';for(const [value,label] of [['0','Never'],['30','30 seconds'],['45','45 seconds'],['60','60 seconds'],['120','2 minutes']]){const op=document.createElement('option');op.value=value;op.textContent=label;clip.append(op)}
  const saveWrap=document.createElement('label');saveWrap.className='favorite-field';const saveToggle=document.createElement('input');saveToggle.type='checkbox';saveWrap.append(saveToggle,document.createTextNode('Show save-login prompts on websites'));
  const sectionWrap=document.createElement('div');sectionWrap.className='settings-stack';sectionWrap.innerHTML='<strong>Sidebar sections</strong>';
  const toggles={showCards:'Show payment cards',showNotes:'Show secure notes',showIdentities:'Show identities'};const toggleNodes={};for(const [key,label] of Object.entries(toggles)){const row=document.createElement('label');row.className='favorite-field';const input=document.createElement('input');input.type='checkbox';row.append(input,document.createTextNode(label));sectionWrap.append(row);toggleNodes[key]=input;}
  const help=document.createElement('p');help.className='modal-footnote';help.textContent='Vault records remain in Mac Keychain. Appearance and convenience preferences are stored in extension settings only.';
  wrap.append(themeLabel,clipLabel,saveWrap,sectionWrap,help);node.append(wrap);$('#tools-modal').hidden=false;
  chrome.storage.local.get({clipboardClearSeconds:45,showSavePrompts:true,showCards:true,showNotes:true,showIdentities:true}).then(v=>{clip.value=String(v.clipboardClearSeconds);saveToggle.checked=!!v.showSavePrompts;for(const key of Object.keys(toggles))toggleNodes[key].checked=!!v[key]});
  select.addEventListener('change',()=>setTheme(select.value));clip.addEventListener('change',()=>chrome.storage.local.set({clipboardClearSeconds:Number(clip.value)}));saveToggle.addEventListener('change',()=>chrome.storage.local.set({showSavePrompts:saveToggle.checked}));
  for(const [key,input] of Object.entries(toggleNodes))input.addEventListener('change',()=>chrome.storage.local.set({[key]:input.checked}).then(renderList));
}

function bytesToBase64(bytes){let binary='';for(let i=0;i<bytes.length;i+=0x8000)binary+=String.fromCharCode(...bytes.subarray(i,i+0x8000));return btoa(binary)}
function base64ToBytes(value){const binary=atob(value);const bytes=new Uint8Array(binary.length);for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);return bytes}
async function deriveBackupKey(passphrase,salt){const base=await crypto.subtle.importKey('raw',new TextEncoder().encode(passphrase),'PBKDF2',false,['deriveKey']);return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations:600000,hash:'SHA-256'},base,{name:'AES-GCM',length:256},false,['encrypt','decrypt'])}
async function exportEncryptedBackup(){const pass=$('#backup-passphrase').value;if(pass.length<12)throw new Error('Use a backup passphrase with at least 12 characters.');const vault=await desktopRequest('exportVault');const salt=crypto.getRandomValues(new Uint8Array(16)),iv=crypto.getRandomValues(new Uint8Array(12));const key=await deriveBackupKey(pass,salt);const plain=new TextEncoder().encode(JSON.stringify(vault));if(plain.byteLength>600*1024)throw new Error('This vault is too large for the current native messaging backup limit. Split or archive old records before exporting.');const cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,plain);const payload={format:'vaultline-encrypted-backup',version:1,kdf:'PBKDF2-SHA-256',iterations:600000,salt:bytesToBase64(salt),iv:bytesToBase64(iv),ciphertext:bytesToBase64(new Uint8Array(cipher))};const blob=new Blob([JSON.stringify(payload,null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`vaultline-backup-${new Date().toISOString().slice(0,10)}.vaultline`;a.click();setTimeout(()=>URL.revokeObjectURL(url),3000);$('#backup-modal').hidden=true;$('#backup-passphrase').value='';showToast('Encrypted vault backup created. Store it somewhere private.')}
async function importEncryptedBackup(file){const pass=$('#backup-passphrase').value;if(pass.length<12)throw new Error('Enter the backup passphrase first.');if(!file||file.size>1000000)throw new Error('Backup file is too large for the current native messaging limit (maximum 1 MB).');const payload=JSON.parse(await file.text());if(payload.format!=='vaultline-encrypted-backup'||payload.version!==1||payload.kdf!=='PBKDF2-SHA-256'||payload.iterations!==600000)throw new Error('Unsupported or invalid backup file.');const salt=base64ToBytes(payload.salt),iv=base64ToBytes(payload.iv),cipher=base64ToBytes(payload.ciphertext);const key=await deriveBackupKey(pass,salt);let plain;try{plain=await crypto.subtle.decrypt({name:'AES-GCM',iv},key,cipher)}catch{throw new Error('Incorrect backup passphrase or damaged backup file.')}if(plain.byteLength>600*1024)throw new Error('Backup contents exceed the supported restore size.');const data=JSON.parse(new TextDecoder().decode(plain));if(data.format!=='vaultline-backup-v1')throw new Error('Backup contents are not recognized.');const result=await desktopRequest('importVault',{logins:data.logins||[],cards:data.cards||[],notes:data.notes||[],identities:data.identities||[]});$('#backup-modal').hidden=true;$('#backup-passphrase').value='';await refreshLogins();showToast(`Restored ${result.imported||0} records. Existing matching IDs were updated.`)}

async function initialize() {
  const settings = await chrome.storage.local.get(THEME_KEY);
  setTheme(['light', 'dark', 'system'].includes(settings[THEME_KEY]) ? settings[THEME_KEY] : 'system');
  const params = new URLSearchParams(location.search);
  const tabId = Number.parseInt(params.get('tabId') || '-1', 10);
  if (Number.isInteger(tabId) && tabId >= 0) {
    targetTabId = tabId;
    try {
      const tab = await chrome.tabs.get(tabId);
      if (typeof tab.url === 'string' && /^https?:\/\//i.test(tab.url)) { targetUrl = tab.url; targetHost = normalizeHost(targetUrl); }
    } catch { targetTabId = -1; }
  }
  await connect();
}

$('#retry-connect').addEventListener('click', connect);
$('#refresh-button').addEventListener('click', async () => { try { await refreshLogins(); showToast('Login list refreshed.'); } catch (error) { showToast(error.message); } });
$('#add-button').addEventListener('click', () => openModal());

$('#add-card-button').addEventListener('click', () => openCardModal());
$('#view-logins').addEventListener('click', () => { viewMode = 'logins'; selectedId = entries[0]?.id || null; revealedCardId = null; revealedCardNumber = ''; clearTimeout(cardRevealTimer); render(); });
$('#view-cards').addEventListener('click', () => { viewMode = 'cards'; selectedId = cards[0]?.id || null; revealedId = null; revealedPassword = ''; clearTimeout(revealTimer); render(); });
$('#view-notes').addEventListener('click',()=>{viewMode='notes';selectedNoteFull=null;selectedId=notes[0]?.id||null;render();if(selectedId)loadSelectedNote()});
$('#view-identities').addEventListener('click',()=>{viewMode='identities';selectedIdentityFull=null;selectedId=identities[0]?.id||null;render();if(selectedId)loadSelectedIdentity()});
$('#add-note-button').addEventListener('click',()=>openNoteModal());$('#add-identity-button').addEventListener('click',()=>openIdentityModal());
$('#note-form').addEventListener('submit',saveNote);$('#note-modal-close').addEventListener('click',closeNoteModal);$('#note-cancel').addEventListener('click',closeNoteModal);
$('#identity-form').addEventListener('submit',saveIdentity);$('#identity-modal-close').addEventListener('click',closeIdentityModal);$('#identity-cancel').addEventListener('click',closeIdentityModal);
$('#history-close').addEventListener('click',()=>$('#history-modal').hidden=true);$('#backup-close').addEventListener('click',()=>$('#backup-modal').hidden=true);$('#backup-button').addEventListener('click',()=>$('#backup-modal').hidden=false);
$('#backup-export').addEventListener('click',()=>exportEncryptedBackup().catch(e=>showToast(e.message)));$('#backup-import').addEventListener('click',()=>$('#backup-file').click());$('#backup-file').addEventListener('change',()=>{const file=$('#backup-file').files?.[0];if(file)importEncryptedBackup(file).catch(e=>showToast(e.message));$('#backup-file').value='';});$('#security-button').addEventListener('click',openSecurityCenter);$('#settings-button').addEventListener('click',openSettings);$('#tools-close').addEventListener('click',()=>$('#tools-modal').hidden=true);
$('#empty-add-button').addEventListener('click',()=>{if(viewMode==='notes')openNoteModal();else if(viewMode==='identities')openIdentityModal();else if(viewMode==='cards')openCardModal();else openModal()});
$('#capture-button').addEventListener('click', captureFromPage);
$('#modal-close').addEventListener('click', closeModal);
$('#modal-cancel').addEventListener('click', closeModal);
$('#login-form').addEventListener('submit', saveLogin);
$('#card-modal-close').addEventListener('click', closeCardModal);
$('#card-modal-cancel').addEventListener('click', closeCardModal);
$('#card-form').addEventListener('submit', saveCard);
$('#card-number-toggle').addEventListener('click', () => { const input = $('#card-number'); input.type = input.type === 'password' ? 'text' : 'password'; $('#card-number-toggle').textContent = input.type === 'password' ? 'Show' : 'Hide'; });
$('#field-website').addEventListener('change', () => { if (!$('#field-title').value.trim()) $('#field-title').value = normalizeHost($('#field-website').value); });
$('#generate-button').addEventListener('click', () => { $('#field-password').value = randomPassword(); $('#field-password').type = 'text'; });
$('#generate-passphrase-button').addEventListener('click',()=>{$('#field-password').value=randomPassphrase();$('#field-password').type='text';showToast('A random passphrase was generated.');});
$('#search-input').addEventListener('input', renderList);
$('#theme-button').addEventListener('click', () => setTheme(theme === 'dark' ? 'light' : 'dark'));
$('#lock-button').addEventListener('click', lockVault);
$('#login-list').addEventListener('click', (event) => {
  const row = event.target.closest('[data-id]');
  if (!row) return;
  selectedId = row.dataset.id; revealedId = null; revealedPassword = ''; revealedCardId = null; revealedCardNumber = ''; selectedNoteFull=null; selectedIdentityFull=null; clearTimeout(revealTimer); clearTimeout(cardRevealTimer); render();
  if(viewMode==='notes') loadSelectedNote(); if(viewMode==='identities') loadSelectedIdentity();
});
$('#detail-panel').addEventListener('click', async (event) => {
  const action = event.target.closest('[data-action]')?.dataset.action;
  if (!action) return;
  try {
    if (viewMode === 'cards') { if(action==='autofill-card'){await fillSelectedCard();return;} await cardAction(action); return; }
    if (viewMode === 'notes') { if(action==='edit-note'){const n=notes.find(x=>x.id===selectedId);if(n){const full=await desktopRequest('getNote',{id:n.id});openNoteModal({...n,...full});}} else if(action==='delete-note') await deleteNote(); return; }
    if (viewMode === 'identities') { await identityAction(action); return; }
    if (action === 'edit') await editSelected();
    else if (action === 'autofill') await fillSelected();
    else if (action === 'copy-username') await copyField('username');
    else if (action === 'copy-password') await copyField('password');
    else if (action === 'reveal-password') await revealPassword();
    else if (action === 'hide-password') { revealedId = null; revealedPassword = ''; clearTimeout(revealTimer); renderDetail(); }
    else if (action === 'delete') await deleteSelected();
    else if (action === 'view-history') await viewPasswordHistory();
    else if (action === 'open-site') { const record = entries.find((item) => item.id === selectedId); if (record) chrome.tabs.create({ url: record.website }); }
  } catch (error) { showToast(error.message || 'The action could not be completed.'); }
});
$('#login-modal').addEventListener('click', (event) => { if (event.target === $('#login-modal')) closeModal(); });
$('#card-modal').addEventListener('click', (event) => { if (event.target === $('#card-modal')) closeCardModal(); });
window.addEventListener('keydown',(event)=>{if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='k'){event.preventDefault();$('#search-input').focus()}if((event.metaKey||event.ctrlKey)&&event.key.toLowerCase()==='n'){event.preventDefault();if(viewMode==='logins')openModal();else if(viewMode==='cards')openCardModal();else if(viewMode==='notes')openNoteModal();else openIdentityModal()}if(event.key==='Escape'){closeNoteModal();closeIdentityModal();$('#history-modal').hidden=true;$('#backup-modal').hidden=true;$('#tools-modal').hidden=true}});
window.addEventListener('pagehide', () => {
  clearTimeout(revealTimer); clearTimeout(cardRevealTimer);
  revealedId = null; revealedPassword = ''; revealedCardId = null; revealedCardNumber = ''; selectedNoteFull=null; selectedIdentityFull=null;
  $('#field-password').value = '';
  $('#login-form').reset();
  $('#card-number').value = ''; $('#card-form').reset();
  editingId = null; editingCardId = null;
});
matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () => { if (theme === 'system') setTheme('system'); });

initialize().catch((error) => showConnect(error.message || 'Vaultline could not initialize.'));
