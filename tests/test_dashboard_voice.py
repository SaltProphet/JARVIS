import http.client
import importlib.util
import json
import os
import sys
import tempfile
import threading
import types
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "jarvis_voice_server", ROOT / "installer" / "dashboard" / "server.py"
)
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


@contextmanager
def running_server(project: Path):
    original = (server.ROOT, server.VERSION_PATH, getattr(server, "transcribe_audio", None))
    server.ROOT = project
    server.VERSION_PATH = project / "version.txt"
    httpd = server.JarvisHTTPServer((server.HOST, 0), server.Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield httpd.server_address[1]
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=2)
        server.ROOT, server.VERSION_PATH = original[:2]
        if original[2] is None:
            if hasattr(server, "transcribe_audio"):
                delattr(server, "transcribe_audio")
        else:
            server.transcribe_audio = original[2]


def transcribe_request(port: int, body: bytes, content_type: str = "audio/wav"):
    connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
    connection.request("POST", "/api/transcribe", body=body, headers={"Content-Type": content_type})
    response = connection.getresponse()
    result = response.status, json.loads(response.read())
    connection.close()
    return result


class DashboardVoiceTests(unittest.TestCase):
    def test_transcribe_returns_local_transcript_for_audio_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            server.transcribe_audio = lambda body, content_type: "local transcript"
            with running_server(Path(directory)) as port:
                status, payload = transcribe_request(port, b"RIFF audio")

        self.assertEqual(status, 200)
        self.assertEqual(payload, {"text": "local transcript"})

    def test_transcribe_rejects_empty_audio(self):
        with tempfile.TemporaryDirectory() as directory:
            with running_server(Path(directory)) as port:
                status, payload = transcribe_request(port, b"")

        self.assertEqual(status, 400)
        self.assertIn("error", payload)

    def test_transcribe_falls_back_to_cpu_when_cuda_runtime_is_unavailable(self):
        calls = []

        class FakeModel:
            def __init__(self, model_path, device, compute_type):
                calls.append((model_path, device, compute_type))
                if device == "cuda":
                    raise RuntimeError("cublas64_12.dll is missing")

            def transcribe(self, path, language, vad_filter):
                return ([types.SimpleNamespace(text="cpu fallback")], None)

        fake_module = types.SimpleNamespace(WhisperModel=FakeModel)
        original_model = server.STT_MODEL
        server.STT_MODEL = None
        try:
            with mock.patch.dict(os.environ, {"JARVIS_STT_DEVICE": "cuda", "JARVIS_STT_COMPUTE_TYPE": "float16"}), mock.patch.dict(sys.modules, {"faster_whisper": fake_module}):
                self.assertEqual(server.transcribe_audio(b"RIFF audio", "audio/wav"), "cpu fallback")
        finally:
            server.STT_MODEL = original_model

        self.assertEqual(calls[0][1:], ("cuda", "float16"))
        self.assertEqual(calls[1][1:], ("cpu", "int8"))

    def test_transcribe_retries_inference_on_cpu_when_cuda_fails_during_transcription(self):
        calls = []

        class FakeModel:
            def __init__(self, model_path, device, compute_type):
                self.device = device
                calls.append((device, compute_type))

            def transcribe(self, path, language, vad_filter):
                if self.device == "cuda":
                    raise RuntimeError("cublas64_12.dll is not found")
                return ([types.SimpleNamespace(text="inference fallback")], None)

        fake_module = types.SimpleNamespace(WhisperModel=FakeModel)
        original_model = server.STT_MODEL
        server.STT_MODEL = None
        try:
            with mock.patch.dict(os.environ, {"JARVIS_STT_DEVICE": "cuda", "JARVIS_STT_COMPUTE_TYPE": "float16"}), mock.patch.dict(sys.modules, {"faster_whisper": fake_module}):
                self.assertEqual(server.transcribe_audio(b"RIFF audio", "audio/wav"), "inference fallback")
        finally:
            server.STT_MODEL = original_model

        self.assertEqual(calls, [("cuda", "float16"), ("cpu", "int8")])


if __name__ == "__main__":
    unittest.main()
