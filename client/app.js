'use strict';
const connection = document.querySelector('#connection');
const version = document.querySelector('#version');
const radio = document.querySelector('#radio');
const login = document.querySelector('#login');
const refresh = document.querySelector('#refresh');
const profileMode = document.body.dataset.profile === 'true';
const selectedHttps = profileMode && location.protocol === 'https:';
const authorization = selectedHttps ? window.stationAuthorization : null;
const authorized = () => !selectedHttps || authorization?.snapshot().ready === true;
const stationFetch = (path, options) => authorization ? authorization.fetch(path, options) : selectedHttps ?
  Promise.reject(new Error('Station authorization component unavailable')) : fetch(path, options);
const stationContext = (current, authEpoch) => current === socket && current?.readyState === WebSocket.OPEN &&
  authorized() && (!authorization || authorization.snapshot().epoch === authEpoch);
const settingsForm = document.querySelector('#settings');
const settingsResult = document.querySelector('#settings-result');
let profileData, editingRevision, dirty = false, conflict = false, saving = false;
let socket, timer, pendingId, handshakeProbe;
let retry = 1000, lastMessage = 0, nextId = 1;
function stale() { connection.textContent = 'Disconnected · stale'; connection.dataset.state = 'stale'; refresh.disabled = true; window.dispatchEvent(new Event('station-stale')); }
function requestStatus() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  pendingId = nextId++; refresh.disabled = true;
  socket.send(JSON.stringify({v: 1, type: 'station.get', id: pendingId}));
}
function disconnect(current) {
  if (current !== socket) return;
  stale(); current.onclose = null; current.onmessage = null;
  current.close();
  const retained = selectedHttps && authorization && ['ready', 'recovering'].includes(authorization.snapshot().state);
  login.hidden = location.protocol !== 'https:' || retained;
  clearTimeout(timer); timer = setTimeout(connect, retry); retry = Math.min(retry * 2, 4000);
}
let connecting = 0;
async function connect() {
  handshakeProbe?.abort(); handshakeProbe = null;
  clearTimeout(timer);
  const attempt = ++connecting;
  if (selectedHttps && !authorization) {
    stale(); connection.textContent = 'Authorization component unavailable · station data stale'; login.hidden = true; return;
  }
  if (authorization) {
    try {await authorization.ensureReady();}
    catch {
      if (attempt !== connecting) return;
      stale(); connection.textContent = 'Authorization unavailable · station data stale'; login.hidden = false;
      timer = setTimeout(connect, 4000); return;
    }
    if (attempt !== connecting || !authorized()) return;
  }
  socket = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`, 'wstx.v1');
  const current = socket, socketEpoch = authorization?.snapshot().epoch;
  let opened = false, lost = false;
  const profileRefresh = {initialized: false, running: null, again: false};
  const loseSocket = () => {
    if (current !== socket || lost) return;
    lost = true; clearTimeout(openingTimer); disconnect(current);
    const auth = authorization?.snapshot();
    if (!selectedHttps || opened || !auth?.ready || auth.epoch !== socketEpoch) return;
    // A failed handshake cannot expose its HTTP status. Only the existing protected
    // read may observe401 and start the manager's independent coalesced renewal.
    const probe = new AbortController(); handshakeProbe?.abort(); handshakeProbe = probe;
    authorization.fetch('/profile', {cache: 'no-store', signal: AbortSignal.any([probe.signal, AbortSignal.timeout(10000)])})
      .then(response => response.body?.cancel().catch(() => {}))
      .catch(() => {})
      .finally(() => {if (handshakeProbe === probe) handshakeProbe = null;});
  };
  const openingTimer = setTimeout(() => {if (current.readyState === WebSocket.CONNECTING) loseSocket();}, 5000);
  current.onopen = () => {
    opened = true; clearTimeout(openingTimer);
    if (lost || current !== socket || !authorized()) return;
    lastMessage = Date.now(); requestStatus();
  };
  current.onmessage = async event => {
    if (current !== socket || !authorized()) return;
    try {
      const message = JSON.parse(event.data);
      if (message.v !== 1) throw new Error('Unsupported version');
      lastMessage = Date.now();
      window.dispatchEvent(new CustomEvent('station-message', {detail: {message, current}}));
      if (message.type === 'station.status' && message.id === pendingId && typeof message.data?.version === 'string' && message.data.radio === 'unconfigured') {
        if (profileMode) {
          if (!profileRefresh.initialized) {
            if (!await refreshProfile(current, profileRefresh)) return;
            if (current !== socket || current.readyState !== WebSocket.OPEN) return;
            profileRefresh.initialized = true;
          } else {
            refreshProfile(current, profileRefresh).catch(() => disconnect(current));
          }
        }
        if (current !== socket || current.readyState !== WebSocket.OPEN || !authorized()) return;
        version.textContent = message.data.version; radio.textContent = 'Radio not configured';
        connection.textContent = 'Connected'; connection.dataset.state = 'connected';
        document.querySelector('#updated').textContent = new Date().toLocaleTimeString([], {hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3});
        refresh.disabled = false;
        retry = 1000; login.hidden = true;
        if (profileMode) window.dispatchEvent(new CustomEvent('station-ready', {detail: current}));
      }
    } catch { disconnect(current); }
  };
  current.onclose = loseSocket;
}
setInterval(() => { if (socket?.readyState === WebSocket.OPEN && Date.now() - lastMessage > 12000) disconnect(socket); }, 1000);
refresh.addEventListener('click', requestStatus);
login.addEventListener('submit', async event => {
  event.preventDefault(); const input = document.querySelector('#token');
  let secret = input.value; input.value = '';
  try {
    if (selectedHttps && !authorization) throw new Error('Authorization component unavailable');
    if (authorization) {const submitted = authorization.bootstrap(secret); secret = null; await submitted;}
    else {const response = await fetch('/session', {method: 'POST', body: secret}); secret = null; if (!response.ok) throw new Error('Access denied');}
    document.querySelector('#login-error').textContent = ''; clearTimeout(timer);
    if (socket && socket.readyState < WebSocket.CLOSING) { socket.onclose = null; socket.close(); }
    retry = 1000; connect();
  } catch { document.querySelector('#login-error').textContent = 'Could not authenticate. Check your token and connection.'; }
  finally {secret = null;}
});
addEventListener('station-authorization', event => {
  if (!authorization || event.detail.ready) return;
  stale(); connection.textContent = 'Authorization unavailable · station data stale';
  if (socket && socket.readyState < WebSocket.CLOSING) {socket.onclose = null; socket.close();}
  clearTimeout(timer); timer = setTimeout(connect, 4000);
});
connect();

function formSettings() {
  const value = id => document.querySelector(id).value;
  return {display_name: value('#display-name'), callsign: value('#callsign'), locator: value('#locator'),
    audio: {input_device: value('#audio-input') || null, output_device: value('#audio-output') || null},
    control: {mode: value('#control-mode'), endpoint: value('#control-endpoint') || null, ptt: value('#ptt-mode')}};
}
// Status refreshes share one request and retain only one follow-up while HTTP is
// busy. Each socket owns its own queue, so old completions cannot clear a new queue.
function refreshProfile(current, state) {
  if (state.running) {state.again = true; return state.running;}
  state.running = (async () => {
    do {
      state.again = false;
      if (!await loadProfile(false, current)) return false;
      if (current !== socket || current.readyState !== WebSocket.OPEN) return false;
      if (state.initialized) window.dispatchEvent(new CustomEvent('station-ready', {detail: current}));
    } while (state.again);
    return true;
  })().catch(error => {
    if (current === socket && current.readyState === WebSocket.OPEN) {
      settingsResult.textContent = 'Could not load saved settings.';
      disconnect(current);
      connection.textContent = 'Disconnected ? could not load saved settings.';
    }
    return false;
  }).finally(() => {state.running = null;});
  return state.running;
}
async function loadProfile(reload, current = socket) {
  const authEpoch = authorization?.snapshot().epoch;
  if (!stationContext(current, authEpoch)) return false;
  const response = await stationFetch('/profile', {signal: AbortSignal.timeout(10000)});
  if (!stationContext(current, authEpoch)) return false;
  if (!response.ok) {settingsResult.textContent = 'Could not load saved settings.'; throw new Error('Profile unavailable');}
  const data = await response.json();
  if (!stationContext(current, authEpoch)) return false;
  if (typeof data.profile_id !== 'string' || typeof data.boot_id !== 'string' || !Number.isSafeInteger(data.revision) || !data.settings) throw new Error('Invalid profile');
  if (profileData && data.boot_id === profileData.boot_id && data.revision < profileData.revision) return true;
  profileData = data; document.querySelector('#profile-panel').hidden = false;
  for (const [id, text] of [['#profile-id', data.profile_id], ['#profile-name', data.settings.display_name], ['#profile-endpoint', data.endpoint], ['#profile-boot', data.boot_id], ['#profile-revision', String(data.revision)]]) document.querySelector(id).textContent = text;
  document.title = `${data.settings.display_name} - ${location.port || (location.protocol === 'https:' ? 443 : 80)} - WSTX`;
  if (reload || !dirty) {
    const s = data.settings;
    for (const [id, value] of [['#display-name', s.display_name], ['#callsign', s.callsign], ['#locator', s.locator], ['#audio-input', s.audio.input_device], ['#audio-output', s.audio.output_device], ['#control-mode', s.control.mode], ['#control-endpoint', s.control.endpoint], ['#ptt-mode', s.control.ptt]]) document.querySelector(id).value = value ?? '';
    editingRevision = data.revision; dirty = false; conflict = false;
  }
  document.querySelector('#settings-save').disabled = saving || conflict;
  return true;
}
settingsForm.addEventListener('input', () => {dirty = true;});
settingsForm.addEventListener('change', () => {dirty = true;});
document.querySelector('#settings-reload').addEventListener('click', async () => {
  try {if (!await loadProfile(true)) throw new Error('Stale settings'); settingsResult.textContent = 'Loaded saved settings.';} catch {settingsResult.textContent = 'Could not load saved settings.';}
});
settingsForm.addEventListener('submit', async event => {
  event.preventDefault(); if (!profileMode || !profileData || saving || conflict || !authorized()) return;
  const current=socket,authEpoch=authorization?.snapshot().epoch,context=JSON.stringify([profileData.profile_id,profileData.boot_id,profileData.revision]);
  if(!stationContext(current,authEpoch))return;
  saving = true;
  const button = document.querySelector('#settings-save');
  const controls = [...settingsForm.elements].map(element => [element, element.disabled]);
  for (const [element] of controls) element.disabled = true;
  try {
    const response = await stationFetch('/profile', {method: 'PUT', signal: AbortSignal.timeout(10000), headers: {'Content-Type': 'application/json'}, body: JSON.stringify({profile_id: profileData.profile_id, revision: editingRevision, settings: formSettings()})});
    const result = await response.json();
    if(!stationContext(current,authEpoch)||context!==JSON.stringify([profileData.profile_id,profileData.boot_id,profileData.revision]))throw new Error('Stale save completion');
    if (!response.ok) {
      if (response.status === 409) {conflict = true; settingsResult.textContent = 'Settings changed or revision limit reached. Reload saved settings before saving.';}
      else settingsResult.textContent = result.error?.field ? `Invalid ${result.error.field}. Check this field.` : `Could not save settings (${result.error?.code || 'connection error'}).`;
      return;
    }
    if(!await loadProfile(true,current)||!stationContext(current,authEpoch))throw new Error('Stale save completion');
    settingsResult.textContent = `Saved revision ${result.revision}`;
  } catch {settingsResult.textContent = 'Save outcome unknown. Reload saved settings before retrying.'; conflict = true;}
  finally {saving = false; for (const [element, disabled] of controls) element.disabled = disabled; button.disabled = saving || conflict;}
});
