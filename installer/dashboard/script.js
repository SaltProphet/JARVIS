/* JARVIS dashboard client: one conversation owner, no stale callbacks. */
const conversation = typeof ConversationState === 'function' ? new ConversationState() : null;
const selected = { key: 'default' };
const talk = { mode: 'ptt', captureActive: false, stopRequested: false };

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}

function render(state) {
  document.querySelector('[data-version]').textContent = state.version || '—';
  document.getElementById('gateway').textContent = state.gateway?.state || 'UNKNOWN';
  document.getElementById('tasks').textContent = state.crew.reduce((n, agent) => n + (agent.tasks || 0), 0);
   document.getElementById('crew').innerHTML = state.crew.map((agent, index) => `<button class="face" data-agent="${escapeHtml(agent.key)}" title="${escapeHtml(agent.role)}"><kbd>${index + 1}</kbd> ${escapeHtml(AV(agent.key))} ${escapeHtml(agent.name)}</button>`).join('');
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
   const orb = document.getElementById('orb');
   if (orb) {
     orb.dataset.phase = label;
     orb.classList.toggle('is-listening', talk.captureActive);
   }
   status.textContent = label;
   const overlayStatus = document.querySelector('#conversation-overlay .eyebrow');
   if (overlayStatus) overlayStatus.textContent = `Live transcript · ${label}`;
   const cancel = document.getElementById('cancel-reply');
   if (cancel) cancel.hidden = label !== 'WAITING FOR REPLY';
}

function setActivity(label) {
  const status = document.getElementById('conversation-status');
  const overlayStatus = document.querySelector('#conversation-overlay .eyebrow');
  const value = `${talk.mode.toUpperCase()} · ${label}`;
  if (status) status.textContent = value;
  if (overlayStatus) overlayStatus.textContent = `Live transcript · ${value}`;
  const orb = document.getElementById('orb');
  if (orb) {
    orb.dataset.activity = label;
    orb.classList.toggle('is-listening', talk.captureActive);
  }
}

function renderTranscript(interimTranscript = '') {
  const target = document.getElementById('conversation-transcript');
  if (target && conversation) target.textContent = [conversation.transcript, interimTranscript.trim()].filter(Boolean).join(' ') || 'Waiting for speech.';
}

function stopRecognition() {
  const recognition = window.__jarvisRecognition;
  window.__jarvisRecognition = null;
  if (!recognition) return;
  talk.captureActive = false;
  recognition.onresult = null;
  recognition.onend = null;
  recognition.onerror = null;
  recognition.onstart = null;
  recognition.onaudiostart = null;
  recognition.onspeechstart = null;
  recognition.onspeechend = null;
  recognition.stop();
}

async function sendMessage(text, agent = selected.key, signal) {
  const response = await fetch('/api/chat/send', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agent, text }), signal });
  const reply = await response.text();
  if (!response.ok) throw new Error(reply || 'chat request failed');
  return reply;
}

function beginSpeechTurn() {
  if (!conversation) return;
  if (window.__jarvisRestTimer) { clearTimeout(window.__jarvisRestTimer); window.__jarvisRestTimer = null; }
  const generation = conversation.startPushToTalk(selected.key);
  if (generation === null) return;
  talk.captureActive = true;
  talk.stopRequested = false;
  renderTranscript();
  setPhase('LISTENING');
  const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!Recognition) {
    conversation.interrupt();
    renderTranscript();
    setPhase('TRANSCRIPTION UNAVAILABLE');
    return;
  }
  const recognition = new Recognition();
  recognition.continuous = true;
  recognition.interimResults = true;
  let interimTranscript = '';
  recognition.onstart = () => { if (generation === conversation.dictationGeneration) setActivity('LISTENING'); };
  recognition.onaudiostart = () => { if (generation === conversation.dictationGeneration) setActivity('AUDIO'); };
  recognition.onspeechstart = () => { if (generation === conversation.dictationGeneration) setActivity('VOICE'); };
  recognition.onspeechend = () => { if (generation === conversation.dictationGeneration) setActivity('AUDIO WAITING'); };
  recognition.onresult = event => {
    interimTranscript = '';
    for (let index = event.resultIndex; index < event.results.length; index += 1) {
      const transcript = event.results[index][0].transcript;
      if (event.results[index].isFinal) conversation.acceptDictation(generation, transcript);
      else interimTranscript += transcript;
    }
    renderTranscript(interimTranscript);
  };
   recognition.onerror = event => {
     if (generation !== conversation.dictationGeneration) return;
     if (event.error === 'no-speech') return setActivity('AUDIO WAITING');
     talk.stopRequested = true;
     stopRecognition();
     setPhase(`MIC ERROR: ${event.error || 'unknown'}`);
   };
   recognition.onend = () => {
     if (generation !== conversation.dictationGeneration || talk.stopRequested || conversation.phase !== 'listening') return;
     setActivity('RECONNECTING');
     setTimeout(() => {
       if (generation !== conversation.dictationGeneration || talk.stopRequested || conversation.phase !== 'listening') return;
       try { recognition.start(); } catch (error) { if (error.name !== 'InvalidStateError') setActivity('RECONNECT FAILED'); }
     }, 0);
   };
  window.__jarvisRecognition = recognition;
   try { recognition.start(); } catch (error) { if (generation === conversation.dictationGeneration) { talk.stopRequested = true; conversation.interrupt(); renderTranscript(); setPhase(`MIC ERROR: ${error.name || 'start failed'}`); } return; }
}

