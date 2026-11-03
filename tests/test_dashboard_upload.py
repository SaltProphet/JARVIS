import base64
import http.client
import importlib.util
import json
import tempfile
import threading
import unittest
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "jarvis_upload_server", ROOT / "installer" / "dashboard" / "server.py"
)
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


def upload_body(name: str, content: bytes, mime: str = "text/html") -> bytes:
    encoded = base64.b64encode(content).decode("ascii")
    return json.dumps({"name": name, "data": f"data:{mime};base64,{encoded}"}).encode()


def request(port: int, body: bytes, headers=None):
    connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
    connection.request(
        "POST", "/api/upload", body=body,
        headers=headers or {"Content-Type": "application/json"},
    )
    response = connection.getresponse()
    result = response.status, json.loads(response.read())
    connection.close()
    return result


class DashboardUploadTests(unittest.TestCase):
    def test_accepts_decoded_limit_and_rejects_one_byte_more_without_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            target = project / "limit.svg"
            with running_server(project) as port:
                status, payload = request(
                    port, upload_body(target.name, b"x" * server.MAX_UPLOAD_BYTES, "image/svg+xml")
                )
                self.assertEqual(status, 200)
                self.assertEqual(payload["size"], server.MAX_UPLOAD_BYTES)
                self.assertEqual(target.stat().st_size, server.MAX_UPLOAD_BYTES)

                status, payload = request(
                    port, upload_body(target.name, b"y" * (server.MAX_UPLOAD_BYTES + 1), "image/svg+xml")
                )
                self.assertEqual(status, 413)
                self.assertFalse(payload["ok"])
                self.assertEqual(target.read_bytes(), b"x" * server.MAX_UPLOAD_BYTES)

    def test_request_limit_and_malformed_body_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            with running_server(Path(directory)) as port:
                connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
                connection.putrequest("POST", "/api/upload")
                connection.putheader("Content-Type", "application/json")
                connection.putheader("Content-Length", str(server.MAX_REQUEST_BYTES + 1))
                connection.endheaders()
                response = connection.getresponse()
                self.assertEqual(response.status, 413)
                response.read()
                connection.close()

                for body, content_type in (
                    (b"{}", "text/plain"),
                    (b'{"name":"x.svg","data":"data:image/svg+xml;base64,%%%"}', "application/json"),
                    (b'{"name":"x.svg","data":"not-a-data-url"}', "application/json"),
                ):
                    with self.subTest(body=body, content_type=content_type):
                        status, payload = request(port, body, {"Content-Type": content_type})
                        self.assertEqual(status, 400)
                        self.assertFalse(payload["ok"])

    def test_rejects_filename_escape_matrix_and_mime_extension_mismatch(self):
        bad_names = (
            "../x.html", "..\\x.html", "/x.html", "C:\\x.html", "\\\\host\\x.html",
            ".html", "x.html.", "x.exe", "folder/x.svg", "folder\\x.svg", "x\x00.svg",
        )
        with tempfile.TemporaryDirectory() as directory:
            project = Path(directory)
            with running_server(project) as port:
                for name in bad_names:
                    with self.subTest(name=name):
                        status, payload = request(port, upload_body(name, b"safe"))
                        self.assertEqual(status, 400)
                        self.assertFalse(payload["ok"])
                status, payload = request(port, upload_body("x.png", b"not-png", "text/html"))
                self.assertEqual(status, 400)
                self.assertFalse(payload["ok"])
            self.assertEqual(list(project.iterdir()), [])

    def test_rejects_transfer_encoding_and_ambiguous_content_length(self):
        with tempfile.TemporaryDirectory() as directory:
            with running_server(Path(directory)) as port:
                connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
                connection.putrequest("POST", "/api/upload")
                connection.putheader("Content-Type", "application/json")
                connection.putheader("Content-Length", "2")
                connection.putheader("Content-Length", "2")
                connection.endheaders(b"{}")
                response = connection.getresponse()
                self.assertEqual(response.status, 400)
                response.read()
                connection.close()

                connection = http.client.HTTPConnection(server.HOST, port, timeout=5)
                connection.putrequest("POST", "/api/upload")
                connection.putheader("Content-Type", "application/json")
                connection.putheader("Transfer-Encoding", "chunked")
                connection.endheaders(b"2\r\n{}\r\n0\r\n\r\n")
                response = connection.getresponse()
                self.assertEqual(response.status, 400)
                response.read()
                connection.close()


if __name__ == "__main__":
    unittest.main()
