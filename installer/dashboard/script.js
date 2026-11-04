const conversation = new ConversationState();
const selected = { key: 'default' };
const talk = { mode: 'ptt', captureActive: false, stopRequested: false, startedAt: 0, spokenReplies: true };
let serviceCache = [];
let meterContext = null, meterFrame = null, meterAnalyser = null;
let audioUrl = null, modeMenuTrigger = null;
const audioPrefs = (() => { try { return JSON.parse(localStorage.getItem('mission-audio') || '{}'); } catch (_) { return {}; } })();
function saveAudioPrefs() { try { localStorage.setItem('mission-audio', JSON.stringify(audioPrefs)); } catch (_) {} }
function closeModeMenu() { $('mode-menu').hidden = true; $('mode-toggle').setAttribute('aria-expanded', 'false'); }
function stopMeter() { if (meterFrame) cancelAnimationFrame(meterFrame); meterFrame = null; meterAnalyser = null; meterContext?.close().catch(() => {}); meterContext = null; $('meter').classList.remove('active'); $('meter').querySelectorAll('i').forEach(bar => bar.style.setProperty('height', '2px', 'important')); }
function startMeter(stream) { stopMeter(); try { meterContext = new (window.AudioContext || window.webkitAudioContext)(); meterAnalyser = meterContext.createAnalyser(); meterAnalyser.fftSize = 256; meterContext.createMediaStreamSource(stream).connect(meterAnalyser); const data = new Uint8Array(meterAnalyser.frequencyBinCount); const draw = () => { if (!talk.captureActive || !meterAnalyser) return; meterAnalyser.getByteFrequencyData(data); $('meter').classList.add('active'); $('meter').querySelectorAll('i').forEach((bar, index) => bar.style.setProperty('height', `${2 + data[index * 4] / 255 * 16}px`, 'important')); meterFrame = requestAnimationFrame(draw); }; draw(); } catch (error) { $('settings-error').textContent = `Audio meter unavailable: ${error.message}`; } }
function stopPlayback() { if (window.__missionAudio) { window.__missionAudio.pause(); window.__missionAudio.onended = null; window.__missionAudio = null; } if (audioUrl) URL.revokeObjectURL(audioUrl); audioUrl = null; }
function cancelTurn() { window.__missionReply?.abort(); window.__missionReply = null; window.__missionTranscribe?.abort(); window.__missionTranscribe = null; window.__missionVoice?.abort(); window.__missionVoice = null; stopPlayback(); stopCapture(); }


function escapeHtml(value) { return String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch])); }
function $ (id) { return document.getElementById(id); }
function setPhase(label) { const status = $('conversation-status'); status.textContent = label === 'READY' ? '' : label; status.title = status.textContent; status.hidden = !status.textContent; $('orb').classList.toggle('is-listening', talk.captureActive); $('orb').setAttribute('aria-pressed', String(talk.captureActive)); $('orb').setAttribute('aria-label', talk.captureActive ? 'Stop recording' : 'Start listening'); const busy = label !== 'READY'; $('stop-capture').hidden = !talk.captureActive; $('cancel-reply').hidden = !busy; $('mode-toggle').disabled = busy; $('home-send').disabled = busy; $('send').disabled = busy; }
function setTranscript(text) { const value = text && text !== 'Waiting for speech.' && text !== 'Listening...' ? text : ''; $('transcript').textContent = value; $('transcript-line').hidden = !value; }
function addMessage(kind, text) { if (!text) return; $('empty-thread')?.remove(); const item = document.createElement('div'); item.className = `message ${kind}`; item.innerHTML = `${escapeHtml(text)}`; $('conversation-thread').appendChild(item); $('conversation-thread').scrollTop = $('conversation-thread').scrollHeight; }
function updateTimer() { if (!talk.captureActive) return; const seconds = Math.floor((Date.now() - talk.startedAt) / 1000); $('timer').textContent = `${String(Math.floor(seconds / 60)).padStart(2, '0')}:${String(seconds % 60).padStart(2, '0')}`; window.setTimeout(updateTimer, 250); }
function render(state) {
  $('gateway').textContent = state.gateway?.state?.toUpperCase() || 'UNKNOWN';
  document.querySelector('[data-version]').textContent = state.version || '—';
  $('tasks').textContent = state.crew.reduce((total, agent) => total + (agent.tasks || 0), 0);
  $('feed').innerHTML = (state.ops || []).slice(0, 6).map(op => `<div class="activity-item"><span><b>${escapeHtml(op.agent || 'system')}</b> ${escapeHtml(op.op)}</span><span>${escapeHtml(op.t || '')}</span></div>`).join('') || '<span class="muted">No activity yet.</span>';
  $('agent-list').innerHTML = state.crew.map(agent => `<button class="agent-card card ${agent.key === selected.key ? 'selected' : ''}" data-agent="${escapeHtml(agent.key)}"><span><b>${escapeHtml(agent.key === 'default' ? 'Default' : agent.name)}</b><small class="service-detail">${escapeHtml(agent.role)}</small></span><span>${agent.tasks || 0} tasks</span></button>`).join('');
  document.querySelectorAll('[data-agent]').forEach(button => button.addEventListener('click', () => selectAgent(button.dataset.agent)));
}
function selectAgent(agent) { selected.key = agent; const label = document.querySelector(`[data-agent="${CSS.escape(agent)}"] b`); $('active-agent').textContent = agent === 'default' ? 'Default' : label?.textContent || agent; document.querySelectorAll('[data-agent]').forEach(button => button.classList.toggle('selected', button.dataset.agent === agent)); }

