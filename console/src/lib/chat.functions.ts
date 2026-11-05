import { createServerFn } from "@tanstack/react-start";
import { agentByKey, type AgentKey } from "@/lib/crew";

type HistoryTurn = { role: "user" | "assistant"; text: string };

function dashboard() {
  return (process.env.JARVIS_DASHBOARD_URL || "http://127.0.0.1:8899").replace(/\/$/, "");
}

function offline() {
  return `Dashboard is not running at ${dashboard()}.`;
}

function parseAsk(input: unknown) {
  if (!input || typeof input !== "object") throw new Error("Missing request.");
  const raw = input as { agent?: unknown; text?: unknown; history?: unknown };
  const text = typeof raw.text === "string" ? raw.text.trim().slice(0, 1800) : "";
  if (!text) throw new Error("Say something first.");
  const agent = agentByKey(typeof raw.agent === "string" ? raw.agent : "default").key;
  const history: HistoryTurn[] = [];
  if (Array.isArray(raw.history)) {
    for (const item of raw.history.slice(-6)) {
      if (!item || typeof item !== "object") continue;
      const turn = item as { role?: unknown; text?: unknown };
      if ((turn.role === "user" || turn.role === "assistant") && typeof turn.text === "string") {
        history.push({ role: turn.role, text: turn.text.slice(0, 800) });
      }
    }
  }
  return { agent, text, history };
}

export const askCrew = createServerFn({ method: "POST" })
  .validator(parseAsk)
  .handler(async ({ data }) => {
    let res: Response;
    try {
      res = await fetch(`${dashboard()}/api/chat/send`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ agent: data.agent, text: data.text }),
      });
    } catch {
      return { ok: false as const, error: offline() };
    }
    const reply = (await res.text()).trim();
    if (!res.ok) return { ok: false as const, error: reply || "Hermes did not answer." };
    if (!reply) return { ok: false as const, error: "Hermes returned an empty reply." };
    const topic = reply.split("\n")[0]?.trim().slice(0, 48);
    return { ok: true as const, agent: data.agent, text: reply, topic };
  });

function parseSpeak(input: unknown) {
  if (!input || typeof input !== "object") throw new Error("Missing request.");
  const raw = input as { text?: unknown; agent?: unknown };
  const text = typeof raw.text === "string" ? raw.text.trim().slice(0, 420) : "";
  if (!text) throw new Error("Nothing to say.");
  const agent = agentByKey(typeof raw.agent === "string" ? raw.agent : "default").key as AgentKey;
  return { text, agent };
}

function toBase64(bytes: Uint8Array) {
  let binary = "";
  const chunk = 0x8000;
  for (let index = 0; index < bytes.length; index += chunk) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunk));
  }
  return btoa(binary);
}

export const speakReply = createServerFn({ method: "POST" })
  .validator(parseSpeak)
  .handler(async ({ data }) => {
    let res: Response;
    try {
      res = await fetch(`${dashboard()}/api/voice`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: data.text }),
      });
    } catch {
      return { ok: false as const, error: offline() };
    }
    if (!res.ok) return { ok: false as const, error: "Kokoro did not answer." };
    return {
      ok: true as const,
      audio: toBase64(new Uint8Array(await res.arrayBuffer())),
      mime: "audio/wav",
    };
  });

function parseClip(input: unknown) {
  if (!input || typeof input !== "object") throw new Error("Missing audio.");
  const raw = input as { audio?: unknown; mime?: unknown };
  const audio = typeof raw.audio === "string" ? raw.audio : "";
  const mime = typeof raw.mime === "string" && raw.mime.startsWith("audio/") ? raw.mime : "audio/webm";
  if (!audio || audio.length > 8_000_000) throw new Error("Audio clip is empty or too large.");
  return { audio, mime };
}

export const transcribeClip = createServerFn({ method: "POST" })
  .validator(parseClip)
  .handler(async ({ data }) => {
    const bytes = Buffer.from(data.audio, "base64");
    let res: Response;
    try {
      res = await fetch(`${dashboard()}/api/transcribe`, {
        method: "POST",
        headers: { "Content-Type": data.mime },
        body: bytes,
      });
    } catch {
      return { ok: false as const, error: offline() };
    }
    const payload = (await res.json().catch(() => null)) as { text?: string; error?: string } | null;
    if (!res.ok) return { ok: false as const, error: payload?.error || "Transcription failed." };
    return { ok: true as const, text: payload?.text?.trim() || "" };
  });
