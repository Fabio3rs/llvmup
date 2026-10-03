"""Exercise the real installer and curl against a private HTTP server."""

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import threading
import unittest


INSTALLER = Path(__file__).resolve().parents[2] / "llvm-prebuilt"
ASSET_NAME = "LLVM-20.1.8-Linux-X64.tar.xz"
VERSION = "llvmorg-20.1.8"


class PrebuiltHTTPTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w:xz") as package:
            for name in ("clang", "clang++", "padding"):
                # Keep the compressed archive above 1 MiB so integer rounding
                # cannot hide the original misleading zero-size result.
                data = os.urandom(2 * 1024 * 1024) if name == "padding" else b"#!/bin/sh\necho clang version 20.1.8\n"
                info = tarfile.TarInfo(f"LLVM-20.1.8-Linux-X64/bin/{name}")
                info.size = len(data)
                info.mode = 0o755
                package.addfile(info, io.BytesIO(data))
        cls.archive = archive.getvalue()

    def check_install(self, scenario, expected_size):
        requests = []
        archive = self.archive

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def respond(self):
                requests.append((self.command, self.path))
                if self.path == "/release":
                    self.send_response(302)
                    self.send_header("Location", "/archive")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if self.path != "/archive":
                    self.send_error(404)
                    return
                if self.command == "HEAD" and scenario == "head_failure":
                    self.send_error(405)
                    return
                self.send_response(200)
                if self.command == "GET" or scenario == "length":
                    self.send_header("Content-Length", str(len(archive)))
                elif scenario == "invalid_length":
                    self.send_header("Content-Length", "invalid")
                self.end_headers()
                if self.command == "GET":
                    self.wfile.write(archive)

            do_HEAD = respond
            do_GET = respond

        with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                with tempfile.TemporaryDirectory(prefix="llvmup-http-") as directory:
                    root = Path(directory)
                    releases = root / "releases.json"
                    releases.write_text(json.dumps([{
                        "tag_name": VERSION, "draft": False, "prerelease": False,
                        "assets": [{
                            "id": 2018, "name": ASSET_NAME, "state": "uploaded",
                            "browser_download_url": f"http://127.0.0.1:{server.server_port}/release",
                            "digest": "sha256:" + hashlib.sha256(archive).hexdigest(),
                        }],
                    }]))
                    env = dict(os.environ)
                    for key in tuple(env):
                        if key.startswith("LLVMUP_") or key.lower().endswith("_proxy"):
                            env.pop(key)
                    env.update({
                        "LLVMUP_RELEASES_FILE": str(releases),
                        "LLVM_TOOLCHAINS_DIR": str(root / "toolchains"),
                        "TMPDIR": directory, "RUNNER_TEMP": directory,
                        "NO_PROXY": "127.0.0.1", "no_proxy": "127.0.0.1",
                    })
                    result = subprocess.run(
                        [str(INSTALLER), "--verify", "warn", VERSION],
                        cwd=root, env=env, text=True, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT, timeout=45,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout)
                    self.assertIn(f"File size: {expected_size}", result.stdout)
                    self.assertNotIn("File size: 0MB", result.stdout)
                    self.assertIn("SHA256 asset.digest matches the downloaded file", result.stdout)
                    self.assertTrue((root / "toolchains" / VERSION / "bin/clang").is_file())
                    for method in ("HEAD", "GET"):
                        for path in ("/release", "/archive"):
                            self.assertIn((method, path), requests)
            finally:
                server.shutdown()
                thread.join(timeout=5)

    def test_final_size_after_zero_length_redirect(self):
        self.check_install("length", f"{len(self.archive) // 1024 // 1024}MB")

    def test_missing_final_length_does_not_reuse_redirect_size(self):
        self.check_install("missing_length", "unknown")

    def test_invalid_final_length(self):
        self.check_install("invalid_length", "unknown")

    def test_head_failure_still_allows_download(self):
        self.check_install("head_failure", "unknown")


if __name__ == "__main__":
    unittest.main(verbosity=2)
