#!/usr/bin/env python3
"""Exercise publication refusals using synthetic files in isolated repositories."""
from pathlib import Path
from tempfile import TemporaryDirectory
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RepositoryChecksTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "build").mkdir(exist_ok=True)
        self.temporary = TemporaryDirectory(prefix="repository-check-", dir=ROOT / "build")
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name)
        (self.fixture / "scripts").mkdir()
        shutil.copyfile(ROOT / "scripts/check-repository.py", self.fixture / "scripts/check-repository.py")
        self.write("README.md", "# Example\n\n[Guide](guide.md#用法)\n")
        self.write("guide.md", "# 用法\n")

    def write(self, name, value):
        (self.fixture / name).write_text(value)

    def check_repo(self, *args):
        return subprocess.run(["python3", "scripts/check-repository.py", *args], cwd=self.fixture,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def git(self, *args):
        subprocess.run(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", *args],
                       cwd=self.fixture, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def test_source_zip_and_utf8_anchor(self):
        # Parent is a real checkout; the source ZIP must not inspect that parent.
        self.assertEqual(self.check_repo().returncode, 0)

    def test_broken_html_and_markdown_links(self):
        self.write("README.md", '# Example\n[missing](guide.md#不存在)\n<img src="absent.png">\n')
        result = self.check_repo()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing heading anchor", result.stderr)
        self.assertIn("Broken local link", result.stderr)

    def test_forbidden_untracked_file_without_git(self):
        self.write(".env.local", "synthetic fixture, no account data")
        self.assertNotEqual(self.check_repo().returncode, 0)

    def test_credentials_withheld(self):
        synthetic = "ghp_" + "A" * 36
        self.write("example.txt", synthetic)
        result = self.check_repo()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Potential credential", result.stderr)
        self.assertNotIn(synthetic, result.stdout + result.stderr)

    def test_deleted_credentials_still_refused_in_history(self):
        self.git("init", "-q")
        self.write("old.txt", "ghp_" + "B" * 36)
        self.git("add", ".")
        self.git("commit", "-qm", "synthetic initial fixture")
        (self.fixture / "old.txt").unlink()
        self.git("add", "-u")
        self.git("commit", "-qm", "remove synthetic value")
        self.assertEqual(self.check_repo().returncode, 0)
        result = self.check_repo("--history")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Potential historical credential", result.stderr)

    def test_outside_symlink_refused(self):
        (self.fixture / "linked-file").symlink_to(ROOT / "README.md")
        result = self.check_repo()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Review symlink", result.stderr)


if __name__ == "__main__":
    unittest.main()
