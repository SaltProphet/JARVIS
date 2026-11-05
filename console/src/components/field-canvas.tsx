import { useEffect, useRef, useState } from "react";

type Props = {
  listening: boolean;
  phase: string;
  topics: string[];
};

type Cell = { x: number; y: number; z: number };

const CELLS: Cell[] = (() => {
  const count = 168;
  const golden = Math.PI * (3 - Math.sqrt(5));
  const cells: Cell[] = [];
  for (let i = 0; i < count; i += 1) {
    const y = 1 - (i / (count - 1)) * 2;
    const radius = Math.sqrt(1 - y * y);
    const theta = golden * i;
    cells.push({ x: Math.cos(theta) * radius, y, z: Math.sin(theta) * radius });
  }
  return cells;
})();

const MIST = Array.from({ length: 42 }, (_, index) => ({
  orbit: 16 + (index % 8) * 3.4,
  speed: 0.12 + (index % 5) * 0.04,
  phase: (index / 42) * Math.PI * 2,
  radius: 0.22 + (index % 4) * 0.16,
}));

function place(cell: Cell, yaw: number, pitch: number) {
  const x1 = cell.x * Math.cos(yaw) + cell.z * Math.sin(yaw);
  const z1 = -cell.x * Math.sin(yaw) + cell.z * Math.cos(yaw);
  const y2 = cell.y * Math.cos(pitch) - z1 * Math.sin(pitch);
  const z2 = cell.y * Math.sin(pitch) + z1 * Math.cos(pitch);
  const depth = (z2 + 1) / 2;
  const size = 0.9 + depth * 2.8;
  return {
    x: 50 + x1 * 38 - size / 2,
    y: 50 + y2 * 36 - size / 2,
    size,
    opacity: 0.16 + depth * 0.84,
    depth,
  };
}

export function FieldCanvas({ listening, phase, topics }: Props) {
  const svgRef = useRef<SVGSVGElement>(null);
  const [mounted, setMounted] = useState(false);
  const hot = listening ? 18 : phase === "Thinking" || phase === "Speaking" ? 10 : Math.min(topics.length, 8);

  useEffect(() => {
    setMounted(true);
  }, []);

  const turn = useRef(0.4);

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg || !mounted) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    let raf = 0;
    const draw = () => {
      turn.current += 0.006;
      const yaw = turn.current;
      const pitch = Math.sin(turn.current * 0.35) * 0.45;
      const drawn: { node: SVGRectElement; depth: number }[] = [];
      svg.querySelectorAll<SVGRectElement>("[data-cell]").forEach((node, index) => {
        const cell = CELLS[index];
        if (!cell) return;
        const point = place(cell, yaw, pitch);
        const lit = index % 21 < hot / 6 && hot > 0;
        node.setAttribute("x", point.x.toFixed(2));
        node.setAttribute("y", point.y.toFixed(2));
        node.setAttribute("width", point.size.toFixed(2));
        node.setAttribute("height", point.size.toFixed(2));
        node.setAttribute("opacity", point.opacity.toFixed(2));
        node.setAttribute("stroke", lit ? "#c43218" : "#94a3b8");
        node.setAttribute("stroke-width", (0.12 + point.depth * 0.22).toFixed(2));
        node.setAttribute("fill", lit ? "rgba(196, 50, 24, 0.38)" : `rgba(148, 163, 184, ${(point.depth * 0.1).toFixed(3)})`);
        drawn.push({ node, depth: point.depth });
      });
      drawn.sort((a, b) => a.depth - b.depth);
      for (const item of drawn) svg.appendChild(item.node);
      svg.querySelectorAll<SVGCircleElement>("[data-mist]").forEach((node, index) => {
        const speck = MIST[index];
        if (!speck) return;
        const t = turn.current * speck.speed + speck.phase;
        const drift = Math.sin(t * 1.6) * 2.4;
        node.setAttribute("cx", (50 + Math.cos(t) * (speck.orbit + drift)).toFixed(2));
        node.setAttribute("cy", (50 + Math.sin(t * 0.85) * speck.orbit * 0.62).toFixed(2));
        node.setAttribute("opacity", (0.08 + ((Math.sin(t) + 1) / 2) * 0.28).toFixed(2));
        if (index % 3 === 0) svg.appendChild(node);
      });
      raf = requestAnimationFrame(draw);
    };
    raf = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(raf);
  }, [hot, mounted]);

  return (
    <svg ref={svgRef} viewBox="0 0 100 100" className="h-full w-full" role="img" aria-label="Orb">
      <line x1="0" y1="50" x2="100" y2="50" stroke="#334155" strokeWidth="0.12" />
      <line x1="50" y1="8" x2="50" y2="92" stroke="#334155" strokeWidth="0.12" />
      <circle cx="50" cy="50" r="8" fill="#94a3b8" opacity="0.08" />
      <circle cx="50" cy="50" r="30" fill="none" stroke="#64748b" strokeWidth="0.15" opacity="0.35" />
      <circle cx="50" cy="50" r="42" fill="none" stroke="#334155" strokeWidth="0.12" strokeDasharray="0.3 1.6" />
      {mounted &&
        MIST.map((speck, index) => (
          <circle
            key={`mist-${index}`}
            data-mist=""
            cx={50 + Math.cos(speck.phase) * speck.orbit}
            cy={50 + Math.sin(speck.phase) * speck.orbit * 0.62}
            r={speck.radius}
            fill="#cbd5e1"
            opacity="0.16"
          />
        ))}
      {mounted &&
        CELLS.map((cell, index) => {
          const point = place(cell, 0.4, 0.2);
          return (
            <rect
              key={index}
              data-cell=""
              x={point.x.toFixed(2)}
              y={point.y.toFixed(2)}
              width={point.size.toFixed(2)}
              height={point.size.toFixed(2)}
              fill="none"
              stroke={index % 21 < hot / 6 && hot > 0 ? "#c43218" : "#94a3b8"}
              strokeWidth="0.22"
              opacity={point.opacity.toFixed(2)}
            />
          );
        })}
    </svg>
  );
}
