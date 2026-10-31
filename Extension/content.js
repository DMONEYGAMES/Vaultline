(() => {
  if (window.top !== window || location.protocol === 'chrome-extension:') return;
  const host = location.hostname.toLowerCase();
  if (!host || !['http:', 'https:'].includes(location.protocol)) return;
  let promptRoot = null;
  let lastFingerprint = '';
  const visible = (el) => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el); return r.width > 0 && r.height > 0 && s.display !== 'none' && s.visibility !== 'hidden' && !el.disabled; };
  const capture = () => {
    const pass = [...document.querySelectorAll('input[type="password"]')].filter(visible).find(el => el.value);
    if (!pass) return null;
    const form = pass.form || pass.closest('form') || document;
    const users = [...form.querySelectorAll('input')].filter(el => visible(el) && el !== pass && ['text','email','tel'].includes((el.type || 'text').toLowerCase()));
    const rank = el => { const hint = `${el.autocomplete} ${el.name} ${el.id} ${el.placeholder}`.toLowerCase(); return (el.autocomplete === 'username' ? 100 : 0) + (el.type === 'email' ? 40 : 0) + (/user|email|login|account/.test(hint) ? 20 : 0) - (/search|coupon|promo|zip|postal|address/.test(hint) ? 100 : 0); };
    users.sort((a,b) => rank(b)-rank(a));
    return { title: document.title || host, username: users[0]?.value || '', password: pass.value };
  };
  const dismiss = () => { promptRoot?.remove(); promptRoot = null; };
  const offerSave = async () => {
    try { const pref = await chrome.storage.local.get({showSavePrompts:true}); if (!pref.showSavePrompts) return; } catch { return; }
    const fields = capture(); if (!fields) return;
    const fingerprint = `${host}|${fields.username}|${fields.password}`;
    if (fingerprint === lastFingerprint) return;
    lastFingerprint = fingerprint;
    dismiss();
    promptRoot = document.createElement('div');
    const shadow = promptRoot.attachShadow({ mode: 'closed' });
    const wrap = document.createElement('div');
    wrap.innerHTML = `<style>:host{all:initial}div.card{position:fixed;z-index:2147483647;right:18px;bottom:18px;width:310px;padding:16px;border-radius:14px;background:#111d30;color:#eaf2ff;border:1px solid #304565;box-shadow:0 14px 44px #0008;font:13px -apple-system,BlinkMacSystemFont,sans-serif}strong{display:block;font-size:14px;margin-bottom:6px}p{margin:0 0 12px;color:#a9bbd2;line-height:1.4}.row{display:flex;gap:8px;justify-content:flex-end}button{border:0;border-radius:8px;padding:8px 11px;font-weight:700;cursor:pointer}.save{background:#398df4;color:white}.later{background:#22344e;color:#dce9fb}</style><div class="card"><strong>Save this login to Vaultline?</strong><p>${host.replace(/[&<>"']/g, '')} · ${String(fields.username).replace(/[&<>"']/g, '').slice(0,80) || 'Username not detected'}</p><div class="row"><button class="later">Not now</button><button class="save">Save to Mac</button></div></div>`;
    shadow.append(wrap); document.documentElement.append(promptRoot);
    shadow.querySelector('.later').addEventListener('click', dismiss);
    shadow.querySelector('.save').addEventListener('click', async () => {
      const button = shadow.querySelector('.save'); button.disabled = true; button.textContent = 'Saving…';
      try {
        const fresh = capture(); if (!fresh) throw new Error('Login fields are no longer available.');
        const result = await chrome.runtime.sendMessage({ type: 'VAULTLINE_CAPTURE_SAVE', payload: fresh });
        if (!result?.ok) throw new Error(result?.error || 'Could not save login.');
        button.textContent = 'Saved'; setTimeout(dismiss, 1000);
      } catch { button.textContent = 'Open Vaultline to save'; button.disabled = false; }
    });
  };
  const schedule = () => setTimeout(offerSave, 250);
  document.addEventListener('input', (event) => { if (event.target instanceof HTMLInputElement && (event.target.type === 'password' || event.target.autocomplete === 'username')) schedule(); }, true);
  document.addEventListener('focusout', schedule, true);
  chrome.runtime.onMessage.addListener(message => { if (message?.type === 'VAULTLINE_SHOW_SAVE_PROMPT') offerSave(); });
})();
