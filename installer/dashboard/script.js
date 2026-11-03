/* JARVIS dashboard client: one conversation owner, no stale callbacks. */
const conversation = typeof ConversationState === 'function' ? new ConversationState() : null;
const selected = { key: 'default' };

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}

function render(state) {
  document.querySelector('[data-version]').textContent = state.version || '—';
  document.getElementById('gateway').textContent = state.gateway?.state || 'UNKNOWN';
  document.getElementById('tasks').textContent = state.crew.reduce((n, agent) => n + (agent.tasks || 0), 0);
  document.getElementById('crew').innerHTML = state.crew.map(agent => `<button class="face" data-agent="${escapeHtml(agent.key)}" title="${escapeHtml(agent.role)}">${escapeHtml(AV(agent.key))} ${escapeHtml(agent.name)}</button>`).join('');
  document.getElementById('agent-list').innerHTML = state.crew.map(agent => `<p><b>${escapeHtml(agent.name)}</b> · ${escapeHtml(agent.role)} · ${agent.tasks || 0} logged tasks</p>`).join('');
  document.getElementById('feed').innerHTML = (state.ops || []).slice(0, 6).map(op => `<div>${escapeHtml(op.agent)}: ${escapeHtml(op.op)}</div>`).join('') || '<div>No activity yet.</div>';
  document.querySelectorAll('[data-agent]').forEach(button => { button.onclick = () => selectAgent(button.dataset.agent); });
}

function selectAgent(agent) {
  selected.key = agent;
  if (conversation) conversation.selectedAgent = agent;
  document.querySelectorAll('[data-agent]').forEach(button => button.classList.toggle('selected', button.dataset.agent === agent));
}

function setPhase(label) {
  let status = document.getElementById('conversation-status');
  if (!status) {
    status = document.createElement('div');
    status.id = 'conversation-status';
    status.className = 'conversation-status';
    document.getElementById('orb').after(status);
  }
  status.textContent = label;
}

async function sendMessage(text, agent = selected.key) {
  const response = await fetch('/api/chat/send', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agent, text }) });
  const reply = await response.text();
  if (!response.ok) throw new Error(reply || 'chat request failed');
  return reply;
}

function beginSpeechTurn() {
  if (!conversation) return;
  const generation = conversation.startPushToTalk(selected.key);
  if (generation === null) return;
  setPhase('LISTENING');
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Recognition) { setPhase('TYPE A MESSAGE'); return; }
  const recognition = new Recognition();
  recognition.continuous = true;
  recognition.interimResults = true;
  recognition.onresult = event => {
    for (let index = event.resultIndex; index < event.results.length; index += 1) {
       if (event.results[index].isFinal) conversation.acceptDictation(generation, event.results[index][0].transcript);
    }
  };
   recognition.onerror = () => { if (generation === conversation.dictationGeneration) setPhase('MIC ERROR'); };
   recognition.onend = () => { if (generation === conversation.dictationGeneration && conversation.phase === 'listening') setPhase('READY'); };
  window.__jarvisRecognition = recognition;
   recognition.start();
   window.__jarvisPushTimer = setTimeout(() => stopSpeechTurn(generation), PUSH_TO_TALK_MS);
}

function stopSpeechTurn(generation = conversation?.dictationGeneration) {
  if (window.__jarvisPushTimer) { clearTimeout(window.__jarvisPushTimer); window.__jarvisPushTimer = null; }
  if (window.__jarvisRecognition) { window.__jarvisRecognition.stop(); window.__jarvisRecognition = null; }
  if (conversation && conversation.finishPushToTalk(generation)) {
    setPhase('WAITING FOR REPLY');
    const text = conversation.transcript;
     sendMessage(text).then(reply => { document.getElementById('reply').textContent = reply; conversation.beginSpeaking(); setPhase('REPLY'); setTimeout(() => conversation.interrupt(), REST_MS); }).catch(error => { document.getElementById('reply').textContent = error.message; conversation.interrupt(); setPhase('ERROR'); });
  }
}

function installConversationControls() {
  const orb = document.getElementById('orb');
  if (!orb) return;
  orb.setAttribute('role', 'button');
  orb.tabIndex = 0;
  orb.onclick = () => conversation?.phase === 'listening' ? stopSpeechTurn() : beginSpeechTurn();
  document.addEventListener('keydown', event => {
     if (event.key === 'Escape') { if (window.__jarvisPushTimer) clearTimeout(window.__jarvisPushTimer); if (window.__jarvisRecognition) window.__jarvisRecognition.stop(); conversation?.interrupt(); setPhase('READY'); return; }
    if (event.code === 'Space' && !ConversationState.isTextControl(event.target)) { event.preventDefault(); if (event.type === 'keydown') beginSpeechTurn(); }
    if (/^[1-4]$/.test(event.key) && !event.ctrlKey && !event.metaKey && !ConversationState.isTextControl(event.target)) selectAgent(['default', 'dev', 'research', 'assistant'][Number(event.key) - 1]);
  });
  document.addEventListener('keyup', event => { if (event.code === 'Space') stopSpeechTurn(); });
}

async function load() {
  const state = await fetch('/api/state').then(response => response.json());
  render(state); installConversationControls();
  const events = typeof EventSource === 'function' ? new EventSource('/events') : null;
  if (events) events.addEventListener('state', event => render(JSON.parse(event.data)));
  fetch('/api/content').then(response => response.json()).then(value => { document.getElementById('library-list').textContent = `${value.total} documents across four shelves.`; });
  fetch('/docs.md').then(response => response.ok ? response.text() : Promise.reject()).then(value => { document.getElementById('docs-body').textContent = value; }).catch(() => { const seed = document.getElementById('docs-seed'); if (seed) document.getElementById('docs-body').textContent = seed.textContent; });
}

document.querySelectorAll('[data-view]').forEach(button => button.onclick = () => { document.querySelectorAll('.view').forEach(view => view.classList.remove('active')); document.getElementById(button.dataset.view).classList.add('active'); document.querySelectorAll('.tabs button').forEach(item => item.classList.remove('active')); button.classList.add('active'); });
document.getElementById('send').onclick = async () => { const input = document.getElementById('message'); const text = input.value.trim(); if (!text) return; input.value = ''; try { document.getElementById('reply').textContent = await sendMessage(text); } catch (error) { document.getElementById('reply').textContent = error.message; } };
load();
