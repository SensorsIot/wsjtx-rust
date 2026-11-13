"""make_package.py: the package carries the commit's mechanism bytes, never a working folder's.

TC-171-02 (b): a working-folder script edited after the commit has no effect on the package,
also under CRLF settings. The oracle is the blob of the commit (git cat-file) in a temporary
repository that carries this repository's .gitattributes.
"""
import hashlib
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import station_drill  # noqa: E402

spec = importlib.util.spec_from_file_location("make_package", os.path.join(ROOT, "tools", "deploy", "station-update", "make_package.py"))
make_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(make_package)


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True).stdout


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class MakePackageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "repo")
        os.makedirs(self.repo)
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "drill@example.invalid")
        git(self.repo, "config", "user.name", "drill")
        git(self.repo, "config", "core.autocrlf", "true")
        git(self.repo, "config", "core.eol", "crlf")
        shutil.copyfile(os.path.join(ROOT, ".gitattributes"), os.path.join(self.repo, ".gitattributes"))
        for path in station_drill.MECHANISM + ("other.txt",):
            full = os.path.join(self.repo, *path.split("/"))
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "wb") as f:
                f.write(f"# {path}\nline two\n".encode())
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "mechanism")

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_package_holds_the_commit_bytes_not_an_edited_working_folder(self):
        edited = os.path.join(self.repo, *station_drill.MECHANISM[0].split("/"))
        with open(edited, "ab") as f:
            f.write(b"# edited in the working folder\n")
        src, out = os.path.join(self.tmp.name, "src"), os.path.join(self.tmp.name, "out")
        make_package.export(self.repo, "HEAD", src)
        files = make_package.copy_mechanism(src, out)
        self.assertEqual(sorted(f["path"] for f in files), sorted(station_drill.MECHANISM))
        for f in files:
            with open(os.path.join(out, "deploy", *f["path"].split("/")), "rb") as g:
                data = g.read()
            blob = git(self.repo, "cat-file", "blob", f"HEAD:{f['path']}")
            self.assertEqual(data, blob, f["path"])
            self.assertEqual(f["sha256"], sha256(blob), f["path"])
        # The CRLF settings are active: a text file of the same export got CRLF.
        with open(os.path.join(src, "other.txt"), "rb") as g:
            self.assertIn(b"\r\n", g.read())

    def test_a_new_file_in_the_station_update_folder_is_a_mechanism_file(self):
        extra = os.path.join(self.repo, "tools", "deploy", "station-update", "helper.ps1")
        with open(extra, "wb") as f:
            f.write(b"# helper\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "helper")
        src = os.path.join(self.tmp.name, "src")
        make_package.export(self.repo, "HEAD", src)
        self.assertIn("tools/deploy/station-update/helper.ps1", make_package.mechanism_paths(src))

    def test_packages_go_to_the_shared_folder_also_from_a_worktree(self):
        wt = os.path.join(self.tmp.name, "wt")
        git(self.repo, "worktree", "add", "-q", "--detach", wt, "HEAD")
        expected = os.path.join(self.repo, ".git", "harness-parallel", "resources", "station-update", "packages")
        for start in (self.repo, wt):
            self.assertEqual(os.path.normcase(os.path.normpath(make_package.packages_root(start))),
                             os.path.normcase(os.path.normpath(expected)))


if __name__ == "__main__":
    unittest.main()
