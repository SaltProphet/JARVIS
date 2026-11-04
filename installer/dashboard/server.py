"""JARVIS Mission Control, Windows-friendly stdlib server."""
from __future__ import annotations

import base64
import binascii
import hashlib
import json
import mimetypes
import os
import re
import shutil
import shlex
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote_to_bytes, urlparse

ROOT = Path(os.environ.get("JARVIS_PROJECT_ROOT", Path(__file__).resolve().parent)).resolve()
HERMES = Path(os.environ.get("HERMES_HOME", Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local")) / "hermes")).resolve()
HOST = "127.0.0.1"
PORT = int(os.environ.get("JARVIS_DASHBOARD_PORT", "8899"))
LOG_DB = Path(os.environ.get("AGENT_LOG_DB", ROOT / "agent-logs.db")).resolve()
VERSION_PATH = ROOT / "version.txt"
VOICE_CONFIG = ROOT / "voice-config.json"
EVENTS = ("state",)
MAX_REQUEST_TARGET_BYTES = 4096
MAX_REQUEST_BYTES = 8 * 1024 * 1024
MAX_UPLOAD_BYTES = 5 * 1024 * 1024
IMAGE_MAX_AGE_SECONDS = 300
UPLOAD_TYPES = {
    ".html": "text/html",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp",
    ".svg": "image/svg+xml",
}
UPLOAD_LOCK = threading.Lock()
STT_LOCK = threading.Lock()
STT_MODEL = None
SERVICE_PROCESSES: dict[str, subprocess.Popen] = {}
CREW = [
    {"key": "default", "name": "JARVIS", "code": "J-00", "initials": "JV", "role": "Chief of staff", "tagline": "Routes, verifies, reports"},
    {"key": "dev", "name": "DEV", "code": "J-01", "initials": "DV", "role": "Build engineer", "tagline": "Makes the machine useful"},
    {"key": "research", "name": "RESEARCH", "code": "J-02", "initials": "RS", "role": "Research lead", "tagline": "Evidence before confidence"},
    {"key": "assistant", "name": "ASSISTANT", "code": "J-03", "initials": "AS", "role": "Executive assistant", "tagline": "Quietly keeps the day moving"},
]

def model_runtime_status():
    speech = {"name": os.environ.get("JARVIS_STT_MODEL", "base"), "state": "loaded" if STT_MODEL is not None else "loading" if STT_LOCK.locked() else "unloaded"}
    try:
        host = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434").rstrip("/")
        if not host.startswith(("http://", "https://")):
            host = "http://" + host
        with urllib.request.urlopen(host + "/api/ps", timeout=2) as response:
            models = json.load(response).get("models", [])
        return {"state": "loaded" if models else "unloaded", "models": [item.get("name", "Unknown") for item in models], "speech": speech, "detail": "Ollama residency; loading transitions unavailable from this provider"}
    except Exception as exc:
        return {"state": "unknown", "models": [], "speech": speech, "detail": "Model runtime unavailable: " + str(exc)}


def now_ms() -> int:
    return int(time.time() * 1000)


def transcribe_audio(body: bytes, content_type: str) -> str:
    """Transcribe one browser audio clip with the local faster-whisper model."""
    global STT_MODEL
    model_path = os.environ.get("JARVIS_STT_MODEL", "base")
    device = os.environ.get("JARVIS_STT_DEVICE", "cpu")
    compute_type = os.environ.get("JARVIS_STT_COMPUTE_TYPE", "int8")
    runtime_device = device
    suffix = ".webm" if "webm" in content_type else ".wav"
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as stream:
        clip = Path(stream.name)
        stream.write(body)
    try:
        with STT_LOCK:
            if STT_MODEL is None:
                from faster_whisper import WhisperModel
                try:
                    STT_MODEL = WhisperModel(model_path, device=device, compute_type=compute_type)
                except Exception:
                    if device != "cuda":
                        raise
                    STT_MODEL = WhisperModel(model_path, device="cpu", compute_type="int8")
                    runtime_device = "cpu"
        try:
            segments, _ = STT_MODEL.transcribe(str(clip), language="en", vad_filter=True)
        except Exception:
            if runtime_device != "cuda":
                raise
            with STT_LOCK:
                from faster_whisper import WhisperModel
                STT_MODEL = WhisperModel(model_path, device="cpu", compute_type="int8")
            segments, _ = STT_MODEL.transcribe(str(clip), language="en", vad_filter=True)
        return " ".join(segment.text.strip() for segment in segments).strip()
    finally:
        clip.unlink(missing_ok=True)


def read_version() -> str:
    try:
        value = VERSION_PATH.read_text(encoding="ascii").strip()
        if re.fullmatch(r"v\d+\.\d+", value):
            return value
    except (OSError, UnicodeError):
        pass
    return "v0.1"

def db_rows() -> list[dict]:
    if not LOG_DB.exists():
        return []
    db = None
    try:
        db = sqlite3.connect(f"file:{LOG_DB}?mode=ro", uri=True, timeout=0.5)
        db.row_factory = sqlite3.Row
        return [dict(row) for row in db.execute("SELECT agent_name, task_description, model_used, status, created_at FROM agent_logs ORDER BY id DESC LIMIT 80")]
    except sqlite3.Error:
        return []
    finally:
        if db is not None:
            db.close()


def process_is_alive(pid: object) -> bool:
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except (OSError, OverflowError):
        return False


def gateway_state() -> dict:
    result = {"state": "stopped", "pid": None, "platforms": []}
    try:
        value = json.loads((HERMES / "gateway_state.json").read_text(encoding="utf-8"))
        if not isinstance(value, dict):
            return result
        pid = value.get("pid")
        platforms = value.get("platforms", [])
        result["pid"] = pid if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0 else None
        result["platforms"] = [item for item in platforms if isinstance(item, str)] if isinstance(platforms, list) else []
        result["state"] = "running" if process_is_alive(result["pid"]) else "stopped"
    except (OSError, ValueError, UnicodeError):
        pass
    return result


def kokoro_state() -> dict:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8767/health", timeout=1) as response:
            if response.status == 200:
                return {"state": "running", "endpoint": "http://127.0.0.1:8767"}
    except (OSError, urllib.error.URLError):
        pass
    return {"state": "stopped", "endpoint": "http://127.0.0.1:8767"}


def stt_state() -> dict:
    model = os.environ.get("JARVIS_STT_MODEL", "base")
    try:
        import faster_whisper  # noqa: F401
    except ImportError:
        return {"state": "error", "detail": "faster-whisper is not installed", "model": model}
    return {"state": "ready", "detail": f"local {os.environ.get('JARVIS_STT_DEVICE', 'cpu')} {os.environ.get('JARVIS_STT_COMPUTE_TYPE', 'int8')}", "model": model}


def service_status() -> dict:
    gateway = gateway_state()
    kokoro = kokoro_state()
    stt = stt_state()
    return {
        "dashboard": {"id": "dashboard", "label": "Dashboard", "state": "available", "detail": f"127.0.0.1:{PORT}", "actions": []},
        "stt": {"id": "stt", "label": "Whisper", "state": stt["state"], "detail": stt["detail"], "actions": []},
        "hermes": {"id": "hermes", "label": "Hermes", "state": "running" if gateway["state"] == "running" else "stopped", "detail": ", ".join(gateway["platforms"]) or "gateway", "actions": ["start", "restart"]},
        "kokoro": {"id": "kokoro", "label": "Kokoro", "state": kokoro["state"], "detail": kokoro["endpoint"], "actions": ["start", "stop", "restart"]},
    }


def audio_devices() -> dict:
    result = {"inputs": [], "outputs": [], "default_input": None, "default_output": None, "error": None}
    try:
        import sounddevice as sd
        devices = sd.query_devices()
        defaults = sd.default.device
        for index, device in enumerate(devices):
            item = {"id": str(index), "name": str(device.get("name", f"Device {index}")), "channels": int(device.get("max_input_channels", 0) or 0)}
            if item["channels"] > 0:
                result["inputs"].append(item)
            if int(device.get("max_output_channels", 0) or 0) > 0:
                result["outputs"].append({**item, "channels": int(device.get("max_output_channels", 0) or 0)})
        if isinstance(defaults, (tuple, list)):
            if len(defaults) > 0 and defaults[0] is not None:
                result["default_input"] = str(defaults[0])
            if len(defaults) > 1 and defaults[1] is not None:
                result["default_output"] = str(defaults[1])
    except Exception as exc:
        result["error"] = str(exc)
    return result


def service_action(service: str, action: str) -> dict:
    if service not in {"hermes", "kokoro"}:
        raise RequestError("service action is not available", 404)
    if action not in {"start", "stop", "restart"}:
        raise RequestError("unknown service action")
    process = SERVICE_PROCESSES.get(service)
    if action in {"stop", "restart"} and process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
    SERVICE_PROCESSES.pop(service, None)
    if action in {"start", "restart"}:
        if service == "kokoro":
            script = ROOT / "voice" / "voice-server.py"
            command = [sys.executable, str(script)] if script.is_file() else shlex.split(os.environ.get("JARVIS_KOKORO_COMMAND", ""))
        else:
            command = shlex.split(os.environ.get("JARVIS_HERMES_GATEWAY_COMMAND", "hermes gateway run --quiet"))
        if not command:
            raise RequestError(f"no {service} start command configured", 409)
        SERVICE_PROCESSES[service] = subprocess.Popen(command, cwd=str(ROOT), env={**os.environ, "HERMES_HOME": str(HERMES)}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return {"ok": True, "service": service, "action": action, "services": service_status()}


def box_state() -> dict:
    result = {
        "cpu_pct": None,
        "mem_pct": None,
        "disk_pct": None,
        "load1": None,
        "hostname": os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME") or "windows",
    }
    try:
        usage = shutil.disk_usage(ROOT)
        result["disk_pct"] = round(usage.used * 100 / usage.total, 1) if usage.total else None
    except OSError:
        pass
    try:
        result["load1"] = round(os.getloadavg()[0], 2)
    except (AttributeError, OSError):
        pass
    return result


def activity_time(value: object) -> str:
    if not isinstance(value, str):
        return "--:--:--"
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).strftime("%H:%M:%S")
    except ValueError:
        match = re.search(r"(\d{2}:\d{2}:\d{2})", value)
        return match.group(1) if match else "--:--:--"

def shelves() -> dict:
    total = 0
    result = []
    for agent in CREW:
        folder = ROOT / "content" / agent["key"]
        docs = []
        for path in sorted(folder.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True) if folder.exists() else []:
            docs.append(content_metadata(agent["key"], path))
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


def valid_agent(agent: object) -> bool:
    return isinstance(agent, str) and agent in {item["key"] for item in CREW}


def valid_content_name(name: object) -> bool:
    if not isinstance(name, str) or not name or name != Path(name).name:
        return False
    if any(char in name for char in ("/", "\\", "\x00")) or ".." in name:
        return False
    return Path(name).suffix.lower() == ".md"


def content_metadata(agent: str, path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    title = next((line.lstrip("# ").strip() for line in lines if line.startswith("#")), path.stem)
    date = path.name[:10] if re.match(r"^\d{4}-\d{2}-\d{2}_", path.name) else None
    return {"file": path.name, "title": title, "author": agent.upper(), "date": date,
            "bytes": path.stat().st_size, "words": len(text.split()),
            "sections": sum(1 for line in lines if line.startswith("#")),
            "read_min": max(1, len(text.split()) // 220),
            "created": path.stat().st_ctime, "modified": path.stat().st_mtime}

def read_voice_config() -> dict:
    default = {"scenario": 1, "el_key_present": False, "el_voice": None, "el_voice_name": None}
    try:
        if VOICE_CONFIG.is_file():
            value = json.loads(VOICE_CONFIG.read_text(encoding="utf-8"))
            default.update(value)
    except (OSError, ValueError):
        pass
    return default


def cron_payload() -> dict:
    jobs = []
    for raw in read_cron_jobs():
        if not isinstance(raw, dict):
            continue
        jobs.append({"id": str(raw.get("id", raw.get("job_id", ""))),
                     "name": str(raw.get("name", raw.get("title", "Unnamed job"))),
                     "schedule": raw.get("schedule", raw.get("cron", "")),
                     "enabled": bool(raw.get("enabled", not raw.get("paused", False))),
                     "next_run": raw.get("next_run", raw.get("nextRun")),
                     "agent": raw.get("agent", "default")})
    return {"jobs": jobs}

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
    ops = [{"t": activity_time(row.get("created_at")), "agent": row.get("agent_name"), "op": row.get("task_description"), "state": "failed" if row.get("status") == "failed" else "ok", "model": row.get("model_used")} for row in rows]
    unmatched = sum(1 for row in rows if row.get("agent_name") not in counts)
    alerts = [{"level": "info", "text": f"{unmatched} activity rows have unmatched agent names"}] if unmatched else []
    return {"crew": crew, "ops": ops, "sessions": {"totals": {"sessions": None, "messages": None, "tokens": None, "tool_calls": None, "input": None, "output": None, "cache_read": None, "reasoning": None, "cost": None}, "recent": []}, "heatmap": {"rows": [{"key": a["key"], "name": a["name"], "counts": [0] * 24, "total": 0} for a in CREW], "max": 0, "total_events": len(rows), "peak_hour": None}, "hourly": [0] * 13, "hourly_peak": None, "box": box_state(), "gateway": gateway_state(), "events": [r.get("task_description") for r in rows], "alerts": alerts, "capabilities": {"mail": {"connected": False, "count": None, "next": None, "checked_at": None, "stale": False, "reason": "not connected", "items": []}, "calendar": {"connected": False, "count": None, "next": None, "checked_at": None, "stale": False, "reason": "not connected", "items": []}}, "version": read_version()}

def json_response(handler: BaseHTTPRequestHandler, payload: object, status: int = 200, content_type: str = "application/json; charset=utf-8") -> None:
    body = (payload if isinstance(payload, str) and content_type.startswith("text/plain") else json.dumps(payload, ensure_ascii=False)).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)

class JarvisHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class RequestError(ValueError):
    def __init__(self, message: str, status: int = 400):
        super().__init__(message)
        self.status = status


def request_path(target: str) -> tuple[str, dict]:
    try:
        raw = target.encode("ascii")
    except UnicodeEncodeError as exc:
        raise RequestError("invalid request target") from exc
    if len(raw) > MAX_REQUEST_TARGET_BYTES:
        raise RequestError("request target too long", 414)
    if re.search(br"%(?![0-9A-Fa-f]{2})", raw):
        raise RequestError("invalid percent escape")
    raw_path, _, raw_query = raw.partition(b"?")
    try:
        path = unquote_to_bytes(raw_path).decode("utf-8", "strict")
        query_text = unquote_to_bytes(raw_query).decode("utf-8", "strict")
    except UnicodeError as exc:
        raise RequestError("invalid request target encoding") from exc
    if not path.startswith("/") or path.startswith("//") or "\\" in path or "\x00" in path:
        raise RequestError("invalid request path")
    if any(part in (".", "..") for part in path.split("/")):
        raise RequestError("invalid request path")
    return path, parse_qs(query_text, keep_blank_values=True)


def upload_name(name: object) -> tuple[str, str]:
    if not isinstance(name, str) or not name or name != Path(name).name:
        raise RequestError("invalid filename")
    if name in (".", "..") or name[-1] in (".", " ") or any(ord(char) < 32 for char in name):
        raise RequestError("invalid filename")
    if any(char in name for char in '<>:"/\\|?*') or ".." in name:
        raise RequestError("invalid filename")
    stem, suffix = Path(name).stem, Path(name).suffix.lower()
    if not stem or suffix not in UPLOAD_TYPES:
        raise RequestError("unsupported upload extension")
    if stem.upper() in {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)), *(f"LPT{i}" for i in range(1, 10))}:
        raise RequestError("reserved filename")
    return name, suffix


def decode_upload(data: object, suffix: str) -> bytes:
    if not isinstance(data, str):
        raise RequestError("invalid data URL")
    match = re.fullmatch(r"data:([^;,]+);base64,([A-Za-z0-9+/]*={0,2})", data)
    if not match or match.group(1).lower() != UPLOAD_TYPES[suffix]:
        raise RequestError("invalid data URL or media type")
    encoded = match.group(2)
    if len(encoded) > ((MAX_UPLOAD_BYTES + 2) // 3) * 4:
        raise RequestError("decoded upload too large", 413)
    try:
        body = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error) as exc:
        raise RequestError("invalid base64 data") from exc
    if len(body) > MAX_UPLOAD_BYTES:
        raise RequestError("decoded upload too large", 413)
    return body


class Handler(BaseHTTPRequestHandler):
    server_version = "JARVIS/0.1"
    def log_message(self, fmt, *args):
        return
    def handle(self):
        try:
            super().handle()
        except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            self.close_connection = True
    def _target(self):
        return request_path(self.path)
    def _body(self) -> bytes:
        if self.headers.get("Transfer-Encoding") is not None:
            raise RequestError("transfer encoding is not supported")
        lengths = self.headers.get_all("Content-Length", [])
        if len(lengths) != 1 or not re.fullmatch(r"[0-9]+", lengths[0]):
            raise RequestError("one valid Content-Length is required")
        length = int(lengths[0])
        if length <= 0:
            raise RequestError("request body is required")
        if length > MAX_REQUEST_BYTES:
            raise RequestError("request body too large", 413)
        body = self.rfile.read(length)
        if len(body) != length:
            raise RequestError("incomplete request body")
        return body
    def _request_error(self, exc: RequestError):
        result = json_response(self, {"ok": False, "error": str(exc)}, exc.status)
        self.close_connection = True
        return result
    def do_GET(self):
        try:
            path, query = self._target()
        except RequestError as exc:
            return self._request_error(exc)
        if path == "/events":
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.send_header("Cache-Control", "no-store"); self.send_header("Connection", "keep-alive"); self.send_header("X-Accel-Buffering", "no"); self.end_headers()
            try:
                self.wfile.write(b"retry: 5000\n\n"); self.wfile.flush()
                while True:
                    data = json.dumps(state(), ensure_ascii=False).encode("utf-8")
                    self.wfile.write(b"event: state\ndata: " + data + b"\n\n"); self.wfile.flush(); time.sleep(3)
            except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError): return
        if path == "/api/state": return json_response(self, state())
        if path == "/api/models/runtime": return json_response(self, model_runtime_status())
        if path == "/api/services": return json_response(self, {"services": list(service_status().values())})
        if path == "/api/audio/devices": return json_response(self, audio_devices())
        if path == "/api/content": return json_response(self, shelves())
        if path == "/api/owner":
            user = HERMES / "memories" / "USER.md"; first = ""
            if user.exists(): first = user.read_text(encoding="utf-8", errors="replace").split()[0] if user.read_text(encoding="utf-8", errors="replace").split() else ""
            return json_response(self, {"name": first if first.isalpha() else ""})
        if path == "/api/models": return json_response(self, {"agents": [{**a, "model": None, "provider": "custom"} for a in CREW], "providers": [{"slug": "custom", "name": "Custom", "models": ["gpt-oss:20b"], "total": 1}], "loading": False, "error": None})
        if path == "/api/chat/history":
            agent = query.get("agent", ["default"])[0]
            if not valid_agent(agent):
                return json_response(self, {"error": "unknown agent"}, 400)
            return json_response(self, {"session": None, "telegram": agent == "default", "messages": []})
        if path == "/api/cron": return json_response(self, cron_payload())
        if path == "/api/voice/config": return json_response(self, read_voice_config())
        if path == "/docs.md": return self.send_file(ROOT / "docs.md", "text/markdown; charset=utf-8")
        if path in ("/", "/template", "/styles.css", "/script.js", "/field.js", "/conversation.js", "/favicon.svg", "/upload"):
            file = {"/": "index.html", "/template": "jarvis-dashboard-template.html", "/upload": "upload.html"}.get(path, path.lstrip("/"))
            return self.send_file(ROOT / file)
        if Path(path).suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".svg"} and path.count("/") == 1:
            return self.send_file(ROOT / path.lstrip("/"))
        if path == "/api/content/read":
            agent, file = query.get("agent", [""])[0], query.get("file", [""])[0]
            if not valid_agent(agent) or not valid_content_name(file): return json_response(self, {"error": "not found"}, 404)
            target = ROOT / "content" / agent / file
            if not target.is_file(): return json_response(self, {"error": "not found"}, 404)
            text = target.read_text(encoding="utf-8", errors="replace")
            return json_response(self, {**content_metadata(agent, target), "text": text})
        return json_response(self, {"error": "not found"}, 404)
    def send_file(self, path: Path, content_type: str | None = None):
        if not path.is_file(): return json_response(self, {"error": "not found"}, 404)
        body = path.read_bytes()
        suffix = path.suffix.lower()
        explicit_types = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8", ".js": "application/javascript; charset=utf-8", ".md": "text/markdown; charset=utf-8", ".svg": "image/svg+xml"}
        self.send_response(200)
        self.send_header("Content-Type", content_type or explicit_types.get(suffix) or mimetypes.guess_type(path.name)[0] or "application/octet-stream")
        if suffix in {".png", ".jpg", ".jpeg", ".webp", ".svg"}:
            self.send_header("Cache-Control", f"public, max-age={IMAGE_MAX_AGE_SECONDS}")
            self.send_header("ETag", f'"{hashlib.sha256(body).hexdigest()}"')
        else:
            self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_POST(self):
        try:
            path, query = self._target()
            raw = self._body()
        except RequestError as exc:
            return self._request_error(exc)
        if path == "/api/upload":
            try:
                if self.headers.get_content_type() != "application/json":
                    raise RequestError("Content-Type must be application/json")
                payload = json.loads(raw.decode("utf-8", "strict"))
                if not isinstance(payload, dict) or set(payload) != {"name", "data"}:
                    raise RequestError("upload requires only name and data")
                name, suffix = upload_name(payload["name"])
                body = decode_upload(payload["data"], suffix)
                target = ROOT / name
                with UPLOAD_LOCK:
                    temporary = None
                    try:
                        with tempfile.NamedTemporaryFile(dir=ROOT, prefix=".upload-", delete=False) as stream:
                            temporary = Path(stream.name)
                            stream.write(body)
                            stream.flush()
                            os.fsync(stream.fileno())
                        os.replace(temporary, target)
                    finally:
                        if temporary is not None and temporary.exists():
                            temporary.unlink()
                return json_response(self, {"ok": True, "filename": name, "path": str(target), "size": len(body)})
            except RequestError as exc:
                return self._request_error(exc)
            except (KeyError, ValueError, UnicodeError, json.JSONDecodeError) as exc:
                return self._request_error(RequestError("invalid JSON upload"))
            except OSError:
                return self._request_error(RequestError("upload could not be saved", 500))
        if path == "/api/chat/send":
            try:
                payload = json.loads(raw); agent, text = payload["agent"], payload["text"]
                if not valid_agent(agent) or not isinstance(text, str) or not text.strip() or len(text) > 10000:
                    raise ValueError("invalid chat request")
                cmd = ["hermes"] + ([] if agent == "default" else ["-p", agent]) + ["-z", text]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=300, env={**os.environ, "HERMES_HOME": str(HERMES)})
                return json_response(self, result.stdout.strip() if result.returncode == 0 else result.stderr.strip(), 200 if result.returncode == 0 else 502, "text/plain; charset=utf-8")
            except Exception as exc: return json_response(self, {"error": str(exc)}, 502)
        if path.startswith("/api/services/") and path.endswith("/action"):
            service = path[len("/api/services/"):-len("/action")].strip("/")
            try:
                payload = json.loads(raw.decode("utf-8", "strict"))
                action = payload.get("action") if isinstance(payload, dict) else None
                return json_response(self, service_action(service, action))
            except RequestError as exc:
                return json_response(self, {"ok": False, "error": str(exc)}, exc.status)
            except (ValueError, TypeError, json.JSONDecodeError) as exc:
                return json_response(self, {"ok": False, "error": "invalid service action"}, 400)
        if path == "/api/models/set":
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
        if path == "/api/cron/action":
            action = query.get("action", [""])[0]; job_id = query.get("id", [""])[0]
            commands = {"run": "run", "pause": "pause", "resume": "resume", "delete": "remove"}
            if action not in commands or not job_id: return json_response(self, {"ok": False, "error": "invalid action"}, 400)
            result = subprocess.run(["hermes", "cron", commands[action], job_id], capture_output=True, text=True, env={**os.environ, "HERMES_HOME": str(HERMES)})
            return json_response(self, {"ok": result.returncode == 0, "error": result.stderr.strip() if result.returncode else None}, 200 if result.returncode == 0 else 502)
        if path == "/api/content/delete":
            agent, file = query.get("agent", [""])[0], query.get("file", [""])[0]
            if not valid_agent(agent) or not valid_content_name(file): return json_response(self, {"error": "not found"}, 404)
            target = ROOT / "content" / agent / file
            if not target.is_file(): return json_response(self, {"error": "not found"}, 404)
            target.unlink(); return json_response(self, {"ok": True})
        if path == "/api/voice/config":
            try:
                value = json.loads(raw); scenario = int(value["scenario"])
                if scenario not in (1, 2, 3): raise ValueError("scenario must be 1, 2, or 3")
                VOICE_CONFIG.write_text(json.dumps({**read_voice_config(), "scenario": scenario}), encoding="utf-8")
                return json_response(self, read_voice_config())
            except Exception as exc: return json_response(self, {"error": str(exc)}, 400)
        if path == "/api/voice":
            try:
                payload = json.loads(raw); request = urllib.request.Request("http://127.0.0.1:8767/say?voice=bm_daniel", data=str(payload.get("text", "")).encode(), method="POST")
                with urllib.request.urlopen(request, timeout=60) as response: audio = response.read()
                self.send_response(200); self.send_header("Content-Type", "audio/wav"); self.send_header("X-Jarvis-Voice-Engine", "kokoro"); self.send_header("Content-Length", str(len(audio))); self.end_headers(); self.wfile.write(audio); return
            except Exception as exc: return json_response(self, {"error": str(exc)}, 502)
        if path == "/api/greeting": return json_response(self, {"error": "greeting cache is not generated"}, 404)
        if path == "/api/transcribe":
            if not raw:
                return json_response(self, {"error": "audio body is required"}, 400)
            content_type = self.headers.get("Content-Type", "")
            if not content_type.startswith("audio/"):
                return json_response(self, {"error": "Content-Type must be audio/*"}, 400)
            try:
                return json_response(self, {"text": transcribe_audio(raw, content_type)})
            except Exception as exc:
                return json_response(self, {"error": str(exc)}, 502)
        return json_response(self, {"error": "not found"}, 404)

if __name__ == "__main__":
    ROOT.mkdir(parents=True, exist_ok=True)
    JarvisHTTPServer((HOST, PORT), Handler).serve_forever()

