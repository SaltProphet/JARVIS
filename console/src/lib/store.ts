import { create } from "zustand";
import { persist } from "zustand/middleware";
import type { AgentKey } from "@/lib/crew";

export type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  agent: AgentKey;
  text: string;
  topic?: string;
  at: number;
};

export type Note = {
  id: string;
  title: string;
  body: string;
  agent: AgentKey;
  at: number;
};

type MissionState = {
  agent: AgentKey;
  view: "home" | "agents" | "map" | "library" | "control";
  messages: ChatMessage[];
  notes: Note[];
  spoken: boolean;
  volume: number;
  hydrated: boolean;
  setAgent: (agent: AgentKey) => void;
  setView: (view: MissionState["view"]) => void;
  setSpoken: (spoken: boolean) => void;
  setVolume: (volume: number) => void;
  push: (message: ChatMessage) => void;
  pin: (note: Note) => void;
  dropNote: (id: string) => void;
  clearThread: () => void;
  markHydrated: () => void;
};

export const useMission = create<MissionState>()(
  persist(
    (set) => ({
      agent: "default",
      view: "home",
      messages: [],
      notes: [],
      spoken: true,
      volume: 80,
      hydrated: false,
      setAgent: (agent) => set({ agent }),
      setView: (view) => set({ view }),
      setSpoken: (spoken) => set({ spoken }),
      setVolume: (volume) => set({ volume }),
      push: (message) =>
        set((state) => ({ messages: [...state.messages, message].slice(-80) })),
      pin: (note) => set((state) => ({ notes: [note, ...state.notes].slice(0, 40) })),
      dropNote: (id) => set((state) => ({ notes: state.notes.filter((note) => note.id !== id) })),
      clearThread: () => set({ messages: [] }),
      markHydrated: () => set({ hydrated: true }),
    }),
    {
      name: "jarvis-mission",
      skipHydration: true,
      partialize: (state) => ({
        agent: state.agent,
        messages: state.messages,
        notes: state.notes,
        spoken: state.spoken,
        volume: state.volume,
      }),
    },
  ),
);
