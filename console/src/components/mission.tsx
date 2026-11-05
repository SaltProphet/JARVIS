import { useEffect, useMemo, useRef, useState, type PointerEvent } from "react";
import {
  AudioLines,
  BookOpen,
  Bot,
  Map as MapIcon,
  Mic,
  Pin,
  Radio,
  Send,
  Settings2,
  Trash2,
} from "lucide-react";
import { AGENTS, agentByKey, type AgentKey } from "@/lib/crew";
import { askCrew, speakReply } from "@/lib/chat.functions";
import { useMission, type ChatMessage } from "@/lib/store";
import { FieldCanvas } from "@/components/field-canvas";
import { GraphCanvas } from "@/components/graph-canvas";

type SpeechResult = ArrayLike<{ transcript: string }> & { isFinal: boolean };

type SpeechCtor = new () => {
  lang: string;
  interimResults: boolean;
  continuous: boolean;
  start: () => void;
  stop: () => void;
  onresult: ((event: { results: ArrayLike<SpeechResult> }) => void) | null;
  onerror: (() => void) | null;
  onend: (() => void) | null;
};

function speechCtor(): SpeechCtor | null {
  if (typeof window === "undefined") return null;
  const host = window as Window & { SpeechRecognition?: SpeechCtor; webkitSpeechRecognition?: SpeechCtor };
  return host.SpeechRecognition ?? host.webkitSpeechRecognition ?? null;
}

const NAV = [
  { id: "home", label: "Home", icon: Radio },
  { id: "agents", label: "Agents", icon: Bot },
  { id: "map", label: "Map", icon: MapIcon },
  { id: "library", label: "Library", icon: BookOpen },
  { id: "control", label: "Control", icon: Settings2 },
] as const;

