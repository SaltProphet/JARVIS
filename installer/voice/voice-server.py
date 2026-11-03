"""Loopback Kokoro voice service."""
from __future__ import annotations
import hashlib, json, os, threading, wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HOST, PORT = "127.0.0.1", int(os.environ.get("JARVIS_VOICE_PORT", "8767"))
ROOT = Path(os.environ.get("JARVIS_VOICE_ROOT", Path(__file__).resolve().parent)).resolve()
MODEL = ROOT / "kokoro-v1.0.onnx"
VOICES = ROOT / "voices-v1.0.bin"
CACHE = ROOT / "audio-cache"
KNOWN = ["bm_daniel", "bm_fable", "bm_george", "bf_alice", "bm_lewis"]
lock = threading.Lock()
engine = None
error = None
loading = True

def load_model():
    global engine, error, loading
    try:
        if not MODEL.is_file() or not VOICES.is_file():
            raise FileNotFoundError("Kokoro model files are missing")
        from kokoro_onnx import Kokoro
        engine = Kokoro(str(MODEL), str(VOICES))
    except Exception as exc:
        error = str(exc)
    finally:
        loading = False

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def send_json(self, payload, code=200):
        body = json.dumps(payload).encode(); self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        if urlparse(self.path).path == "/health": return self.send_json({"ok": not loading and error is None, "loading": loading, "error": error, "voices": KNOWN, "default": "bm_daniel"})
        self.send_json({"error": "not found"}, 404)
    def do_POST(self):
        parsed = urlparse(self.path)
        if parsed.path != "/say": return self.send_json({"error": "not found"}, 404)
        query = parse_qs(parsed.query); voice = query.get("voice", ["bm_daniel"])[0]; speed = query.get("speed", ["1.0"])[0]
        if voice not in KNOWN: return self.send_json({"error": "unknown voice"}, 400)
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.send_json({"error": "invalid content length"}, 400)
        if length <= 0 or length > 10000:
            return self.send_json({"error": "text body must be 1-10000 bytes"}, 400)
        text = self.rfile.read(length).decode("utf-8", "replace").strip()
        if not text:
            return self.send_json({"error": "text is required"}, 400)
        try:
            speed_value = float(speed)
        except ValueError:
            return self.send_json({"error": "invalid speed"}, 400)
        if not 0.5 <= speed_value <= 2.0:
            return self.send_json({"error": "speed must be between 0.5 and 2.0"}, 400)
        if loading or engine is None:
            return self.send_json({"error": error or "Kokoro is not ready"}, 503)
        CACHE.mkdir(exist_ok=True); key = hashlib.sha256(f"{voice}|{speed}|{text}".encode()).hexdigest(); path = CACHE / f"{key}.wav"
        if not path.exists():
            with lock:
                if not path.exists():
                    samples, sample_rate = engine.create(text, voice=voice, speed=speed_value, lang="en-gb")
                    import soundfile as sf
                    sf.write(path, samples, 24000, format="WAV", subtype="PCM_16")
        body = path.read_bytes(); self.send_response(200); self.send_header("Content-Type", "audio/wav"); self.send_header("Content-Length", str(len(body))); self.send_header("X-Jarvis-Voice-Engine", "kokoro"); self.end_headers(); self.wfile.write(body)

if __name__ == "__main__":
    threading.Thread(target=load_model, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
