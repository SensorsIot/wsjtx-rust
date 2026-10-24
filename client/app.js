'use strict';
const connection = document.querySelector('#connection');
const version = document.querySelector('#version');
const radio = document.querySelector('#radio');
const login = document.querySelector('#login');
const refresh = document.querySelector('#refresh');
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
  current.onmessage = event => {
    if (current !== socket) return;
    try {
      const message = JSON.parse(event.data);
      if (message.v !== 1) throw new Error('Unsupported version');
      lastMessage = Date.now();
      if (message.type === 'station.status' && message.id === pendingId && typeof message.data?.version === 'string' && message.data.radio === 'unconfigured') {
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
  try {
    const response = await fetch('/session', {method: 'POST', body: input.value}); input.value = '';
    if (!response.ok) throw new Error('Access denied');
    document.querySelector('#login-error').textContent = ''; clearTimeout(timer);
    if (socket && socket.readyState < WebSocket.CLOSING) { socket.onclose = null; socket.close(); }
    retry = 1000; connect();
  } catch { document.querySelector('#login-error').textContent = 'Could not authenticate. Check your token and connection.'; }
});
connect();
