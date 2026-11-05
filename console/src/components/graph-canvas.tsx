import { useEffect, useRef } from "react";
import { AGENTS, type AgentKey } from "@/lib/crew";

type Node = { id: string; label: string; kind: "agent" | "topic"; agent?: AgentKey };

type Props = {
  topics: { label: string; agent: AgentKey }[];
  active: AgentKey;
  onPick: (agent: AgentKey) => void;
};

export function GraphCanvas({ topics, active, onPick }: Props) {
  const ref = useRef<HTMLCanvasElement>(null);
  const nodes = useRef<Node[]>([]);

  useEffect(() => {
    const canvas = ref.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const layout: Node[] = [
      ...AGENTS.map((agent) => ({ id: agent.key, label: agent.name, kind: "agent" as const, agent: agent.key })),
      ...topics.slice(-12).map((topic, index) => ({
        id: `t-${index}-${topic.label}`,
        label: topic.label,
        kind: "topic" as const,
        agent: topic.agent,
      })),
    ];
    nodes.current = layout;

    const positions = new Map<string, { x: number; y: number }>();
    let raf = 0;

    const draw = () => {
      const parent = canvas.parentElement;
      const width = parent?.clientWidth ?? 640;
      const height = parent?.clientHeight ?? 480;
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = "#000000";
      ctx.fillRect(0, 0, width, height);

      layout.forEach((node, index) => {
        if (node.kind === "agent") {
          const slot = AGENTS.findIndex((agent) => agent.key === node.agent);
          const angle = -Math.PI / 2 + (slot / AGENTS.length) * Math.PI * 2;
          positions.set(node.id, {
            x: width * 0.5 + Math.cos(angle) * Math.min(width, height) * 0.28,
            y: height * 0.46 + Math.sin(angle) * Math.min(width, height) * 0.22,
          });
        } else {
          const ring = 70 + (index % 6) * 18;
          const angle = (index / Math.max(layout.length, 1)) * Math.PI * 2;
          const owner = positions.get(node.agent ?? "default");
          positions.set(node.id, {
            x: (owner?.x ?? width / 2) + Math.cos(angle) * ring,
            y: (owner?.y ?? height / 2) + Math.sin(angle) * ring * 0.7,
          });
        }
      });

      ctx.lineWidth = 1;
      for (const node of layout) {
        if (node.kind !== "topic" || !node.agent) continue;
        const from = positions.get(node.agent);
        const to = positions.get(node.id);
        if (!from || !to) continue;
        ctx.strokeStyle = "rgba(5, 180, 201, 0.35)";
        ctx.beginPath();
        ctx.moveTo(from.x, from.y);
        ctx.lineTo(to.x, to.y);
        ctx.stroke();
      }

      for (const node of layout) {
        const point = positions.get(node.id);
        if (!point) continue;
        const on = node.agent === active && node.kind === "agent";
        ctx.beginPath();
        ctx.arc(point.x, point.y, node.kind === "agent" ? 8 : 4, 0, Math.PI * 2);
        ctx.fillStyle = on ? "#9af6ff" : node.kind === "agent" ? "#05b4c9" : "#94a3b8";
        ctx.fill();
        ctx.fillStyle = "#e8eef3";
        ctx.font = "12px IBM Plex Mono, monospace";
        ctx.textAlign = "center";
        ctx.fillText(node.label.slice(0, 26), point.x, point.y - 14);
      }

      raf = requestAnimationFrame(draw);
    };

    const onClick = (event: MouseEvent) => {
      const rect = canvas.getBoundingClientRect();
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;
      for (const node of nodes.current) {
        if (node.kind !== "agent" || !node.agent) continue;
        const point = positions.get(node.id);
        if (!point) continue;
        const dx = point.x - x;
        const dy = point.y - y;
        if (dx * dx + dy * dy < 28 * 28) onPick(node.agent);
      }
    };

    raf = requestAnimationFrame(draw);
    canvas.addEventListener("click", onClick);
    return () => {
      cancelAnimationFrame(raf);
      canvas.removeEventListener("click", onClick);
    };
  }, [topics, active, onPick]);

  return <canvas ref={ref} className="block h-full w-full" />;
}
