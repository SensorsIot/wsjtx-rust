'use strict';
const connection = document.querySelector('#connection');
const version = document.querySelector('#version');
const radio = document.querySelector('#radio');
const login = document.querySelector('#login');
let socket, timer, pendingId;
let retry = 1000, lastMessage = 0, nextId = 1;
function stale() { connection.textContent = 'Disconnected · stale'; connection.dataset.state = 'stale'; }
function connect() {
  clearTimeout(timer);
  socket = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws`, 'wstx.v1');
  const current = socket;
  current.onopen = () => {
    lastMessage = Date.now(); pendingId = nextId++;
    current.send(JSON.stringify({v: 1, type: 'station.get', id: pendingId}));
  };
  current.onmessage = event => {
    try {
      const message = JSON.parse(event.data);
      if (message.v !== 1) throw new Error('Unsupported version');
      lastMessage = Date.now();
      if (message.type === 'station.status' && message.id === pendingId && typeof message.data?.version === 'string' && message.data.radio === 'unconfigured') {
        version.textContent = message.data.version; radio.textContent = 'Radio not configured';
        connection.textContent = 'Connected'; connection.dataset.state = 'connected';
        retry = 1000; login.hidden = true;
      }
    } catch { current.close(); }
  };
  current.onclose = () => {
    stale(); login.hidden = location.protocol !== 'https:';
    timer = setTimeout(connect, retry); retry = Math.min(retry * 2, 4000);
  };
}
setInterval(() => { if (socket?.readyState === WebSocket.OPEN && Date.now() - lastMessage > 12000) { stale(); socket.close(); } }, 1000);
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
