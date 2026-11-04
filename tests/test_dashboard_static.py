import http.client
import importlib.util
import re
import shutil
import tempfile
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DASHBOARD = ROOT / "installer" / "dashboard"
SPEC = importlib.util.spec_from_file_location("jarvis_static_server", DASHBOARD / "server.py")
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


@contextmanager
def running_server(project: Path):
    original = (server.ROOT, server.VERSION_PATH)
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
        server.ROOT, server.VERSION_PATH = original


def get(port: int, path: str):
    connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
    connection.request("GET", path)
    response = connection.getresponse()
    result = response.status, dict(response.getheaders()), response.read()
    connection.close()
    return result


class DashboardStaticTests(unittest.TestCase):
    def test_template_marker_is_executable_only_on_template_and_badge_only_on_index(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ("index.html", "jarvis-dashboard-template.html", "styles.css", "script.js", "conversation.js", "favicon.svg", "upload.html"):
                shutil.copyfile(DASHBOARD / name, project / name)
            with running_server(project) as port:
                _, _, index = get(port, "/")
                _, _, template = get(port, "/template")

            self.assertNotIn(b"__TEMPLATE__", index)
            self.assertIn(b"data-version", index)
            self.assertIn(b"| VERSION <span data-version>", index)
            self.assertIn(b"conversation.js", index)
            self.assertIn(b'id="conversation-overlay"', index)
            self.assertIn(b'id="conversation-transcript"', index)
            self.assertIn(b"window.__TEMPLATE__=true", template)
            self.assertNotIn(b"data-version", template)
            self.assertIn(b"<script", template)
            for view in (b"home", b"agents", b"comms", b"schedule", b"library", b"docs", b"control"):
                self.assertIn(b'data-view="' + view + b'"', template)
                self.assertIn(b'id="' + view + b'"', template)

    def test_static_mime_cache_and_image_etag_contracts_are_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            for name in ("index.html", "jarvis-dashboard-template.html", "styles.css", "script.js", "conversation.js", "favicon.svg", "upload.html"):
                shutil.copyfile(DASHBOARD / name, project / name)
            project.joinpath("photo.png").write_bytes(b"png fixture")
            with running_server(project) as port:
                for path, mime in (("/", "text/html; charset=utf-8"), ("/template", "text/html; charset=utf-8"),
                                   ("/styles.css", "text/css; charset=utf-8"),
                                   ("/script.js", "application/javascript; charset=utf-8")):
                    with self.subTest(path=path):
                        status, headers, _ = get(port, path)
                        self.assertEqual(status, 200)
                        self.assertEqual(headers["Content-Type"], mime)
                        self.assertEqual(headers["Cache-Control"], "no-store")
                status, headers, _ = get(port, "/photo.png")
                self.assertEqual(status, 200)
                self.assertEqual(headers["Content-Type"], "image/png")
                self.assertIn("max-age=", headers["Cache-Control"])
                self.assertTrue(headers["ETag"].startswith('"'))

    def test_encoded_traversal_malformed_escape_and_oversized_target_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            project.joinpath("index.html").write_text("index", encoding="ascii")
            with running_server(project) as port:
                for path in ("/%2e%2e/index.html", "/%ZZ", "/a%5cb", "/%2foutside"):
                    with self.subTest(path=path):
                        status, _, _ = get(port, path)
                        self.assertEqual(status, 400)
                status, _, _ = get(port, "/" + "a" * server.MAX_REQUEST_TARGET_BYTES)
                self.assertEqual(status, 414)

    def test_conversation_surfaces_audio_and_interim_transcription_state(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")
        styles = (DASHBOARD / "styles.css").read_text(encoding="utf-8")

        self.assertIn("recognition.onaudiostart", script)
        self.assertIn("recognition.onspeechstart", script)
        self.assertIn("recognition.onerror", script)
        self.assertIn("interimTranscript", script)
        self.assertIn("conversation.interrupt(); renderTranscript(); setPhase('READY');", script)
        self.assertIn(".orb.is-listening", styles)

    def test_space_hold_ignores_key_repeat_and_suppresses_keyboard_click(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")

        self.assertIn("event.repeat", script)
        self.assertIn("__jarvisSpaceHeld", script)
        self.assertIn("__jarvisSuppressSpaceClick", script)

    def test_conversation_has_stable_modes_and_cancellable_reply(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")
        page = (DASHBOARD / "index.html").read_text(encoding="utf-8")

        self.assertIn("toggleTalkMode", script)
        self.assertIn("Talk mode", page)
        self.assertIn("AbortController", script)
        self.assertIn("cancel-reply", page)
        self.assertIn("recognition.start()", script)
        self.assertIn("RECONNECTING", script)

    def test_conversation_has_local_media_recorder_fallback(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")

        self.assertIn("navigator.mediaDevices.getUserMedia", script)
        self.assertIn("MediaRecorder", script)
        self.assertIn("/api/transcribe", script)

    def test_conversation_speaks_agent_reply_through_local_voice_api(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")

        self.assertIn("/api/voice", script)
        self.assertIn("new Audio", script)

    def test_talk_control_is_a_single_toggle_and_space_stops_explicitly(self):
        script = (DASHBOARD / "script.js").read_text(encoding="utf-8")
        page = (DASHBOARD / "index.html").read_text(encoding="utf-8")

        self.assertIn("Toggle: Push to Talk", page)
        self.assertIn("toggleTalkMode", script)
        self.assertIn("if (conversation?.phase === 'listening') stopSpeechTurn();", script)
        self.assertRegex(script, re.compile(r"document\.addEventListener\('keyup'.*?if \(conversation\?\.phase === 'listening'\) stopSpeechTurn\(\);", re.S))


if __name__ == "__main__":
    unittest.main()