function renderServices(services) {
  serviceCache = services;
  const details = services.map(service => `<div class="service"><span class="service-dot ${escapeHtml(service.state)}"></span><span class="service-name">${escapeHtml(service.label)}<small class="service-detail">${escapeHtml(service.detail || service.state)}</small></span><span>${(service.actions || []).map(action => `<button class="service-action" data-service="${escapeHtml(service.id)}" data-action="${escapeHtml(action)}">${escapeHtml(action)}</button>`).join(' ')}</span></div>`).join('');
  $('services').innerHTML = services.map(service => `<button class="service-indicator" data-drawer="settings" aria-label="${escapeHtml(service.label + ': ' + service.state)}" title="${escapeHtml(service.label + ': ' + service.state)}"><span class="service-dot ${escapeHtml(service.state)}"></span></button>`).join('');
  $('drawer-services').innerHTML = details || '<p class="muted">No service data.</p>';
  $('services').querySelectorAll('button').forEach(button => button.addEventListener('click', openDrawer));
  document.querySelectorAll('[data-service]').forEach(button => button.addEventListener('click', () => serviceAction(button.dataset.service, button.dataset.action)));
}
async function refreshServices() { try { const response = await fetch('/api/services'); const payload = await response.json(); if (!response.ok) throw new Error(payload.error || 'Service status unavailable'); renderServices(payload.services || []); } catch (error) { $('services').innerHTML = '<button class="service-indicator" data-drawer="settings" aria-label="Service status unavailable" title="Service status unavailable"><span class="service-dot error"></span></button>'; $('services').querySelector('button').addEventListener('click', openDrawer); $('drawer-services').textContent = error.message; $('settings-error').textContent = error.message; } }
async function serviceAction(service, action) { $('settings-error').textContent = `Requesting ${action} for ${service}...`; try { const response = await fetch(`/api/services/${encodeURIComponent(service)}/action`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action }) }); const payload = await response.json(); if (!response.ok || !payload.ok) throw new Error(payload.error || 'service action failed'); renderServices(Object.values(payload.services)); $('settings-error').textContent = ''; } catch (error) { $('settings-error').textContent = error.message; } }
async function loadAudioDevices() { try { const response = await fetch('/api/audio/devices'); const payload = await response.json(); if (!response.ok || payload.error) $('settings-error').textContent = payload.error || 'Host audio inventory unavailable'; const devices = navigator.mediaDevices?.enumerateDevices ? await navigator.mediaDevices.enumerateDevices() : []; for (const [id, kind, pref] of [['input-device', 'audioinput', 'input'], ['output-device', 'audiooutput', 'output']]) { const select = $(id); select.innerHTML = '<option value="">System default</option>' + devices.filter(device => device.kind === kind && device.deviceId).map((device, i) => `<option value="${escapeHtml(device.deviceId)}">${escapeHtml(device.label || 'Device ' + (i + 1))}</option>`).join(''); select.value = audioPrefs[pref] || ''; select.disabled = id === 'output-device' && !HTMLMediaElement.prototype.setSinkId; } $('input-name').textContent = $('input-device').selectedOptions[0]?.textContent || 'System default'; } catch (error) { $('settings-error').textContent = error.message; } }

