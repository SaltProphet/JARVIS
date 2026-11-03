import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("jarvis_data_server", ROOT / "installer" / "dashboard" / "server.py")
server = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(server)


class DashboardDataContractTests(unittest.TestCase):
    def test_content_names_are_markdown_files_in_known_agent_shelves(self):
        self.assertTrue(server.valid_agent("research"))
        self.assertFalse(server.valid_agent("../../research"))
        self.assertTrue(server.valid_content_name("2026-11-03_brief.md"))
        for name in ("../brief.md", "..\\brief.md", "brief.txt", "C:\\brief.md", "brief.md\\x"):
            self.assertFalse(server.valid_content_name(name), name)

    def test_content_metadata_exposes_author_and_date_without_body(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "2026-11-03_brief.md"
            path.write_text("# A brief\n\nBody", encoding="utf-8")
            metadata = server.content_metadata("research", path)
        self.assertEqual(metadata["title"], "A brief")
        self.assertEqual(metadata["author"], "RESEARCH")
        self.assertEqual(metadata["date"], "2026-11-03")
        self.assertNotIn("text", metadata)

    def test_cron_payload_normalizes_jobs_and_ignores_non_objects(self):
        original = server.read_cron_jobs
        try:
            server.read_cron_jobs = lambda: [{"job_id": 7, "title": "Morning", "paused": True}, "bad"]
            self.assertEqual(server.cron_payload(), {"jobs": [{
                "id": "7", "name": "Morning", "schedule": "", "enabled": False,
                "next_run": None, "agent": "default"
            }]})
        finally:
            server.read_cron_jobs = original


if __name__ == "__main__":
    unittest.main()
