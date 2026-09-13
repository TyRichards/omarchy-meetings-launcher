#!/usr/bin/env python3

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "meetings-config"
MAX_CONFIG_BYTES = 65536
VALID = b'{"version":1,"meetings":[]}\n'


class ConfigHelperTests(unittest.TestCase):
    def run_helper(self, action, path, *, data=None, expected=0):
        result = subprocess.run(
            [str(HELPER), action, str(path)],
            input=data,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=3,
            check=False,
        )
        self.assertEqual(
            result.returncode,
            expected,
            msg=f"stdout={result.stdout!r}\nstderr={result.stderr!r}",
        )
        return result

    def test_atomic_private_write_and_bounded_read(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "omarchy" / "meetings.json"
            self.run_helper("setup", path)
            self.run_helper("write", path, data=VALID)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(self.run_helper("read", path).stdout, VALID)
            self.assertEqual(list(path.parent.glob(".meetings.*")), [])

    def test_setup_enforces_exact_private_mode(self):
        for starting_mode in (0o644, 0o700, 0o400):
            with self.subTest(starting_mode=oct(starting_mode)), tempfile.TemporaryDirectory() as temp:
                directory = Path(temp) / "omarchy"
                directory.mkdir()
                path = directory / "meetings.json"
                path.write_bytes(VALID)
                path.chmod(starting_mode)
                self.run_helper("setup", path)
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)

    def test_read_rejects_a_permissive_mode_before_migration(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "omarchy"
            directory.mkdir()
            path = directory / "meetings.json"
            path.write_bytes(VALID)
            path.chmod(0o644)
            self.run_helper("read", path, expected=2)

    def test_missing_file_is_not_an_error_condition(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "omarchy" / "meetings.json"
            self.run_helper("setup", path)
            self.run_helper("read", path, expected=1)

    def test_symlink_file_is_rejected_for_read_and_write(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "omarchy"
            directory.mkdir()
            target = directory / "target"
            target.write_bytes(b"unchanged")
            path = directory / "meetings.json"
            path.symlink_to(target)
            self.run_helper("read", path, expected=2)
            self.run_helper("write", path, data=VALID, expected=2)
            self.assertEqual(target.read_bytes(), b"unchanged")

    def test_fifo_is_rejected_without_blocking(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "omarchy"
            directory.mkdir()
            path = directory / "meetings.json"
            os.mkfifo(path, 0o600)
            self.run_helper("read", path, expected=2)
            self.run_helper("write", path, data=VALID, expected=2)

    def test_symlinked_parent_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            real = base / "real"
            real.mkdir()
            linked = base / "linked"
            linked.symlink_to(real, target_is_directory=True)
            self.run_helper("read", linked / "meetings.json", expected=2)

    def test_group_or_world_writable_config_directory_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "omarchy"
            directory.mkdir(mode=0o777)
            directory.chmod(0o777)
            self.run_helper("write", directory / "meetings.json", data=VALID, expected=2)

    def test_oversized_read_and_write_preserve_prior_file(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "omarchy"
            directory.mkdir()
            path = directory / "meetings.json"
            path.write_bytes(b"x" * (MAX_CONFIG_BYTES + 1))
            path.chmod(0o600)
            self.run_helper("read", path, expected=2)

            path.write_bytes(VALID)
            path.chmod(0o600)
            self.run_helper(
                "write",
                path,
                data=b"x" * (MAX_CONFIG_BYTES + 1),
                expected=2,
            )
            self.assertEqual(path.read_bytes(), VALID)


if __name__ == "__main__":
    unittest.main()