function stopRecognition() { const recognition = window.__missionRecognition; window.__missionRecognition = null; if (!recognition) return; talk.captureActive = false; recognition.onresult = recognition.onend = recognition.onerror = null; recognition.stop(); }
function stopMediaCapture() { talk.captureActive = false; stopMeter(); const recorder = window.__missionRecorder; window.__missionRecorder = null; if (recorder && recorder.state !== 'inactive') recorder.stop(); if (window.__missionStream) { window.__missionStream.getTracks().forEach(track => track.stop()); window.__missionStream = null; } }
function finishSpeechTurn(generation) { if (generation !== conversation.dictationGeneration) return; if (talk.mode === 'always') { addMessage('user', conversation.transcript); conversation.interrupt(); setTranscript(''); setPhase('READY'); return; } if (!conversation.finishPushToTalk(generation)) { conversation.interrupt(); setTranscript(''); setPhase('READY'); return; } const text = conversation.transcript; addMessage('user', text); setTranscript(''); setPhase('WAITING FOR REPLY'); const controller = new AbortController(); window.__missionReply = controller; sendMessage(text, selected.key, controller.signal).then(async reply => { if (window.__missionReply !== controller || generation !== conversation.dictationGeneration) return; window.__missionReply = null; addMessage('assistant', reply); $('reply').textContent = reply; conversation.beginSpeaking(); if (talk.spokenReplies) { setPhase('SPEAKING'); await speakReply(reply, generation); } else { conversation.interrupt(); setPhase('READY'); } }).catch(error => { if (error.name === 'AbortError' || generation !== conversation.dictationGeneration) return; addMessage('system', error.message); $('settings-error').textContent = error.message; conversation.interrupt(); setPhase('READY'); }); }
async function startMediaCapture(generation) {
 try {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: audioPrefs.input ? { deviceId: { exact: audioPrefs.input } } : true });
  if (generation !== conversation.dictationGeneration || talk.stopRequested) return stream.getTracks().forEach(track => track.stop());
  const mimeType = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4'].find(type => MediaRecorder.isTypeSupported(type));
  const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined); const chunks = [];
  window.__missionStream = stream; window.__missionRecorder = recorder; startMeter(stream); loadAudioDevices();
  recorder.ondataavailable = event => { if (event.data.size) chunks.push(event.data); };
  recorder.onerror = () => { cancelTurn(); addMessage('system', 'Microphone capture failed.'); };
  recorder.onstop = async () => {
   stream.getTracks().forEach(track => track.stop()); if (window.__missionStream === stream) window.__missionStream = null;
   if (!chunks.length || generation !== conversation.dictationGeneration) return;
   const controller = new AbortController(); window.__missionTranscribe = controller;
   try { setPhase('TRANSCRIBING'); const clip = new Blob(chunks, { type: recorder.mimeType || mimeType || 'audio/webm' }); const response = await fetch('/api/transcribe', { method: 'POST', headers: { 'Content-Type': clip.type }, body: clip, signal: controller.signal }); const payload = await response.json(); if (generation !== conversation.dictationGeneration) return; if (!response.ok) throw new Error(payload.error || 'Transcription failed'); conversation.acceptDictation(generation, payload.text); finishSpeechTurn(generation); }
   catch (error) { if (error.name === 'AbortError' || generation !== conversation.dictationGeneration) return; conversation.interrupt(); addMessage('system', error.message); setPhase('READY'); }
   finally { if (window.__missionTranscribe === controller) window.__missionTranscribe = null; }
  }; recorder.start();
 } catch (error) { if (generation !== conversation.dictationGeneration) return; cancelTurn(); addMessage('system', `Microphone: ${error.message}`); }
}

