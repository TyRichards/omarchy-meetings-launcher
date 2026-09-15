#!/usr/bin/env python3

import html
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "meetings-launch"
PANEL = ROOT / "Panel.qml"


class LaunchHelperTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.runtime = self.base / "runtime"
        self.runtime.mkdir(mode=0o700)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.capture = self.base / "capture.json"
        launcher = self.bin / "omarchy-launch-webapp"
        launcher.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import json
                import os
                from pathlib import Path
                import stat
                import sys
                from urllib.parse import unquote, urlsplit

                uri = sys.argv[1]
                path = Path(unquote(urlsplit(uri).path))
                result = {{
                    "argv": sys.argv,
                    "contains_secret_environment": any("super-secret" in value for value in os.environ.values()),
                    "directory_mode": stat.S_IMODE(path.parent.stat().st_mode),
                    "file_mode": stat.S_IMODE(path.stat().st_mode),
                    "document": path.read_text(),
                }}
                info = path.stat()
                os.utime(path, ns=(info.st_atime_ns + 1, info.st_mtime_ns))
                Path(os.environ["MEETINGS_TEST_CAPTURE"]).write_text(json.dumps(result))
                """
            )
        )
        launcher.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment.update(
            {
                "PATH": f"{self.bin}:{self.environment.get('PATH', '')}",
                "XDG_RUNTIME_DIR": str(self.runtime),
                "MEETINGS_TEST_CAPTURE": str(self.capture),
            }
        )

    def tearDown(self):
        self.temporary.cleanup()

    def run_helper(self, url, *arguments, expected=0):
        result = subprocess.run(
            [str(HELPER), *arguments],
            input=url.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=self.environment,
            timeout=3,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected,
            msg=f"stdout={result.stdout!r}\nstderr={result.stderr!r}",
        )
        return result

    def test_secret_reaches_private_redirect_only_through_stdin(self):
        url = "https://meet.example/room?token=super-secret&name=R%26D"
        self.run_helper(url)

        captured = json.loads(self.capture.read_text())
        self.assertEqual(captured["argv"][0], str(self.bin / "omarchy-launch-webapp"))
        self.assertEqual(len(captured["argv"]), 2)
        self.assertNotIn("super-secret", captured["argv"][1])
        self.assertFalse(captured["contains_secret_environment"])
        self.assertEqual(captured["directory_mode"], 0o700)
        self.assertEqual(captured["file_mode"], 0o600)
        self.assertIn(html.escape(url, quote=True), captured["document"])
        self.assertEqual(list(self.runtime.glob("omarchy-meetings-*")), [])

    def test_rejects_noncanonical_or_unsafe_urls_without_launching(self):
        invalid = (
            "http://example.com/room",
            "https://user:password@example.com/room",
            "https://EXAMPLE.com/room",
            "https://example.com.:443/room",
            "https://example.com/room\nsecond",
            "javascript:alert(1)",
        )
        for url in invalid:
            with self.subTest(url=url):
                self.capture.unlink(missing_ok=True)
                self.run_helper(url, expected=2)
                self.assertFalse(self.capture.exists())

    def test_requires_private_runtime_directory(self):
        self.runtime.chmod(0o755)
        self.run_helper("https://example.com/room", expected=2)
        self.assertFalse(self.capture.exists())

    def test_rejects_url_in_argv(self):
        self.run_helper(
            "https://example.com/room",
            "https://example.com/secret",
            expected=2,
        )
        self.assertFalse(self.capture.exists())

    def test_panel_uses_only_the_fixed_stdin_helper_for_launches(self):
        source = PANEL.read_text()
        self.assertNotIn('execDetached(["omarchy-launch-webapp"', source)
        self.assertNotIn('execDetached(["wl-copy"', source)
        self.assertIn('command: ["timeout", "15", root.launchHelper]', source)
        self.assertIn("launchProc.write(root.activeLaunch)", source)
        self.assertIn('command: ["wl-copy", "--"]', source)
        self.assertIn("copyProc.write(root.activeCopy)", source)


if __name__ == "__main__":
    unittest.main()
