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
// WstxMcp::AutomationIndicator (#74): the socket that has carried an automation.state, so that
// the operating client, loaded after the first snapshots, reads GET /automation only after one.
let automationAnnounced = null;
// #82 FreeTxSlotMarks: the socket's latest free_tx_slots.state value, for an operating client that
// loads after it.
let freeTxSlotsHeld = null;
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
let loginRetry = null;
const loginRetryText = () => `Slow link · Retrying authorization (attempt ${loginRetry.attempt} of ${loginRetry.attempts})…`;
function showAuthorizationUnavailable(error) {
  const condition = error?.authorizationCondition;
  if (condition === 'explicit-in-progress' && loginRetry) {stale(); connection.textContent = loginRetryText() + ' · station data stale'; login.hidden = true; return;}
  const reasons = {'credential-missing': 'Browser credential missing \u00b7 authorize this station',
    'credential-invalid': 'Browser credential invalid \u00b7 station data stale',
    'credential-storage-unavailable': 'Browser credential storage unavailable \u00b7 station data stale',
    'retained-transient': error?.status === 429 ? 'Authorization rate limited \u00b7 station data stale' : error?.status === 503 ?
      'Authorization persistence unavailable \u00b7 station data stale' : 'Retained authorization unavailable \u00b7 retrying',
    'retained-rejected': 'Retained authorization not accepted or identity changed \u00b7 station data stale',
    'enrollment-pending': 'Authorization enrollment outcome unknown \u00b7 station data stale',
    'explicit-in-progress': 'Authorization in progress \u00b7 station data stale'};
  stale(); connection.textContent = Object.hasOwn(reasons, condition) ? reasons[condition] : 'Authorization unavailable \u00b7 station data stale'; login.hidden = condition !== 'credential-missing';
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
    catch (error) {
      if (attempt !== connecting) return;
      showAuthorizationUnavailable(error);
      clearTimeout(timer); timer = setTimeout(connect, 4000); return;
    }
    if (attempt !== connecting || !authorized()) return;
  }
  clearTimeout(timer);
  if (socket?.readyState === WebSocket.OPEN || socket?.readyState === WebSocket.CONNECTING) return;
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
      if (message.type === 'automation.state') automationAnnounced = current;
      if (message.type === 'free_tx_slots.state' && message.data) freeTxSlotsHeld = {current, value: message.data.free_tx_slots};
      window.dispatchEvent(new CustomEvent('station-message', {detail: {message, current}}));
      // WstxStationProtocol::PushedStationState: the first status of a socket reads the profile, then only a newer announced revision does.
      if (message.type === 'profile.state' && profileRefresh.initialized && (message.data?.boot_id !== profileData?.boot_id || message.data?.revision > profileData?.revision)) refreshProfile(current, profileRefresh).catch(() => disconnect(current));
      if (message.type === 'station.status' && message.id === pendingId && typeof message.data?.version === 'string' && message.data.radio === 'unconfigured') {
        if (stationUpdated(message.data.build)) return;
        if (profileMode) {
          if (!profileRefresh.initialized) {
            if (!await refreshProfile(current, profileRefresh)) return;
            if (current !== socket || current.readyState !== WebSocket.OPEN) return;
            profileRefresh.initialized = true;
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
// WstxStationProtocol::PageUpdate (#51): a page served with another client build than the
// station's reloads itself once (local settings stay in browser storage). The operating
// screen may hold the reload (window.wstxReloadHeld: QSO, dialog, unsaved settings); it then
// shows its "Station updated" chip. A second mismatch for the same build never loops.
const pageBuild = document.body.dataset.build;
function stationUpdated(build) {
  if (typeof build !== 'string' || !pageBuild || build === pageBuild) return false;
  let reloaded = null; try {reloaded = sessionStorage.getItem('wstx.reloaded-build.v1');} catch {}
  if (reloaded !== build && !window.wstxReloadHeld?.()) {
    try {sessionStorage.setItem('wstx.reloaded-build.v1', build);} catch {}
    location.reload(); return true;
  }
  window.dispatchEvent(new CustomEvent('station-updated', {detail: build}));
  return false;
}
// WstxStationProtocol::BrowserLinkLifecycle (#8): the page's own deferred client download shares
// the one station-to-browser bottleneck, so on a 32 kbit/s link the station's messages can queue
// behind it for more than 12 s. While one is pending the silence bound is 30 s; its completion
// or failure counts as a message. No other request extends the bound.
let deferredDownloads = 0;
function deferredDownload(promise) {
  deferredDownloads++;
  return promise.finally(() => {deferredDownloads--; lastMessage = Date.now();});
}
setInterval(() => { if (socket?.readyState === WebSocket.OPEN && Date.now() - lastMessage > (deferredDownloads ? 30000 : 12000)) disconnect(socket); }, 1000);
refresh.addEventListener('click', requestStatus);
login.addEventListener('submit', async event => {
  event.preventDefault(); const input = document.querySelector('#token');
  let secret = input.value, submittedEpoch = null; input.value = '';
  try {
    if (selectedHttps && !authorization) throw new Error('Authorization component unavailable');
    if (authorization) {
      const beforeEpoch = authorization.snapshot().epoch, submitted = authorization.bootstrap(secret);
      const afterEpoch = authorization.snapshot().epoch;
      if (afterEpoch !== beforeEpoch) submittedEpoch = afterEpoch;
      secret = null; await submitted;
      if (submittedEpoch === null || authorization.snapshot().epoch !== submittedEpoch || !authorization.snapshot().ready) return;
    }
    else {const response = await fetch('/session', {method: 'POST', body: secret}); secret = null; if (!response.ok) throw new Error('Access denied');}
    document.querySelector('#login-error').textContent = ''; clearTimeout(timer);
    if (socket && socket.readyState < WebSocket.CLOSING) { socket.onclose = null; socket.close(); }
    retry = 1000; connect();
  } catch (error) {
    if (authorization && (submittedEpoch === null || authorization.snapshot().epoch !== submittedEpoch || authorization.snapshot().ready)) return;
    if (error?.authorizationCondition) {
      showAuthorizationUnavailable(error); document.querySelector('#login-error').textContent = '';
    } else document.querySelector('#login-error').textContent = 'Could not authenticate. Check your token and connection.';
  }
  finally {secret = null;}
});
const logoutButton = document.querySelector('#logout'), forgetButton = document.querySelector('#forget');
// CL-022-01 slow-link setup retry: the token login stays in progress; say so instead of failing.
addEventListener('station-authorization-retry', event => {
  if (!authorization || event.detail.epoch !== authorization.snapshot().epoch) return;
  loginRetry = event.detail; document.querySelector('#login-error').textContent = loginRetryText();
  if (authorization.snapshot().state === 'authorizing') {stale(); connection.textContent = loginRetryText() + ' · station data stale';}
});
addEventListener('station-authorization', event => {
  if (!authorization || event.detail.epoch !== authorization.snapshot().epoch) return;
  if (event.detail.state !== 'authorizing') loginRetry = null;
  logoutButton.hidden = !event.detail.ready;
  forgetButton.hidden = !['retained-rejected', 'credential-invalid'].includes(event.detail.authorizationCondition);
  if (event.detail.ready) return;
  if (event.detail.authorizationCondition) showAuthorizationUnavailable(event.detail);
  else {stale(); connection.textContent = 'Authorization unavailable · station data stale';}
  if (socket && socket.readyState < WebSocket.CLOSING) {socket.onclose = null; socket.close();}
  clearTimeout(timer); timer = setTimeout(connect, 4000);
});
for (const [button, action] of [[logoutButton, 'logout'], [forgetButton, 'forget']]) {
  button.addEventListener('click', async () => {
    button.disabled = true;
    try {await authorization[action]();} catch {} finally {button.disabled = false;}
  });
}
connect();

// #44 CL-044-11: the managed AGC is sent only while the CAT endpoint names a radio
// with a known CI-V AGC command (the row is shown), so other radios carry no radio key.
function agcManaged() {
  return document.querySelector('#control-mode').value === 'cat' && /^(icom7300:\/\/COM[0-9]{1,3}\?|COM[0-9]{1,3}$)/i.test(document.querySelector('#control-endpoint').value);
}
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
  applyProfile(data, reload);
  return true;
}
// One authoritative snapshot, from a GET or from the save's own 200 reply (CL-073-01):
// the ProfileRepresentation checks, then SnapshotApplicable, then the form and shown profile.
function applyProfile(data, reload) {
  if (typeof data?.profile_id !== 'string' || typeof data.boot_id !== 'string' || !Number.isSafeInteger(data.revision) || !data.settings) throw new Error('Invalid profile');
  if (profileData && data.boot_id === profileData.boot_id && data.revision < profileData.revision) return false;
  const newBoot = !!profileData && data.boot_id !== profileData.boot_id;
  profileData = data; document.querySelector('#profile-panel').hidden = false;
  // WstxStationProtocol::PushedStationState (#74): a new boot is learned here; each view of
  // station state drops what it holds at once and shows its freshly loaded form.
  if (newBoot) window.dispatchEvent(new CustomEvent('station-boot', {detail: data.boot_id}));
  // FR-023: the connection type is read-only and shown as saved.
  document.querySelector('#settings select:not([id])').value = data.connection_type === 'native_flex' ? 'native_flex' : 'standard';
  for (const [id, text] of [['#profile-id', data.profile_id], ['#profile-name', data.settings.display_name], ['#profile-endpoint', data.endpoint], ['#profile-boot', data.boot_id], ['#profile-revision', String(data.revision)]]) document.querySelector(id).textContent = text;
  document.title = `${data.settings.display_name} - ${location.port || (location.protocol === 'https:' ? 443 : 80)} - WSTX`;
  if (reload || !dirty) {
    const s = data.settings;
    for (const [id, value] of [['#display-name', s.display_name], ['#callsign', s.callsign], ['#locator', s.locator], ['#audio-input', s.audio.input_device], ['#audio-output', s.audio.output_device], ['#control-mode', s.control.mode], ['#control-endpoint', s.control.endpoint], ['#ptt-mode', s.control.ptt]]) {
      const field = document.querySelector(id);
      // CL-044-08: an audio select keeps a saved endpoint it does not list yet (named later).
      if (id.startsWith('#audio-') && value && ![...field.options].some(o => o.value === value)) field.add(new Option('Saved device', value));
      field.value = value ?? '';
    }
    document.querySelector('#control-agc').value = s.radio?.agc ?? 'SLOW';
    document.querySelector('#control-power-limit').value = s.radio?.power_limit_pct ?? '';
    window.dispatchEvent(new CustomEvent('profile-fields'));
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
  if (!stationContext(socket, authorization?.snapshot().epoch)) return;
  saving = true;
  const button = document.querySelector('#settings-save');
  const controls = [...settingsForm.elements].map(element => [element, element.disabled]);
  for (const [element] of controls) element.disabled = true;
  try {
    const response = await stationFetch('/profile', {method: 'PUT', signal: AbortSignal.timeout(10000), headers: {'Content-Type': 'application/json'}, body: JSON.stringify({profile_id: profileData.profile_id, revision: editingRevision, settings: {...formSettings(), ...(agcManaged() ? {radio: {agc: document.querySelector('#control-agc').value, ...(document.querySelector('#control-power-limit').value ? {power_limit_pct: Number(document.querySelector('#control-power-limit').value)} : {})}} : {})}})});
    // CL-073-01: the reply is the outcome. A control save advances the safety revision and
    // so drops this page's socket and transport while the reply is on its way; no check of
    // the socket, the authorization epoch or the shown snapshot after the reply decides it.
    const result = await response.json();
    if (!response.ok) {
      if (response.status === 409) {conflict = true; settingsResult.textContent = 'Settings changed or revision limit reached. Reload saved settings before saving.';}
      else if (result.error?.code === 'audio_device_not_endpoint') settingsResult.textContent = `${result.error.field} must be a Windows audio endpoint ID ({0.0.x.00000000}.{GUID}), not a device name.`;
      else settingsResult.textContent = result.error?.field ? `Invalid ${result.error.field}. Check this field.` : `Could not save settings (${result.error?.code || 'connection error'}).`;
      return;
    }
    // The 200 body is the authoritative snapshot, applied as a GET's (no follow-up GET);
    // an invalid body leaves the outcome unknown. A newer shown same-boot snapshot is kept
    // and the form takes it (CL-073-01), so the next Apply edits the newer revision.
    if (!applyProfile(result, true)) applyProfile(profileData, true);
    settingsResult.textContent = `Saved revision ${result.revision}`;
  } catch {settingsResult.textContent = 'Save outcome unknown. Reload saved settings before retrying.'; conflict = true;}
  finally {saving = false; for (const [element, disabled] of controls) element.disabled = disabled; button.disabled = saving || conflict;}
});