function beginSpeechTurn() { if (conversation.phase !== 'rest' || talk.captureActive) return; if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) { addMessage('system', 'Microphone recording needs a supported browser on localhost or HTTPS.'); return; } const generation = conversation.startPushToTalk(selected.key); if (generation === null) return; talk.captureActive = true; talk.stopRequested = false; talk.startedAt = Date.now(); setTranscript(''); setPhase(talk.mode === 'always' ? 'TRANSCRIPT ONLY' : 'RECORDING'); updateTimer(); startMediaCapture(generation); }
function stopSpeechTurn() { talk.stopRequested = true; if (window.__missionRecorder) { setPhase('TRANSCRIBING'); stopMediaCapture(); $('stop-capture').hidden = true; return; } cancelTurn(); }
function startAlwaysOn() { beginSpeechTurn(); }
function stopCapture() { talk.stopRequested = true; conversation.interrupt(); stopMediaCapture(); stopRecognition(); talk.captureActive = false; setTranscript(''); setPhase('READY'); }
function setMode(mode) { if (conversation.phase !== 'rest' || talk.captureActive) return; talk.mode = mode; document.querySelectorAll('[data-mode]').forEach(button => { button.classList.toggle('active', button.dataset.mode === mode); button.setAttribute('aria-pressed', String(button.dataset.mode === mode)); }); $('mode-label').textContent = { ptt: 'Push to Talk', tap: 'Tap to Talk', always: 'Always On' }[mode]; closeModeMenu(); $('mode-toggle').focus(); }
async function sendMessage(text, agent = selected.key, signal) { const response = await fetch('/api/chat/send', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ agent, text }), signal }); const reply = await response.text(); if (!response.ok) throw new Error(reply || 'chat request failed'); return reply; }
async function speakReply(text, generation = conversation.dictationGeneration) { stopPlayback(); const controller = new AbortController(); window.__missionVoice = controller; try { const response = await fetch('/api/voice', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text }), signal: controller.signal }); if (!response.ok) throw new Error('Voice service unavailable; text reply preserved.'); const blob = await response.blob(); if (generation !== conversation.dictationGeneration) return; audioUrl = URL.createObjectURL(blob); const audio = new Audio(audioUrl); window.__missionAudio = audio; audio.volume = Number($('volume').value) / 100; if (audioPrefs.output && audio.setSinkId) await audio.setSinkId(audioPrefs.output); if (generation !== conversation.dictationGeneration) { stopPlayback(); return; } audio.onended = () => { if (generation !== conversation.dictationGeneration) return; stopPlayback(); conversation.interrupt(); setPhase('READY'); }; await audio.play(); } finally { if (window.__missionVoice === controller) window.__missionVoice = null; } }

