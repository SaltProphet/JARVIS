import http.client
import importlib.util
import json
import tempfile
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "jarvis_services_server", ROOT / "installer" / "dashboard" / "server.py"
)
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


@contextmanager
def running_server(project: Path):
    original = (server.ROOT, server.VERSION_PATH, server.HERMES, server.LOG_DB)
    server.ROOT = project
    server.VERSION_PATH = project / "version.txt"
    server.HERMES = project / "hermes"
    server.LOG_DB = project / "agent-logs.db"
    httpd = server.JarvisHTTPServer((server.HOST, 0), server.Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield httpd.server_address[1]
    finally:
        httpd.shutdown()
        httpd.server_close()
        thread.join(timeout=2)
        server.ROOT, server.VERSION_PATH, server.HERMES, server.LOG_DB = original


def get_json(port: int, path: str):
    connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
    connection.request("GET", path)
    response = connection.getresponse()
    payload = json.loads(response.read())
    connection.close()
    return response.status, payload


def post_json(port: int, path: str, payload: dict):
    connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
    connection.request("POST", path, body=json.dumps(payload), headers={"Content-Type": "application/json"})
    response = connection.getresponse()
    result = response.status, json.loads(response.read())
    connection.close()
    return result


class DashboardServiceTests(unittest.TestCase):
    def test_services_endpoint_reports_actionable_runtime_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with running_server(root) as port:
                with mock.patch.object(server, "service_status", return_value={
                    "dashboard": {"id": "dashboard", "label": "Dashboard", "state": "available", "actions": []},
                    "stt": {"id": "stt", "label": "Whisper", "state": "available", "actions": []},
                    "hermes": {"id": "hermes", "label": "Hermes", "state": "error", "actions": ["start", "restart"]},
                    "kokoro": {"id": "kokoro", "label": "Kokoro", "state": "available", "actions": ["stop", "restart"]},
                }):
                    status, payload = get_json(port, "/api/services")

        self.assertEqual(status, 200)
        self.assertEqual([item["id"] for item in payload["services"]], ["dashboard", "stt", "hermes", "kokoro"])
        self.assertEqual(payload["services"][2]["actions"], ["start", "restart"])

    def test_audio_devices_endpoint_preserves_default_and_device_lists(self):
        with tempfile.TemporaryDirectory() as directory:
            with running_server(Path(directory)) as port:
                with mock.patch.object(server, "audio_devices", return_value={
                    "inputs": [{"id": "mic-1", "name": "Microphone"}],
                    "outputs": [{"id": "out-1", "name": "Speakers"}],
                    "default_input": "mic-1",
                    "default_output": "out-1",
                    "error": None,
                }):
                    status, payload = get_json(port, "/api/audio/devices")

        self.assertEqual(status, 200)
        self.assertEqual(payload["default_input"], "mic-1")
        self.assertEqual(payload["outputs"][0]["name"], "Speakers")

    def test_service_action_rejects_unknown_service(self):
        with tempfile.TemporaryDirectory() as directory:
            with running_server(Path(directory)) as port:
                status, payload = post_json(port, "/api/services/nope/action", {"action": "start"})

        self.assertEqual(status, 404)
        self.assertFalse(payload["ok"])


if __name__ == "__main__":
    unittest.main()
