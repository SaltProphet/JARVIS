import importlib.util
import http.client
import json
import os
import sqlite3
import tempfile
import threading
import time
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "jarvis_state_server", ROOT / "installer" / "dashboard" / "server.py"
)
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


@contextmanager
def server_paths(project: Path, hermes: Path):
    original = (server.ROOT, server.HERMES, server.LOG_DB, server.VERSION_PATH)
    server.ROOT = project
    server.HERMES = hermes
    server.LOG_DB = project / "agent-logs.db"
    server.VERSION_PATH = project / "version.txt"
    try:
        yield
    finally:
        server.ROOT, server.HERMES, server.LOG_DB, server.VERSION_PATH = original


class DashboardStateTests(unittest.TestCase):
    def test_state_reads_real_activity_gateway_and_persisted_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, hermes = root / "project", root / "hermes"
            project.mkdir()
            hermes.mkdir()
            project.joinpath("version.txt").write_text("v0.1\n", encoding="ascii")
            hermes.joinpath("gateway_state.json").write_text(
                json.dumps({"pid": 0, "platforms": ["telegram"]}), encoding="utf-8"
            )
            database = sqlite3.connect(project / "agent-logs.db")
            try:
                database.execute(
                    "CREATE TABLE agent_logs (id INTEGER PRIMARY KEY, agent_name TEXT, "
                    "task_description TEXT, model_used TEXT, status TEXT, created_at TEXT)"
                )
                database.execute(
                    "INSERT INTO agent_logs VALUES (1, 'DEV', 'Built shell', 'model-a', "
                    "'completed', '2026-11-03T12:34:56+00:00')"
                )
                database.commit()
            finally:
                database.close()
            with server_paths(project, hermes):
                payload = server.state()

            self.assertEqual(payload["version"], "v0.1")
            self.assertEqual(payload["ops"][0], {
                "t": "12:34:56", "agent": "DEV", "op": "Built shell",
                "state": "ok", "model": "model-a",
            })
            dev = next(agent for agent in payload["crew"] if agent["key"] == "dev")
            self.assertEqual(dev["tasks"], 1)
            self.assertEqual(dev["mix"]["completed"], 1)
            self.assertEqual(payload["gateway"]["state"], "stopped")
            self.assertEqual(payload["gateway"]["platforms"], ["telegram"])
            self.assertTrue(payload["box"]["hostname"])
            self.assertIsInstance(payload["box"]["disk_pct"], (int, float))

    def test_missing_malformed_and_locked_sources_keep_contract_available(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project, hermes = root / "project", root / "hermes"
            project.mkdir()
            hermes.mkdir()
            hermes.joinpath("gateway_state.json").write_text("not-json", encoding="utf-8")
            lock = sqlite3.connect(project / "agent-logs.db", timeout=0)
            lock.execute("CREATE TABLE agent_logs (id INTEGER PRIMARY KEY)")
            lock.commit()
            lock.execute("BEGIN EXCLUSIVE")
            try:
                with server_paths(project, hermes):
                    payload = server.state()
            finally:
                lock.rollback()
                lock.close()

            self.assertEqual(payload["ops"], [])
            self.assertEqual(payload["gateway"], {
                "state": "stopped", "pid": None, "platforms": [],
            })
            self.assertEqual(payload["version"], "v0.1")
            self.assertEqual(
                set(payload),
                {"crew", "ops", "sessions", "heatmap", "hourly", "hourly_peak",
                 "box", "gateway", "events", "alerts", "capabilities", "version"},
            )

    @unittest.skipUnless(os.name == "nt", "Windows handle-count contract")
    def test_two_hundred_state_requests_do_not_leak_process_handles(self):
        import ctypes

        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            project.joinpath("version.txt").write_text("v0.1\n", encoding="ascii")
            original = (server.ROOT, server.HERMES, server.LOG_DB, server.VERSION_PATH)
            server.ROOT = project
            server.HERMES = project / "missing-hermes"
            server.LOG_DB = project / "missing.db"
            server.VERSION_PATH = project / "version.txt"
            httpd = server.JarvisHTTPServer((server.HOST, 0), server.Handler)
            thread = threading.Thread(target=httpd.serve_forever, daemon=True)
            thread.start()
            kernel32 = ctypes.windll.kernel32
            kernel32.GetCurrentProcess.restype = ctypes.c_void_p
            kernel32.GetProcessHandleCount.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_ulong)]
            kernel32.GetProcessHandleCount.restype = ctypes.c_int

            def handles():
                count = ctypes.c_ulong()
                self.assertTrue(kernel32.GetProcessHandleCount(kernel32.GetCurrentProcess(), ctypes.byref(count)))
                return count.value

            try:
                before = handles()
                for _ in range(200):
                    connection = http.client.HTTPConnection(server.HOST, httpd.server_address[1], timeout=3)
                    connection.request("GET", "/api/state")
                    response = connection.getresponse()
                    self.assertEqual(response.status, 200)
                    response.read()
                    connection.close()
                time.sleep(0.2)
                after = handles()
                self.assertLessEqual(after, before + 4)
            finally:
                httpd.shutdown()
                httpd.server_close()
                thread.join(timeout=2)
                server.ROOT, server.HERMES, server.LOG_DB, server.VERSION_PATH = original


if __name__ == "__main__":
    unittest.main()