function stopSpeechTurn(generation = conversation?.dictationGeneration) {
  if (window.__jarvisPushTimer) { clearTimeout(window.__jarvisPushTimer); window.__jarvisPushTimer = null; }
  talk.stopRequested = true;
  stopRecognition();
  if (conversation && conversation.finishPushToTalk(generation)) {
    setPhase('WAITING FOR REPLY');
    const text = conversation.transcript;
    const controller = new AbortController();
    window.__jarvisReplyController = controller;
    sendMessage(text, selected.key, controller.signal).then(reply => { if (window.__jarvisReplyController !== controller) return; window.__jarvisReplyController = null; document.getElementById('reply').textContent = reply; conversation.beginSpeaking(); setPhase('REPLY'); window.__jarvisRestTimer = setTimeout(() => { conversation.interrupt(); renderTranscript(); }, REST_MS); }).catch(error => { if (error.name === 'AbortError' || window.__jarvisReplyController !== controller) return; window.__jarvisReplyController = null; document.getElementById('reply').textContent = error.message; conversation.interrupt(); renderTranscript(); setPhase('ERROR'); });
  } else if (conversation) { conversation.interrupt(); renderTranscript(); setPhase('READY'); }
}

function cancelReply() {
  if (window.__jarvisReplyController) { window.__jarvisReplyController.abort(); window.__jarvisReplyController = null; }
  if (conversation?.phase === 'waiting-for-reply') conversation.interrupt();
  const reply = document.getElementById('reply');
  if (reply) reply.textContent = 'Reply cancelled.';
  renderTranscript();
  setPhase('READY');
}

function toggleTalkMode() {
  talk.mode = talk.mode === 'ptt' ? 'htt' : 'ptt';
  document.getElementById('talk-mode-toggle')?.setAttribute('aria-pressed', String(talk.mode === 'ptt'));
}

function installConversationControls() {
  const orb = document.getElementById('orb');
  if (!orb) return;
  const pause = document.getElementById('dictation-pause');
  document.getElementById('cancel-reply')?.addEventListener('click', cancelReply);
  document.getElementById('talk-mode-toggle')?.addEventListener('click', toggleTalkMode);
  if (pause) pause.onclick = () => { if (conversation?.dictationPaused) { conversation.resumeDictation(); pause.textContent = 'Pause dictation'; } else if (conversation?.pauseDictation()) pause.textContent = 'Resume dictation'; };
  orb.setAttribute('role', 'button');
  orb.tabIndex = 0;
  orb.onclick = () => {
    if (window.__jarvisSuppressSpaceClick) { window.__jarvisSuppressSpaceClick = false; return; }
    conversation?.phase === 'listening' ? stopSpeechTurn() : beginSpeechTurn();
  };
  document.addEventListener('keydown', event => {
     if (event.key === 'Escape') { if (window.__jarvisPushTimer) clearTimeout(window.__jarvisPushTimer); if (window.__jarvisRestTimer) clearTimeout(window.__jarvisRestTimer); talk.stopRequested = true; stopRecognition(); cancelReply(); return; }
    if (event.code === 'Space' && !ConversationState.isTextControl(event.target)) {
      event.preventDefault();
      if (event.repeat || window.__jarvisSpaceHeld) return;
      window.__jarvisSpaceHeld = true;
      if (conversation?.phase === 'rest') beginSpeechTurn();
    }
    if (/^[1-4]$/.test(event.key) && !event.ctrlKey && !event.metaKey && !ConversationState.isTextControl(event.target)) selectAgent(['default', 'dev', 'research', 'assistant'][Number(event.key) - 1]);
  });
  document.addEventListener('keyup', event => {
    if (event.code !== 'Space') return;
    event.preventDefault();
    if (!window.__jarvisSpaceHeld) return;
    window.__jarvisSpaceHeld = false;
    window.__jarvisSuppressSpaceClick = true;
    if (conversation?.phase === 'listening') stopSpeechTurn();
  });
}

async function load() {
  const state = await fetch('/api/state').then(response => response.json());
   render(state); installConversationControls();
   fetch('/api/owner').then(response => response.json()).then(owner => { const greeting = document.getElementById('owner-greeting'); if (greeting && owner.name) greeting.textContent = ` · HELLO ${owner.name.toUpperCase()}`; });
  const events = typeof EventSource === 'function' ? new EventSource('/events') : null;
  if (events) events.addEventListener('state', event => render(JSON.parse(event.data)));
  fetch('/api/content').then(response => response.json()).then(value => { document.getElementById('library-list').textContent = `${value.total} documents across four shelves.`; });
  fetch('/docs.md').then(response => response.ok ? response.text() : Promise.reject()).then(value => { document.getElementById('docs-body').textContent = value; }).catch(() => { const seed = document.getElementById('docs-seed'); if (seed) document.getElementById('docs-body').textContent = seed.textContent; });
}

document.querySelectorAll('[data-view]').forEach(button => button.onclick = () => { document.querySelectorAll('.view').forEach(view => view.classList.remove('active')); document.getElementById(button.dataset.view).classList.add('active'); document.querySelectorAll('.tabs button').forEach(item => item.classList.remove('active')); button.classList.add('active'); });
document.getElementById('send').onclick = async () => { const input = document.getElementById('message'); const text = input.value.trim(); if (!text) return; input.value = ''; try { document.getElementById('reply').textContent = await sendMessage(text); } catch (error) { document.getElementById('reply').textContent = error.message; } };
load();
