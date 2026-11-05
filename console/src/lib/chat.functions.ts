import { createServerFn } from "@tanstack/react-start";
import { agentByKey, systemPrompt, voiceFor, type AgentKey } from "@/lib/crew";

type HistoryTurn = { role: "user" | "assistant"; text: string };

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

function splitTopic(content: string) {
  const match = content.match(/\n?TOPIC:\s*(.+)\s*$/i);
  const topic = match?.[1]?.replace(/^["']|["']$/g, "").trim().slice(0, 64);
  const text = (match ? content.slice(0, match.index) : content).trim();
  return { text: text || content.trim(), topic: topic || "Open thread" };
}

export const askCrew = createServerFn({ method: "POST" })
  .validator(parseAsk)
  .handler(async ({ data }) => {
    const apiKey = process.env.XAI_API_KEY;
    if (!apiKey) return { ok: false as const, error: "The crew is offline in this environment." };

    const messages = [
      { role: "system", content: systemPrompt(data.agent) },
      ...data.history.map((turn) => ({ role: turn.role, content: turn.text })),
      { role: "user", content: data.text },
    ];

    const res = await fetch("https://api.x.ai/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: "grok-4.5",
        max_tokens: 280,
        temperature: 0.6,
        messages,
      }),
    });

    if (!res.ok) return { ok: false as const, error: `Crew request failed (${res.status}).` };
    const body = (await res.json()) as { choices?: { message?: { content?: string } }[] };
    const content = body.choices?.[0]?.message?.content?.trim();
    if (!content) return { ok: false as const, error: "Empty reply." };
    const parsed = splitTopic(content);
    return { ok: true as const, agent: data.agent, ...parsed };
  });

function parseSpeak(input: unknown) {
  if (!input || typeof input !== "object") throw new Error("Missing request.");
  const raw = input as { text?: unknown; agent?: unknown };
  const text = typeof raw.text === "string" ? raw.text.trim().slice(0, 420) : "";
  if (!text) throw new Error("Nothing to say.");
  const agent = agentByKey(typeof raw.agent === "string" ? raw.agent : "default").key as AgentKey;
  return { text, agent };
}

export const speakReply = createServerFn({ method: "POST" })
  .validator(parseSpeak)
  .handler(async ({ data }) => {
    const apiKey = process.env.XAI_API_KEY;
    if (!apiKey) return { ok: false as const, error: "Voice is offline." };

    async function call(voice: string) {
      return fetch("https://api.x.ai/v1/tts", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({ text: data.text, voice_id: voice, language: "en" }),
      });
    }

    let res = await call(voiceFor(data.agent));
    if (!res.ok) res = await call("eve");
    if (!res.ok) return { ok: false as const, error: `Voice failed (${res.status}).` };
    const bytes = new Uint8Array(await res.arrayBuffer());
    let binary = "";
    const chunk = 0x8000;
    for (let i = 0; i < bytes.length; i += chunk) {
      binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
    }
    return { ok: true as const, audio: btoa(binary), mime: res.headers.get("content-type") || "audio/mpeg" };
  });
