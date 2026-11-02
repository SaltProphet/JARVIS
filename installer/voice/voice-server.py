"""Loopback Kokoro voice service. The model is optional until installed."""
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
        if MODEL.is_file() and VOICES.is_file():
            from kokoro_onnx import Kokoro
            engine = Kokoro(str(MODEL), str(VOICES))
    except Exception as exc:
        error = str(exc)
    finally:
        loading = False

def wav_silence(seconds=0.25):
    frames = int(24000 * seconds)
    data = b"\x00\x00" * frames
    import io
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(data)
    return out.getvalue()

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
        text = self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode("utf-8", "replace")
        CACHE.mkdir(exist_ok=True); key = hashlib.sha256(f"{voice}|{speed}|{text}".encode()).hexdigest(); path = CACHE / f"{key}.wav"
        if not path.exists():
            with lock:
                if not path.exists():
                    if engine is not None:
                        samples, sample_rate = engine.create(text, voice=voice, speed=float(speed), lang="en-gb")
                        import soundfile as sf
                        sf.write(path, samples, 24000, format="WAV", subtype="PCM_16")
                    else: path.write_bytes(wav_silence())
        body = path.read_bytes(); self.send_response(200); self.send_header("Content-Type", "audio/wav"); self.send_header("Content-Length", str(len(body))); self.send_header("X-Jarvis-Voice-Engine", "kokoro" if engine else "placeholder"); self.end_headers(); self.wfile.write(body)

if __name__ == "__main__":
    threading.Thread(target=load_model, daemon=True).start()
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
