"""station-probe.ps1 (#33): the probe trusts what it observes, not the receipt."""
import hashlib
import json
import os
import tempfile
import unittest

import pwsh

PROBE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "station-probe.ps1")
COMMIT = "a" * 40
OTHER = "b" * 40


def prelude(pid=4242, exe="", status=200, listeners=1, web_fails=False, commit=COMMIT):
    rows = ",".join(f"[pscustomobject]@{{OwningProcess={pid + i}}}" for i in range(listeners)) if listeners else ""
    headers = "@{}" if commit is None else f"@{{'X-Wstx-Source-Commit'={pwsh.ps_quote(commit)}}}"
    web = ("throw [System.Net.WebException]::new('untrusted')" if web_fails
           else f"[pscustomobject]@{{StatusCode={status}; Headers={headers}}}")
    return f"""
function Get-NetTCPConnection {{ param($LocalPort,$State,$ErrorAction) @({rows}) }}
function Get-CimInstance {{ param($ClassName,$Filter) if ($Filter -eq 'ProcessId={pid}') {{ [pscustomobject]@{{ExecutablePath={pwsh.ps_quote(exe)}}} }} }}
function Invoke-WebRequest {{ param([switch]$UseBasicParsing,$Uri,$TimeoutSec) {web} }}
"""


class ProbeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = self.tmp.name
        self.exe = os.path.join(self.station, COMMIT[:9], "wstx-rust.exe")
        os.makedirs(os.path.dirname(self.exe))
        with open(self.exe, "wb") as f:
            f.write(b"candidate image")
        self.digest = hashlib.sha256(b"candidate image").hexdigest()
        self.receipt(COMMIT, 4242, self.digest)

    def tearDown(self):
        self.tmp.cleanup()

    def receipt(self, commit, pid, digest):
        with open(os.path.join(self.station, "station-running.json"), "w", encoding="utf-8") as f:
            json.dump({"source_commit": commit, "process_id": pid, "artifact_sha256": digest}, f)

    def probe(self, pre, commit=COMMIT, digest=None):
        return pwsh.run(PROBE, ["-Commit", commit, "-ArtifactSha256", digest or self.digest, "-Station", self.station], pre)

    def test_pass_when_listener_runs_the_candidate(self):
        rc, out = self.probe(prelude(exe=self.exe))
        self.assertEqual(rc, 0, out)
        self.assertIn("service: reports commit aaaaaaaaa", out)
        self.assertIn("PROBE PASS aaaaaaaaa PID 4242", out)

    def test_fail_when_the_service_reports_another_commit(self):
        for reported in (OTHER, "unknown", COMMIT.upper(), f"{COMMIT},{OTHER}"):
            rc, out = self.probe(prelude(exe=self.exe, commit=reported))
            self.assertEqual(rc, 1, out)
            self.assertIn(f"PROBE FAIL service reports commit {reported}, expected {COMMIT}", out)

    def test_build_from_before_33_without_header_keeps_the_digest_identity(self):
        rc, out = self.probe(prelude(exe=self.exe, commit=None))
        self.assertEqual(rc, 0, out)
        self.assertIn("service: reports no commit", out)
        self.assertIn("PROBE PASS", out)

    def test_fail_when_listener_runs_another_version(self):
        other = os.path.join(self.station, OTHER[:9], "wstx-rust.exe")
        os.makedirs(os.path.dirname(other))
        with open(other, "wb") as f:
            f.write(b"candidate image")
        rc, out = self.probe(prelude(exe=other))
        self.assertEqual(rc, 1, out)
        self.assertIn("PROBE FAIL listener PID 4242 runs", out)

    def test_fail_when_image_bytes_differ_even_if_receipt_agrees(self):
        with open(self.exe, "wb") as f:
            f.write(b"swapped image")
        rc, out = self.probe(prelude(exe=self.exe))
        self.assertEqual(rc, 1, out)
        self.assertIn("listener image digest", out)

    def test_fail_when_receipt_disagrees_with_the_observation(self):
        self.receipt(COMMIT, 999, self.digest)
        rc, out = self.probe(prelude(exe=self.exe))
        self.assertEqual(rc, 1, out)
        self.assertIn("launcher receipt disagrees", out)

    def test_fail_without_exactly_one_listener(self):
        for n in (0, 2):
            rc, out = self.probe(prelude(exe=self.exe, listeners=n))
            self.assertEqual(rc, 1, out)
            self.assertIn(f"has {n} listening processes", out)

    def test_fail_when_health_is_not_trusted_200(self):
        rc, out = self.probe(prelude(exe=self.exe, web_fails=True))
        self.assertEqual(rc, 1, out)
        self.assertIn("did not answer over trusted TLS", out)
        rc, out = self.probe(prelude(exe=self.exe, status=204))
        self.assertEqual(rc, 1, out)
        self.assertIn("answered 204", out)

    def test_manifest_digest_is_recomputed_from_the_package(self):
        pkg = os.path.join(self.station, "pkg")
        os.makedirs(os.path.join(pkg, "package"))
        with open(os.path.join(pkg, "package", "wstx-rust.exe"), "wb") as f:
            f.write(b"candidate image")
        with open(os.path.join(pkg, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump({"source_commit": COMMIT, "artifact_sha256": "0" * 64}, f)
        rc, out = pwsh.run(PROBE, ["-Manifest", os.path.join(pkg, "manifest.json"), "-Station", self.station], prelude(exe=self.exe))
        self.assertEqual(rc, 0, out)

    def test_bad_arguments_exit_2(self):
        rc, out = pwsh.run(PROBE, ["-Commit", "abc", "-ArtifactSha256", self.digest, "-Station", self.station], prelude(exe=self.exe))
        self.assertEqual(rc, 2, out)

    def test_mistyped_manifest_is_a_usage_error_not_a_failed_probe(self):
        rc, out = pwsh.run(PROBE, ["-Manifest", os.path.join(self.station, "no-such", "manifest.json"), "-Station", self.station], prelude(exe=self.exe))
        self.assertEqual(rc, 2, out)
        self.assertIn("PROBE ERROR cannot read the package", out)
        self.assertNotIn("PROBE FAIL", out)


if __name__ == "__main__":
    unittest.main()
