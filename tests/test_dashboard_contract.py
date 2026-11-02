import importlib.util
import os
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("jarvis_server", ROOT / "installer" / "dashboard" / "server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class DashboardContractTests(unittest.TestCase):
    def test_state_has_fixed_top_level_contract(self):
        payload = server.state()
        required = {"crew", "ops", "sessions", "heatmap", "hourly", "hourly_peak", "box", "gateway", "events", "alerts", "capabilities", "version"}
        self.assertTrue(required.issubset(payload))
        self.assertEqual([agent["key"] for agent in payload["crew"]], ["default", "dev", "research", "assistant"])

    def test_cron_and_voice_helpers_are_safe_when_empty(self):
        self.assertEqual(server.read_cron_jobs(), [])
        self.assertEqual(server.read_voice_config()["scenario"], 1)


if __name__ == "__main__":
    unittest.main()
