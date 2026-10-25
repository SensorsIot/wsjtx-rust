'use strict';
const connection = document.querySelector('#connection');
const version = document.querySelector('#version');
const radio = document.querySelector('#radio');
const login = document.querySelector('#login');
const refresh = document.querySelector('#refresh');
const profileMode = document.body.dataset.profile === 'true';
const settingsForm = document.querySelector('#settings');
const settingsResult = document.querySelector('#settings-result');
let profileData, editingRevision, dirty = false, conflict = false;
let socket, timer, pendingId;
let retry = 1000, lastMessage = 0, nextId = 1;
function stale() { connection.textContent = 'Disconnected · stale'; connection.dataset.state = 'stale'; refresh.disabled = true; }
function requestStatus() {
  if (socket?.readyState !== WebSocket.OPEN) return;
  pendingId = nextId++; refresh.disabled = true;
  socket.send(JSON.stringify({v: 1, type: 'station.get', id: pendingId}));
}
function disconnect(current) {
  if (current !== socket) return;
  stale(); current.onclose = null; current.onmessage = null;
  current.close();
  login.hidden = location.protocol !== 'https:';
  clearTimeout(timer); timer = setTimeout(connect, retry); retry = Math.min(retry * 2, 4000);
}
function connect() {
  clearTimeout(timer);
  socket = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`, 'wstx.v1');
  const current = socket;
  const openingTimer = setTimeout(() => {if (current.readyState === WebSocket.CONNECTING) disconnect(current);}, 5000);
  current.onopen = () => {
    clearTimeout(openingTimer);
    if (current !== socket) return;
    lastMessage = Date.now(); requestStatus();
  };
  current.onmessage = async event => {
    if (current !== socket) return;
    try {
      const message = JSON.parse(event.data);
      if (message.v !== 1) throw new Error('Unsupported version');
      lastMessage = Date.now();
      if (message.type === 'station.status' && message.id === pendingId && typeof message.data?.version === 'string' && message.data.radio === 'unconfigured') {
        if (profileMode && !await loadProfile(false, current)) return;
        version.textContent = message.data.version; radio.textContent = 'Radio not configured';
        connection.textContent = 'Connected'; connection.dataset.state = 'connected';
        document.querySelector('#updated').textContent = new Date().toLocaleTimeString([], {hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit', fractionalSecondDigits: 3});
        refresh.disabled = false;
        retry = 1000; login.hidden = true;
      }
    } catch { disconnect(current); }
  };
  current.onclose = () => {
    clearTimeout(openingTimer); disconnect(current);
  };
}
setInterval(() => { if (socket?.readyState === WebSocket.OPEN && Date.now() - lastMessage > 12000) disconnect(socket); }, 1000);
refresh.addEventListener('click', requestStatus);
login.addEventListener('submit', async event => {
  event.preventDefault(); const input = document.querySelector('#token');
  const secret = input.value; input.value = '';
  try {
    const response = await fetch('/session', {method: 'POST', body: secret});
    if (!response.ok) throw new Error('Access denied');
    document.querySelector('#login-error').textContent = ''; clearTimeout(timer);
    if (socket && socket.readyState < WebSocket.CLOSING) { socket.onclose = null; socket.close(); }
    retry = 1000; connect();
  } catch { document.querySelector('#login-error').textContent = 'Could not authenticate. Check your token and connection.'; }
});
connect();

function formSettings() {
  const value = id => document.querySelector(id).value;
  return {display_name: value('#display-name'), callsign: value('#callsign'), locator: value('#locator'),
    audio: {input_device: value('#audio-input') || null, output_device: value('#audio-output') || null},
    control: {mode: value('#control-mode'), endpoint: value('#control-endpoint') || null, ptt: value('#ptt-mode')}};
}
async function loadProfile(reload, current) {
  const response = await fetch('/profile', {signal: AbortSignal.timeout(10000)});
  if (!response.ok) {settingsResult.textContent = 'Could not load saved settings.'; throw new Error('Profile unavailable');}
  const data = await response.json();
  if (current && current !== socket) return false;
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
  document.querySelector('#settings-save').disabled = conflict;
  return true;
}
settingsForm.addEventListener('input', () => {dirty = true;});
settingsForm.addEventListener('change', () => {dirty = true;});
document.querySelector('#settings-reload').addEventListener('click', async () => {
  try {await loadProfile(true); settingsResult.textContent = 'Loaded saved settings.';} catch {settingsResult.textContent = 'Could not load saved settings.';}
});
settingsForm.addEventListener('submit', async event => {
  event.preventDefault(); if (!profileMode || !profileData || conflict) return;
  const button = document.querySelector('#settings-save');
  const controls = [...settingsForm.elements].map(element => [element, element.disabled]);
  for (const [element] of controls) element.disabled = true;
  try {
    const response = await fetch('/profile', {method: 'PUT', signal: AbortSignal.timeout(10000), headers: {'Content-Type': 'application/json'}, body: JSON.stringify({profile_id: profileData.profile_id, revision: editingRevision, settings: formSettings()})});
    const result = await response.json();
    if (!response.ok) {
      if (response.status === 409) {conflict = true; settingsResult.textContent = 'Settings changed or revision limit reached. Reload saved settings before saving.';}
      else settingsResult.textContent = result.error?.field ? `Invalid ${result.error.field}. Check this field.` : `Could not save settings (${result.error?.code || 'connection error'}).`;
      return;
    }
    dirty = false; await loadProfile(true); settingsResult.textContent = `Saved revision ${result.revision}`;
  } catch {settingsResult.textContent = 'Save outcome unknown. Reload saved settings before retrying.'; conflict = true;}
  finally {for (const [element, disabled] of controls) element.disabled = disabled; button.disabled = conflict;}
});
