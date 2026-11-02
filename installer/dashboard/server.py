"""JARVIS Mission Control, Windows-friendly stdlib server."""
from __future__ import annotations

import base64
import json
import mimetypes
import os
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

ROOT = Path(os.environ.get("JARVIS_PROJECT_ROOT", Path(__file__).resolve().parent)).resolve()
HERMES = Path(os.environ.get("HERMES_HOME", Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "hermes")).resolve()
HOST = "127.0.0.1"
PORT = int(os.environ.get("JARVIS_DASHBOARD_PORT", "8899"))
LOG_DB = Path(os.environ.get("AGENT_LOG_DB", ROOT / "agent-logs.db")).resolve()
VERSION = os.environ.get("JARVIS_VERSION", "v0.1")
VOICE_CONFIG = ROOT / "voice-config.json"
EVENTS = ("state",)
CREW = [
    {"key": "default", "name": "JARVIS", "code": "J-00", "initials": "JV", "role": "Chief of staff", "tagline": "Routes, verifies, reports"},
    {"key": "dev", "name": "DEV", "code": "J-01", "initials": "DV", "role": "Build engineer", "tagline": "Makes the machine useful"},
    {"key": "research", "name": "RESEARCH", "code": "J-02", "initials": "RS", "role": "Research lead", "tagline": "Evidence before confidence"},
    {"key": "assistant", "name": "ASSISTANT", "code": "J-03", "initials": "AS", "role": "Executive assistant", "tagline": "Quietly keeps the day moving"},
]

def now_ms() -> int:
    return int(time.time() * 1000)

def db_rows() -> list[dict]:
    if not LOG_DB.exists():
        return []
    try:
        with sqlite3.connect(f"file:{LOG_DB}?mode=ro", uri=True, timeout=0.5) as db:
            db.row_factory = sqlite3.Row
            return [dict(row) for row in db.execute("SELECT agent_name, task_description, model_used, status, created_at FROM agent_logs ORDER BY id DESC LIMIT 80")]
    except sqlite3.Error:
        return []

