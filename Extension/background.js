'use strict';

const HOST_NAME = 'com.vaultline.bridge';
let nativePort = null;
let nextRequestId = 1;
const pending = new Map();

function disconnectNative(reason = 'desktop-connection-closed') {
  nativePort = null;
  for (const [id, waiter] of pending) {
    clearTimeout(waiter.timer);
    waiter.reject(new Error(reason));
    pending.delete(id);
  }
}

function ensureNativePort() {
  if (nativePort) return nativePort;
  const port = chrome.runtime.connectNative(HOST_NAME);
  nativePort = port;
  port.onMessage.addListener((message) => {
    const waiter = pending.get(message?.requestId);
    if (!waiter) return;
    clearTimeout(waiter.timer);
    pending.delete(message.requestId);
    waiter.resolve(message);
  });
  port.onDisconnect.addListener(() => {
    const message = chrome.runtime.lastError?.message || 'Vaultline Desktop is not connected. Check the native host installation and restart Chrome.';
    disconnectNative(message);
  });
  return port;
}

function desktopRequest(command, payload = {}) {
  return new Promise((resolve, reject) => {
    let port;
    try { port = ensureNativePort(); }
    catch (error) { reject(new Error(error?.message || 'Vaultline Desktop is unavailable.')); return; }

    const requestId = `vlt-${Date.now()}-${nextRequestId++}`;
    const timer = setTimeout(() => {
      pending.delete(requestId);
      reject(new Error('Vaultline Desktop did not respond. Reopen the desktop app and try again.'));
    }, 30000);
    pending.set(requestId, { resolve, reject, timer });
    try { port.postMessage({ requestId, command, payload }); }
    catch (error) {
      clearTimeout(timer);
      pending.delete(requestId);
      reject(new Error(error?.message || 'Could not send a request to Vaultline Desktop.'));
    }
  });
}

chrome.action.onClicked.addListener((tab) => {
  const tabId = Number.isInteger(tab?.id) ? tab.id : -1;
  chrome.tabs.create({ url: chrome.runtime.getURL(`manager.html?tabId=${tabId}`) });
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== 'VAULTLINE_DESKTOP_REQUEST') return false;
  const allowed = new Set(['ping', 'listLogins', 'saveLogin', 'getLogin', 'deleteLogin', 'listCards', 'saveCard', 'getCard', 'deleteCard', 'listNotes', 'saveNote', 'getNote', 'deleteNote', 'listIdentities', 'saveIdentity', 'getIdentity', 'deleteIdentity', 'listActivity', 'exportVault', 'importVault', 'securityAudit', 'lock']);
  const command = String(message.command || '');
  if (!allowed.has(command)) {
    sendResponse({ ok: false, error: 'unsupported-command' });
    return false;
  }
  desktopRequest(command, message.payload || {})
    .then(sendResponse)
    .catch((error) => sendResponse({ ok: false, error: error.message || 'desktop-app-unavailable' }));
  return true;
});

chrome.commands?.onCommand.addListener((command) => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tabId = Number.isInteger(tabs?.[0]?.id) ? tabs[0].id : -1;
    if (command === 'open-vault') chrome.tabs.create({ url: chrome.runtime.getURL(`manager.html?tabId=${tabId}`) });
    if (command === 'save-login-from-page' && tabId >= 0) chrome.tabs.sendMessage(tabId, { type: 'VAULTLINE_SHOW_SAVE_PROMPT' }).catch(() => {});
  });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== 'VAULTLINE_CAPTURE_SAVE') return false;
  const senderURL = sender?.url || sender?.tab?.url || '';
  let hostname = '';
  try { const parsed = new URL(senderURL); if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error(); hostname = parsed.hostname.toLowerCase(); }
  catch { sendResponse({ ok: false, error: 'invalid-source-site' }); return false; }
  const payload = message.payload || {};
  const record = {
    id: crypto.randomUUID(), type: 'login',
    title: String(payload.title || hostname).slice(0, 120),
    website: `https://${hostname}`, username: String(payload.username || '').slice(0, 500),
    password: String(payload.password || '').slice(0, 2000), category: 'Personal', favorite: false, tags: [],
    createdAt: Date.now(), updatedAt: Date.now()
  };
  if (!record.password) { sendResponse({ ok: false, error: 'empty-password' }); return false; }
  desktopRequest('listLogins').then((listed) => {
    const usernameKey = record.username.trim().toLowerCase();
    const existing = usernameKey && Array.isArray(listed.records)
      ? listed.records.find(item => String(item.host || '').toLowerCase() === hostname && String(item.username || '').trim().toLowerCase() === usernameKey)
      : null;
    if (existing) {
      record.id = existing.id;
      record.category = existing.category || 'Personal';
      record.favorite = !!existing.favorite;
      record.tags = Array.isArray(existing.tags) ? existing.tags : [];
      record.createdAt = existing.createdAt || record.createdAt;
    }
    return desktopRequest('saveLogin', { record });
  }).then(sendResponse).catch((error) => sendResponse({ ok: false, error: error.message || 'save-failed' }));
  return true;
});
