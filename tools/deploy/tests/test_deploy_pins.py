"""The deploy pins of docs/harness/Project-Specifics.md (section Deploy pins).

Acceptance item 2 of #171: the mechanism files are versioned with -text and each pin is the
SHA-256 of its blob; TC-171-02 (i): a checkout or export with CRLF settings holds the blob's bytes.
The oracle is git itself: the blob of HEAD and git archive under core.autocrlf=true.
"""
import hashlib
import io
import os
import re
import subprocess
import sys
import tarfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.dirname(HERE))
import station_drill  # noqa: E402

SPECIFICS = os.path.join(ROOT, "docs", "harness", "Project-Specifics.md")
STATION_UPDATE = os.path.join(ROOT, "tools", "deploy", "station-update", "station-update.ps1")
MAKE_PACKAGE = os.path.join(ROOT, "tools", "deploy", "station-update", "make_package.py")
# A text=auto file of the same tree: under the CRLF settings its export must differ from its blob.
CONTROL = "tools/deploy/tests/pwsh.py"


def git(*args):
    return subprocess.run(["git", "-C", ROOT, *args], check=True, capture_output=True).stdout


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pins():
    """[(sha256, path)] of the Deploy pins section of the checked-out Project-Specifics.md."""
    found, inside = [], False
    with open(SPECIFICS, encoding="utf-8") as f:
        for line in f.read().splitlines():
            if re.match(r"#{1,6} ", line):
                inside = re.match(r"#{1,6} Deploy pins\s*$", line) is not None
                continue
            m = re.match(r"([0-9a-f]{64})  (\S+)\s*$", line)
            if inside and m:
                found.append((m.group(1), m.group(2)))
    return found


class DeployPinTests(unittest.TestCase):
    def test_each_pin_is_the_sha256_of_its_blob_and_of_the_checked_out_file(self):
        p = pins()
        self.assertTrue(p, "Project-Specifics.md has no Deploy pins")
        wrong = []
        for pin, path in p:
            blob = sha256(git("cat-file", "blob", f"HEAD:{path}"))
            with open(os.path.join(ROOT, *path.split("/")), "rb") as f:
                checked_out = sha256(f.read())
            if pin != blob or pin != checked_out:
                wrong.append(f"{path}: pin {pin}, blob {blob}, checked out {checked_out}")
        self.assertEqual(wrong, [], "\n".join(wrong))

    def test_the_pins_name_every_mechanism_file_in_the_order_the_deploy_reads(self):
        tree = git("ls-tree", "-r", "--name-only", "HEAD", "--", "tools/deploy/station-update/").decode().split()
        with open(MAKE_PACKAGE, encoding="utf-8") as f:
            extra = re.search(r"MECHANISM_FILES = \(([^)]*)\)", f.read()).group(1)
        expected = sorted(tree) + re.findall(r'"([^"]+)"', extra)
        pinned = [path for _, path in pins()]
        self.assertEqual(sorted(pinned), sorted(expected))
        with open(STATION_UPDATE, encoding="utf-8") as f:
            order = re.findall(r"'([^']+)'", re.search(r"\$MechanismPaths=@\(([^)]*)\)", f.read()).group(1))
        self.assertEqual(pinned, order, "pin order is not the order station-update.ps1 reads")
        self.assertEqual(tuple(order), station_drill.MECHANISM)

    def test_mechanism_files_are_not_text(self):
        out = git("check-attr", "text", "--", *station_drill.MECHANISM).decode().splitlines()
        self.assertEqual([line.rsplit(": ", 1)[1] for line in out], ["unset"] * len(station_drill.MECHANISM), out)

    def test_a_crlf_export_holds_the_blob_bytes(self):
        """TC-171-02 (i): git archive applies the checked-out .gitattributes and CRLF settings."""
        paths = list(station_drill.MECHANISM) + [CONTROL]
        data = git("-c", "core.autocrlf=true", "-c", "core.eol=crlf", "archive", "--worktree-attributes",
                   "--format=tar", "HEAD", *paths)
        with tarfile.open(fileobj=io.BytesIO(data)) as t:
            exported = {m.name: t.extractfile(m).read() for m in t.getmembers() if m.isfile()}
        for path in station_drill.MECHANISM:
            with self.subTest(path):
                self.assertEqual(sha256(exported[path]), sha256(git("cat-file", "blob", f"HEAD:{path}")))
        control = git("cat-file", "blob", f"HEAD:{CONTROL}")
        self.assertNotIn(b"\r\n", control)
        self.assertIn(b"\r\n", exported[CONTROL], "the CRLF settings did not reach the export")


if __name__ == "__main__":
    unittest.main()
