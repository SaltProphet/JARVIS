function createLayeredField() {
  async function refreshModel() {
    const indicator = document.getElementById("model-runtime");
    try {
      const response = await fetch("/api/models/runtime");
      if (!response.ok) throw new Error("Status unavailable");
      const data = await response.json();
      indicator.textContent = `Model · ${data.state}${data.models.length ? " · " + data.models.join(", ") : ""} | STT · ${data.speech.state}`;
      indicator.dataset.state = data.state;
      indicator.title = data.detail + "; speech model: " + data.speech.name;
    } catch (error) {
      indicator.textContent = "Model · unknown";
      indicator.dataset.state = "unknown";
      indicator.title = error.message;
    }
    setTimeout(refreshModel, 3000);
  }
  refreshModel();

  const host = document.querySelector(".orb-stage");
  host.innerHTML = '<canvas id="system-field" aria-hidden="true"></canvas>';
  const canvas = document.getElementById("system-field");
  const ctx = canvas.getContext("2d");
  const reduce = matchMedia("(prefers-reduced-motion: reduce)");
  const golden = Math.PI * (3 - Math.sqrt(5));
  const count = 168;
  const cells = Array.from({ length: count }, (_, index) => {
    const y = 1 - (index / (count - 1)) * 2;
    const radius = Math.sqrt(1 - y * y);
    const theta = golden * index;
    return { x: Math.cos(theta) * radius, y, z: Math.sin(theta) * radius };
  });
  const mist = Array.from({ length: 42 }, (_, index) => ({
    orbit: 0.46 + (index % 8) * 0.07,
    speed: 0.12 + (index % 5) * 0.04,
    phase: (index / 42) * Math.PI * 2,
    radius: 1.1 + (index % 4) * 0.7,
  }));
  let width = 0;
  let height = 0;
  let frame = 0;
  let turn = 0.4;
  let last = 0;

  function litCount() {
    const status = document.getElementById("conversation-status");
    const phase = `${status?.dataset.phase || ""} ${status?.textContent || ""}`.toLowerCase();
    if (talk.captureActive || phase.includes("listen")) return 18;
    if (phase.includes("think") || phase.includes("transcrib") || phase.includes("speak") || phase.includes("wait")) return 10;
    return 0;
  }

  function project(cell, yaw, pitch) {
    const x1 = cell.x * Math.cos(yaw) + cell.z * Math.sin(yaw);
    const z1 = -cell.x * Math.sin(yaw) + cell.z * Math.cos(yaw);
    const y2 = cell.y * Math.cos(pitch) - z1 * Math.sin(pitch);
    const z2 = cell.y * Math.sin(pitch) + z1 * Math.cos(pitch);
    return { x: x1, y: y2, depth: (z2 + 1) / 2 };
  }

  function size() {
    const box = host.getBoundingClientRect();
    width = box.width;
    height = box.height;
    const ratio = Math.min(devicePixelRatio || 1, 2);
    canvas.width = width * ratio;
    canvas.height = height * ratio;
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    draw();
  }

  function draw() {
    ctx.clearRect(0, 0, width, height);
    const cx = width / 2;
    const cy = height / 2;
    const scale = Math.min(width, height) * 0.34;
    const yaw = turn;
    const pitch = Math.sin(turn * 0.35) * 0.45;
    const hot = litCount();
    ctx.strokeStyle = "#334155";
    ctx.lineWidth = 1;
    ctx.globalAlpha = 0.45;
    ctx.beginPath();
    ctx.moveTo(cx - scale * 1.15, cy);
    ctx.lineTo(cx + scale * 1.15, cy);
    ctx.moveTo(cx, cy - scale * 1.05);
    ctx.lineTo(cx, cy + scale * 1.05);
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx, cy, scale * 1.05, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;

    mist.forEach((speck, index) => {
      const t = turn * speck.speed + speck.phase;
      const drift = Math.sin(t * 1.6) * 0.04;
      const x = cx + Math.cos(t) * (speck.orbit + drift) * scale;
      const y = cy + Math.sin(t * 0.85) * speck.orbit * 0.62 * scale;
      ctx.globalAlpha = 0.08 + ((Math.sin(t) + 1) / 2) * 0.22;
      ctx.fillStyle = "#cbd5e1";
      ctx.beginPath();
      ctx.arc(x, y, speck.radius, 0, Math.PI * 2);
      ctx.fill();
      if (index % 3 === 0) return;
    });

    const drawn = cells.map((cell, index) => ({ ...project(cell, yaw, pitch), index }));
    drawn.sort((a, b) => a.depth - b.depth);
    drawn.forEach((point) => {
      const lit = hot > 0 && point.index % 21 < hot / 6;
      const size = 3 + point.depth * 7;
      const x = cx + point.x * scale - size / 2;
      const y = cy + point.y * scale * 0.94 - size / 2;
      ctx.globalAlpha = 0.16 + point.depth * 0.84;
      ctx.lineWidth = 0.6 + point.depth * 0.9;
      ctx.strokeStyle = lit ? "#c43218" : "#94a3b8";
      ctx.fillStyle = lit ? "rgba(196, 50, 24, 0.38)" : `rgba(148, 163, 184, ${point.depth * 0.12})`;
      ctx.fillRect(x, y, size, size);
      ctx.strokeRect(x, y, size, size);
    });
    ctx.globalAlpha = 1;
  }

  function loop(time) {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    if (document.hidden) return;
    if (!reduce.matches) turn += 0.006;
    if (time - last > 32) {
      draw();
      last = time;
    }
    frame = requestAnimationFrame(loop);
  }

  new ResizeObserver(size).observe(host);
  document.addEventListener("visibilitychange", () => loop(performance.now()));
  reduce.addEventListener("change", () => draw());
  size();
  loop(performance.now());
}