function openDrawer() { closeModeMenu(); modeMenuTrigger = document.activeElement; $('drawer-backdrop').hidden = false; $('settings-drawer').inert = false; $('settings-drawer').classList.add('open'); $('settings-drawer').setAttribute('aria-hidden', 'false'); document.querySelector('[data-close-drawer]').focus(); loadAudioDevices(); refreshServices(); }
function closeDrawer() { $('settings-drawer').classList.remove('open'); $('settings-drawer').setAttribute('aria-hidden', 'true'); $('settings-drawer').inert = true; $('drawer-backdrop').hidden = true; modeMenuTrigger?.focus(); }
async function sendTyped(input) {
 const text = input.value.trim(); if (!text || conversation.phase !== 'rest' || talk.captureActive) return; input.value = ''; conversation.beginListening(selected.key); conversation.transcript = text; finishSpeechTurn(conversation.dictationGeneration);
}
function installControls() {
 document.querySelectorAll('[data-view]').forEach(button => button.addEventListener('click', () => { const view = button.dataset.view; document.querySelectorAll('.view').forEach(item => item.classList.toggle('active', item.id === view)); document.querySelectorAll('.rail-link').forEach(item => item.classList.toggle('active', item.dataset.view === view)); if (view !== 'home' && talk.captureActive) cancelTurn(); closeModeMenu(); }));
 document.querySelectorAll('[data-drawer]').forEach(button => button.addEventListener('click', openDrawer)); document.querySelector('[data-close-drawer]').addEventListener('click', closeDrawer); $('drawer-backdrop').addEventListener('click', closeDrawer);
 $('mode-toggle').addEventListener('click', () => { const open = $('mode-menu').hidden; $('mode-menu').hidden = !open; $('mode-toggle').setAttribute('aria-expanded', String(open)); if (open) $('mode-menu').querySelector('.active').focus(); });
 document.querySelectorAll('[data-mode]').forEach(button => button.addEventListener('click', () => setMode(button.dataset.mode)));
 document.addEventListener('click', event => { if (!event.target.closest('.mode-control')) closeModeMenu(); });
 let pointerHeld = false, spaceHeld = false;
 $('orb').addEventListener('pointerdown', event => { if (talk.mode !== 'ptt') return; event.preventDefault(); pointerHeld = true; $('orb').setPointerCapture(event.pointerId); beginSpeechTurn(); });
 $('orb').addEventListener('pointerup', () => { if (pointerHeld) { pointerHeld = false; if (talk.captureActive) stopSpeechTurn(); } });
 $('orb').addEventListener('pointercancel', () => { pointerHeld = false; cancelTurn(); });
 $('orb').addEventListener('click', () => { if (talk.mode === 'ptt') return; talk.captureActive ? stopSpeechTurn() : beginSpeechTurn(); });
 $('stop-capture').addEventListener('click', stopSpeechTurn); $('cancel-reply').addEventListener('click', cancelTurn);
 $('new-thread').addEventListener('click', () => { cancelTurn(); $('conversation-thread').replaceChildren(); $('reply').textContent = ''; });
 $('home-compose').addEventListener('submit', event => { event.preventDefault(); sendTyped($('home-message')); }); $('send').addEventListener('click', () => sendTyped($('message')));
 $('spoken-replies').addEventListener('change', event => { talk.spokenReplies = event.target.checked; $('output-state').textContent = talk.spokenReplies ? 'Spoken + text' : 'Text only'; });
 $('volume').addEventListener('input', event => { $('volume-value').textContent = `${event.target.value}%`; if (window.__missionAudio) window.__missionAudio.volume = Number(event.target.value) / 100; });
 $('input-device').addEventListener('change', event => { audioPrefs.input = event.target.value; saveAudioPrefs(); $('input-name').textContent = event.target.selectedOptions[0]?.textContent || 'System default'; });
 $('output-device').addEventListener('change', event => { audioPrefs.output = event.target.value; saveAudioPrefs(); });
 $('dictation-pause').addEventListener('click', () => { if (conversation.dictationPaused) { conversation.resumeDictation(); $('dictation-pause').textContent = 'Pause dictation'; } else if (conversation.pauseDictation()) $('dictation-pause').textContent = 'Resume dictation'; });
 document.addEventListener('keydown', event => {
  if (event.key === 'Escape') { if (!$('mode-menu').hidden) { closeModeMenu(); $('mode-toggle').focus(); } else if ($('settings-drawer').classList.contains('open')) closeDrawer(); else cancelTurn(); return; }
  if ($('settings-drawer').classList.contains('open')) return;
  if (event.code === 'Space' && !event.repeat && !ConversationState.isTextControl(event.target) && !event.target.closest('button:not(#orb)') && talk.mode === 'ptt') { event.preventDefault(); spaceHeld = true; beginSpeechTurn(); }
 });
 document.addEventListener('keyup', event => { if (event.code === 'Space' && spaceHeld && talk.mode === 'ptt') { event.preventDefault(); spaceHeld = false; if (talk.captureActive) stopSpeechTurn(); } });
 window.addEventListener('blur', () => { if (pointerHeld || spaceHeld) { pointerHeld = spaceHeld = false; cancelTurn(); } });
 document.addEventListener('visibilitychange', () => { if (document.hidden && talk.captureActive) cancelTurn(); });
 $('settings-drawer').addEventListener('keydown', event => { if (event.key !== 'Tab') return; const controls = [...$('settings-drawer').querySelectorAll('button,select,input')].filter(item => !item.disabled); const first = controls[0], last = controls[controls.length - 1]; if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); } else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); } });
 setPhase('READY');
}
function startSystemField() { createLayeredField(); }
async function load() { installControls(); startSystemField(); try { render(await fetch('/api/state').then(response => response.json())); } catch (error) { $('settings-error').textContent = error.message; } refreshServices(); loadAudioDevices(); fetch('/api/content').then(response => response.json()).then(value => $('library-list').textContent = `${value.total} documents across four shelves.`).catch(() => {}); fetch('/api/cron').then(response => response.json()).then(value => $('schedule-list').textContent = value.jobs?.length ? `${value.jobs.length} scheduled jobs.` : 'No scheduled jobs yet.').catch(() => {}); fetch('/docs.md').then(response => response.ok ? response.text() : Promise.reject()).then(value => $('docs-body').textContent = value).catch(() => $('docs-body').textContent = 'Documentation is unavailable.'); }
load();

