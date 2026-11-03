const HOLD_MS = 700;
const REST_MS = 1100;
const IDLE_MS = 30000;
const PUSH_TO_TALK_MS = 5000;

class ConversationState {
  constructor() {
    this.phase = 'rest';
    this.selectedAgent = 'default';
    this.transcript = '';
    this.dictationGeneration = 0;
  }

  beginListening(agent = this.selectedAgent) {
    if (!agent || this.phase === 'speaking') return false;
    this.selectedAgent = agent;
    this.phase = 'listening';
    return true;
  }

  startPushToTalk(agent = this.selectedAgent) {
    if (!this.beginListening(agent)) return null;
    this.dictationGeneration += 1;
    return this.dictationGeneration;
  }

  appendTranscript(text) {
    const value = String(text || '').trim();
    if (!value) return this.transcript;
    this.transcript = this.transcript ? `${this.transcript} ${value}` : value;
    return this.transcript;
  }

  beginReply() {
    if (this.phase !== 'listening' || !this.transcript) return false;
    this.phase = 'waiting-for-reply';
    return true;
  }

  beginSpeaking() {
    if (this.phase !== 'waiting-for-reply') return false;
    this.phase = 'speaking';
    return true;
  }

  interrupt() {
    if (this.phase === 'rest') return false;
    this.phase = 'rest';
    this.transcript = '';
    this.dictationGeneration += 1;
    return true;
  }

  beginDictation() {
    this.dictationGeneration += 1;
    this.phase = 'dictating';
    return this.dictationGeneration;
  }

  acceptDictation(generation, text) {
    if (generation !== this.dictationGeneration || (this.phase !== 'listening' && this.phase !== 'dictating')) return null;
    return this.appendTranscript(text);
  }

  finishPushToTalk(generation) {
    if (generation !== this.dictationGeneration || this.phase !== 'listening') return false;
    return this.beginReply();
  }

  finishDictation() {
    if (this.phase === 'dictating') this.phase = 'rest';
  }

  static isTextControl(element) {
    const tag = String(element?.tagName || '').toUpperCase();
    return ['INPUT', 'TEXTAREA', 'SELECT'].includes(tag) || element?.isContentEditable === true;
  }
}

if (typeof globalThis !== 'undefined') Object.assign(globalThis, { ConversationState, HOLD_MS, REST_MS, IDLE_MS, PUSH_TO_TALK_MS });
if (typeof module !== 'undefined') module.exports = { ConversationState, HOLD_MS, REST_MS, IDLE_MS, PUSH_TO_TALK_MS };