def shelves() -> dict:
    total = 0
    result = []
    for agent in CREW:
        folder = ROOT / "content" / agent["key"]
        docs = []
        for path in sorted(folder.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True) if folder.exists() else []:
            text = path.read_text(encoding="utf-8", errors="replace")
            docs.append({"file": path.name, "title": text.splitlines()[0].lstrip("# ") if text else path.stem, "bytes": path.stat().st_size, "words": len(text.split()), "sections": text.count("\n#"), "read_min": max(1, len(text.split()) // 220), "created": path.stat().st_ctime, "modified": path.stat().st_mtime})
        total += len(docs)
        result.append({"agent": agent["key"], "count": len(docs), "docs": docs})
    return {"total": total, "shelves": result}

def read_cron_jobs() -> list[dict]:
    path = HERMES / "cron" / "jobs.json"
    if not path.is_file():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, list) else payload.get("jobs", [])
    except (OSError, ValueError):
        return []

def read_voice_config() -> dict:
    default = {"scenario": 1, "el_key_present": False, "el_voice": None, "el_voice_name": None}
    try:
        if VOICE_CONFIG.is_file():
            value = json.loads(VOICE_CONFIG.read_text(encoding="utf-8"))
            default.update(value)
    except (OSError, ValueError):
        pass
    return default

def state() -> dict:
    rows = db_rows()
    counts = {a["name"]: {"completed": 0, "running": 0, "failed": 0, "tasks": 0} for a in CREW}
    for row in rows:
        name = row.get("agent_name", "")
        if name in counts:
            counts[name][row.get("status", "running")] = counts[name].get(row.get("status", "running"), 0) + 1
            counts[name]["tasks"] += 1
    total_tasks = sum(v["tasks"] for v in counts.values())
    crew = []
    for a in CREW:
        c = counts[a["name"]]
        crew.append({**a, "state": "active" if c["tasks"] else "standby", "model": None, "channel": "telegram" if a["key"] == "default" else "cli", "telegram": a["key"] == "default", "reachable": True, "share": round(c["tasks"] * 100 / total_tasks) if total_tasks else 0, "sessions": None, "messages": None, "tokens": None, "tasks": c["tasks"], "failed": c["failed"], "events": c["tasks"], "hourly": [0] * 13, "mix": {k: c[k] for k in ("completed", "running", "failed")}})
    ops = [{"t": row["created_at"][-8:], "agent": row["agent_name"], "op": row["task_description"], "state": "failed" if row["status"] == "failed" else "ok", "model": row["model_used"]} for row in rows]
    return {"crew": crew, "ops": ops, "sessions": {"totals": {"sessions": None, "messages": None, "tokens": None, "tool_calls": None, "input": None, "output": None, "cache_read": None, "reasoning": None, "cost": None}, "recent": []}, "heatmap": {"rows": [{"key": a["key"], "name": a["name"], "counts": [0] * 24, "total": 0} for a in CREW], "max": 0, "total_events": len(rows), "peak_hour": None}, "hourly": [0] * 13, "hourly_peak": None, "box": {"cpu_pct": None, "mem_pct": None, "disk_pct": None, "load1": None, "hostname": os.environ.get("COMPUTERNAME", "windows")}, "gateway": {"state": "unknown", "pid": None, "platforms": ["telegram"]}, "events": [r["task_description"] for r in rows], "alerts": [], "capabilities": {"mail": {"connected": False, "count": None, "next": None, "checked_at": None, "stale": False, "reason": "not connected", "items": []}, "calendar": {"connected": False, "count": None, "next": None, "checked_at": None, "stale": False, "reason": "not connected", "items": []}}, "version": VERSION}

def json_response(handler: BaseHTTPRequestHandler, payload: object, status: int = 200, content_type: str = "application/json; charset=utf-8") -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)

class Handler(BaseHTTPRequestHandler):
    server_version = "JARVIS/0.1"
    def log_message(self, fmt, *args):
        return
    def do_GET(self):
        parsed = urlparse(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        if path == "/events":
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Cache-Control", "no-store"); self.send_header("Connection", "keep-alive"); self.send_header("X-Accel-Buffering", "no"); self.end_headers()
            try:
                self.wfile.write(b"retry: 5000\n\n"); self.wfile.flush()
                while True:
                    data = json.dumps(state(), ensure_ascii=False).encode("utf-8")
                    self.wfile.write(b"event: state\ndata: " + data + b"\n\n"); self.wfile.flush(); time.sleep(3)
            except (BrokenPipeError, ConnectionResetError): return
        if path == "/api/state": return json_response(self, state())
        if path == "/api/content": return json_response(self, shelves())
        if path == "/api/owner":
            user = HERMES / "memories" / "USER.md"; first = ""
            if user.exists(): first = user.read_text(encoding="utf-8", errors="replace").split()[0] if user.read_text(encoding="utf-8", errors="replace").split() else ""
            return json_response(self, {"name": first if first.isalpha() else ""})
        if path == "/api/models": return json_response(self, {"agents": [{**a, "model": None, "provider": "custom"} for a in CREW], "providers": [{"slug": "custom", "name": "Custom", "models": ["gpt-oss:20b"], "total": 1}], "loading": False, "error": None})
        if path == "/api/chat/history": return json_response(self, {"session": None, "telegram": False, "messages": []})
        if path == "/api/cron": return json_response(self, {"jobs": read_cron_jobs()})
        if path == "/api/voice/config": return json_response(self, read_voice_config())
        if path == "/docs.md": return self.send_file(ROOT / "docs.md", "text/markdown; charset=utf-8")
        if path in ("/", "/template", "/styles.css", "/script.js", "/favicon.svg", "/upload"):
            file = {"/": "index.html", "/template": "jarvis-dashboard-template.html", "/upload": "upload.html"}.get(path, path.lstrip("/"))
            return self.send_file(ROOT / file)
        if path == "/api/content/read":
            agent, file = query.get("agent", [""])[0], query.get("file", [""])[0]
            if "/" in file or ".." in file: return json_response(self, {"error": "not found"}, 404)
            target = ROOT / "content" / agent / file
            if not target.is_file(): return json_response(self, {"error": "not found"}, 404)
            text = target.read_text(encoding="utf-8", errors="replace"); return json_response(self, {"title": text.splitlines()[0].lstrip("# ") if text else file, "text": text, "file": file})
        return json_response(self, {"error": "not found"}, 404)
    def send_file(self, path: Path, content_type: str | None = None):
        if not path.is_file(): return json_response(self, {"error": "not found"}, 404)
        body = path.read_bytes(); self.send_response(200); self.send_header("Content-Type", content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"); self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        parsed = urlparse(self.path); length = int(self.headers.get("Content-Length", "0")); raw = self.rfile.read(length)
        if parsed.path == "/api/upload":
            try:
                payload = json.loads(raw); name = payload["name"]
                if "/" in name or "\\" in name or ".." in name or Path(name).suffix.lower() not in {".html", ".png", ".jpg", ".jpeg", ".webp", ".svg"}: raise ValueError("invalid filename")
                data = payload["data"].split(",", 1)[-1]; body = base64.b64decode(data); target = ROOT / name; target.write_bytes(body); return json_response(self, {"ok": True, "filename": name, "path": str(target), "size": len(body)})
            except Exception as exc: return json_response(self, {"ok": False, "error": str(exc)}, 400)
        if parsed.path == "/api/chat/send":
            try:
                payload = json.loads(raw); agent, text = payload["agent"], payload["text"]
                cmd = ["hermes"] + ([] if agent == "default" else ["-p", agent]) + ["-z", text]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env={**os.environ, "HERMES_HOME": str(HERMES)})
                return json_response(self, result.stdout.strip() if result.returncode == 0 else result.stderr.strip(), 200 if result.returncode == 0 else 502, "text/plain; charset=utf-8")
            except Exception as exc: return json_response(self, {"error": str(exc)}, 502)
        if parsed.path == "/api/models/set":
            try:
                payload = json.loads(raw); agent = payload["agent"]; model = payload["model"]; provider = payload["provider"]
                target = HERMES / "config.yaml" if agent == "default" else HERMES / "profiles" / agent / "config.yaml"
                if agent not in {a["key"] for a in CREW} or not target.is_file(): raise ValueError("unknown agent")
                lines = target.read_text(encoding="utf-8").splitlines()
                output, in_model = [], False
                for line in lines:
                    if line == "model:": in_model = True
                    elif in_model and line and not line.startswith(" "): in_model = False
                    if in_model and line.startswith("  default:"): line = f'  default: "{model}"'
                    if in_model and line.startswith("  provider:"): line = f'  provider: "{provider}"'
                    output.append(line)
                tmp = target.with_suffix(".yaml.tmp"); tmp.write_text("\n".join(output) + "\n", encoding="utf-8"); tmp.replace(target)
                return json_response(self, {"ok": True})
            except Exception as exc: return json_response(self, {"ok": False, "error": str(exc)}, 400)
        if parsed.path == "/api/cron/action":
            action = parse_qs(parsed.query).get("action", [""])[0]; job_id = parse_qs(parsed.query).get("id", [""])[0]
            commands = {"run": "run", "pause": "pause", "resume": "resume", "delete": "remove"}
            if action not in commands or not job_id: return json_response(self, {"ok": False, "error": "invalid action"}, 400)
            result = subprocess.run(["hermes", "cron", commands[action], job_id], capture_output=True, text=True, env={**os.environ, "HERMES_HOME": str(HERMES)})
            return json_response(self, {"ok": result.returncode == 0, "error": result.stderr.strip() if result.returncode else None}, 200 if result.returncode == 0 else 502)
        if parsed.path == "/api/content/delete":
            query = parse_qs(parsed.query); agent, file = query.get("agent", [""])[0], query.get("file", [""])[0]
            if "/" in file or ".." in file: return json_response(self, {"error": "not found"}, 404)
            target = ROOT / "content" / agent / file
            if not target.is_file(): return json_response(self, {"error": "not found"}, 404)
            target.unlink(); return json_response(self, {"ok": True})
        if parsed.path == "/api/voice/config":
            try:
                value = json.loads(raw); scenario = int(value["scenario"])
                if scenario not in (1, 2, 3): raise ValueError("scenario must be 1, 2, or 3")
                VOICE_CONFIG.write_text(json.dumps({**read_voice_config(), "scenario": scenario}), encoding="utf-8")
                return json_response(self, read_voice_config())
            except Exception as exc: return json_response(self, {"error": str(exc)}, 400)
        if parsed.path == "/api/voice":
            try:
                payload = json.loads(raw); request = urllib.request.Request("http://127.0.0.1:8767/say?voice=bm_daniel", data=str(payload.get("text", "")).encode(), method="POST")
                with urllib.request.urlopen(request, timeout=60) as response: audio = response.read()
                self.send_response(200); self.send_header("Content-Type", "audio/wav"); self.send_header("X-Jarvis-Voice-Engine", "kokoro"); self.send_header("Content-Length", str(len(audio))); self.end_headers(); self.wfile.write(audio); return
            except Exception as exc: return json_response(self, {"error": str(exc)}, 502)
        if parsed.path == "/api/greeting": return json_response(self, {"error": "greeting cache is not generated"}, 404)
        if parsed.path == "/api/transcribe": return json_response(self, {"error": "ElevenLabs transcription is not enabled"}, 501)
        return json_response(self, {"error": "not found"}, 404)

if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    ThreadingHTTPServer.allow_reuse_address = True
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