export function Mission() {
  const agent = useMission((s) => s.agent);
  const view = useMission((s) => s.view);
  const messages = useMission((s) => s.messages);
  const notes = useMission((s) => s.notes);
  const spoken = useMission((s) => s.spoken);
  const volume = useMission((s) => s.volume);
  const hydrated = useMission((s) => s.hydrated);
  const setAgent = useMission((s) => s.setAgent);
  const setView = useMission((s) => s.setView);
  const setSpoken = useMission((s) => s.setSpoken);
  const setVolume = useMission((s) => s.setVolume);
  const push = useMission((s) => s.push);
  const pin = useMission((s) => s.pin);
  const dropNote = useMission((s) => s.dropNote);
  const clearThread = useMission((s) => s.clearThread);
  const markHydrated = useMission((s) => s.markHydrated);

  const [draft, setDraft] = useState("");
  const [phase, setPhase] = useState("Idle");
  const [error, setError] = useState("");
  const [listening, setListening] = useState(false);
  const [busy, setBusy] = useState(false);
  const scroller = useRef<HTMLDivElement>(null);
  const recognition = useRef<InstanceType<SpeechCtor> | null>(null);
  const audio = useRef<HTMLAudioElement | null>(null);
  const holding = useRef(false);
  const heard = useRef("");
  const sentUtterance = useRef(false);

  useEffect(() => {
    void Promise.resolve(useMission.persist.rehydrate()).finally(() => markHydrated());
  }, [markHydrated]);

  useEffect(() => {
    const node = scroller.current;
    if (node) node.scrollTop = node.scrollHeight;
  }, [messages, view]);

  const topics = useMemo(
    () =>
      messages
        .filter((message) => message.role === "assistant" && message.topic)
        .map((message) => ({ label: message.topic as string, agent: message.agent })),
    [messages],
  );
  const topicLabels = useMemo(() => topics.map((topic) => topic.label), [topics]);

  async function play(text: string, who: AgentKey) {
    if (!spoken) return;
    const result = await speakReply({ data: { text, agent: who } });
    if (!result.ok) return;
    const url = `data:${result.mime};base64,${result.audio}`;
    audio.current?.pause();
    const next = new Audio(url);
    next.volume = volume / 100;
    audio.current = next;
    await next.play().catch(() => undefined);
  }

  async function send(text: string) {
    const clean = text.trim();
    if (!clean || busy) return;
    setError("");
    setBusy(true);
    setPhase("Thinking");
    const history = useMission
      .getState()
      .messages.slice(-6)
      .map((message) => ({ role: message.role, text: message.text }));
    push({
      id: crypto.randomUUID(),
      role: "user",
      agent,
      text: clean,
      at: Date.now(),
    });
    setDraft("");
    try {
      const result = await askCrew({ data: { agent, text: clean, history } });
      if (!result.ok) {
        setError(result.error);
        setPhase("Idle");
        return;
      }
      const reply: ChatMessage = {
        id: crypto.randomUUID(),
        role: "assistant",
        agent: result.agent,
        text: result.text,
        topic: result.topic,
        at: Date.now(),
      };
      push(reply);
      setPhase("Speaking");
      await play(result.text, result.agent);
      setPhase("Idle");
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Request failed.");
      setPhase("Idle");
    } finally {
      setBusy(false);
    }
  }

  function holdStart(event: PointerEvent<HTMLButtonElement>) {
    event.preventDefault();
    const Ctor = speechCtor();
    if (!Ctor) {
      setError("This browser has no speech recognition. Type instead.");
      return;
    }
    event.currentTarget.setPointerCapture(event.pointerId);
    holding.current = true;
    heard.current = "";
    sentUtterance.current = false;
    const rec = new Ctor();
    rec.lang = "en-US";
    rec.interimResults = true;
    rec.continuous = true;
    rec.onresult = (resultEvent) => {
      let text = "";
      for (let index = 0; index < resultEvent.results.length; index += 1) {
        text += resultEvent.results[index]?.[0]?.transcript ?? "";
      }
      const shown = text.trim();
      if (!shown) return;
      heard.current = shown;
      setDraft(shown);
    };
    rec.onerror = () => {
      if (holding.current) return;
      setListening(false);
      setPhase("Idle");
    };
    rec.onend = () => {
      if (holding.current) {
        try {
          rec.start();
        } catch {
          setListening(false);
        }
        return;
      }
      setListening(false);
      setPhase((currentPhase) => (currentPhase === "Listening" ? "Idle" : currentPhase));
      const said = heard.current.trim();
      heard.current = "";
      if (!said || sentUtterance.current) return;
      sentUtterance.current = true;
      void send(said);
    };
    recognition.current = rec;
    setListening(true);
    setPhase("Listening");
    setError("");
    try {
      rec.start();
    } catch {
      holding.current = false;
      setListening(false);
      setError("Microphone did not start.");
    }
  }

  function holdStop() {
    holding.current = false;
    recognition.current?.stop();
    setListening(false);
  }

  const current = agentByKey(agent);

  return (
    <div className="flex h-dvh flex-col overflow-hidden bg-ink text-bone md:flex-row">
      <aside className="glass hidden w-52 shrink-0 flex-col border-y-0 border-l-0 px-3 py-4 md:flex">
        <p className="px-2 font-mono text-xs tracking-widest text-muted">MISSION CONTROL</p>
        <p className="mt-1 px-2 text-lg font-semibold">JARVIS</p>
        <nav className="mt-6 flex flex-col gap-1">
          {NAV.map((item) => {
            const Icon = item.icon;
            const on = view === item.id;
            return (
              <button
                key={item.id}
                type="button"
                onClick={() => setView(item.id)}
                className={`flex min-h-11 items-center gap-2 rounded-md px-3 text-left ${on ? "text-teal" : "text-muted hover:bg-white/5"}`}
              >
                <Icon className="size-4" aria-hidden="true" />
                {item.label}
              </button>
            );
          })}
        </nav>
        <p className="mt-auto px-2 font-mono text-xs text-muted">
          {current.code} · {current.name}
        </p>
      </aside>

      <main className="flex min-h-0 min-w-0 flex-1 flex-col">
        <header className="flex items-center gap-3 border-b border-line px-4 py-3">
          <div className="min-w-0">
            <p className="font-mono text-xs tracking-widest text-muted">{view.toUpperCase()}</p>
            <h1 className="truncate text-base font-semibold">{current.name}</h1>
          </div>
          <div className="ml-auto flex items-center gap-2">
            <div className="hidden gap-1 lg:flex">
              {AGENTS.map((member) => (
                <button
                  key={member.key}
                  type="button"
                  onClick={() => setAgent(member.key)}
                  className={`min-h-11 rounded-md px-2 font-mono text-xs ${member.key === agent ? "text-teal" : "text-muted"}`}
                >
                  {member.name}
                </button>
              ))}
            </div>
            <span className="font-mono text-xs text-teal">{phase}</span>
          </div>
        </header>

        {view === "home" && (
          <div className="flex min-h-0 flex-1 flex-col lg:flex-row">
            <section className="orb-wash relative h-80 shrink-0 border-b border-line lg:h-auto lg:min-h-0 lg:flex-1 lg:border-r lg:border-b-0">
              <FieldCanvas listening={listening} phase={phase} topics={topicLabels} />
              <p className="pointer-events-none absolute bottom-3 left-4 font-mono text-xs text-muted">
                {topicLabels.at(-1) ?? "Waiting for a subject"}
              </p>
            </section>
            <section className="flex min-h-0 min-w-0 flex-1 flex-col lg:w-96 lg:flex-none">
            <div ref={scroller} className="flex min-h-0 flex-1 flex-col gap-3 overflow-auto px-4 py-4">
              {!hydrated && <p className="text-sm text-muted">Loading the thread…</p>}
              {hydrated && messages.length === 0 && (
                <div className="glass rounded-md p-4">
                  <p className="font-medium">No thread yet.</p>
                  <p className="mt-1 text-sm text-muted">
                    Hold the mic or type. {current.name} answers, and the map grows from the subject of each reply.
                  </p>
                </div>
              )}
              {messages.map((message) => (
                <article
                  key={message.id}
                  className={`glass max-w-xl rounded-md px-3 py-2 ${message.role === "user" ? "ml-auto" : ""}`}
                >
                  <p className="font-mono text-xs text-muted">
                    {message.role === "user" ? "You" : agentByKey(message.agent).name}
                    {message.topic ? ` · ${message.topic}` : ""}
                  </p>
                  <p className="mt-1 text-sm leading-relaxed">{message.text}</p>
                  {message.role === "assistant" && (
                    <button
                      type="button"
                      className="mt-2 inline-flex min-h-11 items-center gap-1 text-xs text-teal"
                      onClick={() =>
                        pin({
                          id: crypto.randomUUID(),
                          title: message.topic || "Note",
                          body: message.text,
                          agent: message.agent,
                          at: Date.now(),
                        })
                      }
                    >
                      <Pin className="size-3" aria-hidden="true" />
                      Pin to library
                    </button>
                  )}
                </article>
              ))}
            </div>
            <form
              className="flex items-end gap-2 border-t border-line p-3"
              onSubmit={(event) => {
                event.preventDefault();
                void send(draft);
              }}
            >
              <label className="sr-only" htmlFor="draft">
                Message
              </label>
              <input
                id="draft"
                value={draft}
                onChange={(event) => setDraft(event.target.value)}
                placeholder={`Ask ${current.name}…`}
                className="glass min-h-11 flex-1 rounded-md px-3 text-bone outline-none"
              />
              <button
                type="button"
                aria-label={listening ? "Stop listening" : "Hold to talk"}
                onPointerDown={holdStart}
                onPointerUp={holdStop}
                onPointerLeave={() => {
                  if (listening) holdStop();
                }}
                className={`inline-flex min-h-11 min-w-11 items-center justify-center rounded-md px-3 ${listening ? "bg-teal text-ink" : "glass text-bone"}`}
              >
                <Mic className="size-4" aria-hidden="true" />
              </button>
              <button
                type="submit"
                disabled={busy}
                className="inline-flex min-h-11 items-center gap-2 rounded-md bg-teal px-3 font-medium text-ink disabled:opacity-50"
              >
                <Send className="size-4" aria-hidden="true" />
                Send
              </button>
            </form>
            {error && <p className="px-4 pb-3 text-sm text-danger">{error}</p>}
            </section>
          </div>
        )}

        {view === "agents" && (
          <div className="grid gap-3 overflow-auto p-4 sm:grid-cols-2">
            {AGENTS.map((member) => {
              const last = [...messages].reverse().find((message) => message.agent === member.key && message.role === "assistant");
              const on = member.key === agent;
              return (
                <button
                  key={member.key}
                  type="button"
                  onClick={() => {
                    setAgent(member.key);
                    setView("home");
                  }}
                  className={`glass rounded-md p-4 text-left ${on ? "border-teal" : ""}`}
                >
                  <p className="font-mono text-xs text-muted">{member.code}</p>
                  <p className="mt-1 text-lg font-semibold">{member.name}</p>
                  <p className="text-sm text-teal">{member.role}</p>
                  <p className="mt-2 text-sm text-muted">{member.line}</p>
                  <p className="mt-3 text-sm">{last?.text ?? "No reply in this thread yet."}</p>
                </button>
              );
            })}
          </div>
        )}

        {view === "map" && (
          <div className="relative min-h-0 flex-1">
            {topics.length === 0 && (
              <p className="pointer-events-none absolute top-4 left-4 z-10 max-w-xs text-sm text-muted">
                The map is the crew plus subjects from replies. Talk once and nodes appear. Click an agent to switch.
              </p>
            )}
            <GraphCanvas topics={topics} active={agent} onPick={setAgent} />
          </div>
        )}

        {view === "library" && (
          <div className="flex flex-col gap-3 overflow-auto p-4">
            {notes.length === 0 && (
              <p className="glass rounded-md p-4 text-sm text-muted">
                Nothing pinned. Pin a reply from Home and it stays here.
              </p>
            )}
            {notes.map((note) => (
              <article key={note.id} className="glass rounded-md p-4">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-mono text-xs text-muted">{agentByKey(note.agent).name}</p>
                    <h2 className="text-base font-semibold">{note.title}</h2>
                  </div>
                  <button
                    type="button"
                    aria-label="Remove note"
                    className="min-h-11 min-w-11 text-muted"
                    onClick={() => dropNote(note.id)}
                  >
                    <Trash2 className="size-4" />
                  </button>
                </div>
                <p className="mt-2 text-sm leading-relaxed">{note.body}</p>
              </article>
            ))}
          </div>
        )}

        {view === "control" && (
          <div className="flex flex-col gap-4 overflow-auto p-4">
            <section className="glass rounded-md p-4">
              <h2 className="font-semibold">Session</h2>
              <p className="mt-1 text-sm text-muted">
                This console talks to the crew from the browser. Hermes, Kokoro, and Whisper on the Windows machine are not started from here.
              </p>
              <dl className="mt-3 grid grid-cols-2 gap-2 font-mono text-xs">
                <div>
                  <dt className="text-muted">Messages</dt>
                  <dd>{messages.length}</dd>
                </div>
                <div>
                  <dt className="text-muted">Notes</dt>
                  <dd>{notes.length}</dd>
                </div>
                <div>
                  <dt className="text-muted">Active</dt>
                  <dd>{current.name}</dd>
                </div>
                <div>
                  <dt className="text-muted">Topics</dt>
                  <dd>{topics.length}</dd>
                </div>
              </dl>
              <button type="button" className="mt-4 min-h-11 rounded-md border border-line px-3 text-sm" onClick={clearThread}>
                Clear thread
              </button>
            </section>
            <section className="glass rounded-md p-4">
              <h2 className="flex items-center gap-2 font-semibold">
                <AudioLines className="size-4 text-teal" aria-hidden="true" />
                Voice
              </h2>
              <label className="mt-3 flex min-h-11 items-center gap-2 text-sm">
                <input type="checkbox" checked={spoken} onChange={(event) => setSpoken(event.target.checked)} />
                Spoken replies
              </label>
              <label className="mt-2 block text-sm text-muted" htmlFor="volume">
                Volume {volume}%
              </label>
              <input
                id="volume"
                type="range"
                min={0}
                max={100}
                value={volume}
                onChange={(event) => setVolume(Number(event.target.value))}
                className="mt-1 w-full"
              />
            </section>
          </div>
        )}
      </main>

      <nav className="glass grid grid-cols-5 border-x-0 border-b-0 md:hidden">
        {NAV.map((item) => {
          const Icon = item.icon;
          const on = view === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => setView(item.id)}
              className={`flex min-h-14 flex-col items-center justify-center gap-1 text-xs ${on ? "text-teal" : "text-muted"}`}
            >
              <Icon className="size-4" aria-hidden="true" />
              {item.label}
            </button>
          );
        })}
      </nav>
    </div>
  );
}
