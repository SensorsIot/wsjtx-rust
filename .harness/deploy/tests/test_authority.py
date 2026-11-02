"""Station deploy authority (#30, #31, #32), switched off: its checks refuse what they claim."""
import hashlib
import json
import os
import subprocess
import tempfile
import unittest

import pwsh

AUTH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "authority")
LIB = os.path.join(AUTH, "authority-lib.ps1")
KEYGEN = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\OpenSSH\ssh-keygen.exe")
COMMIT = "1234567890" + "ab" * 15
OTHER = "f" * 40
DIGEST = hashlib.sha256(b"approved image").hexdigest()
DEST = "HB9BLA-station 192.168.0.37:18081"
PRINCIPAL = "operator@HB9BLA"


def keygen(path):
    subprocess.run([KEYGEN, "-q", "-t", "ed25519", "-N", "", "-f", path], check=True, capture_output=True)


def lib_call(body):
    """Run `body` after dot-sourcing the library; print OK or the refusal."""
    script = f"""
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. {pwsh.ps_quote(LIB)}
Use-SystemModules
try {{ {body}; 'OK' }} catch {{ [string]$_.Exception.Message }}
"""
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "call.ps1")
        with open(path, "w", encoding="utf-8-sig") as f:
            f.write(script)
        rc, out = pwsh.run(path)
    return out.strip().splitlines()[-1] if out.strip() else f"(no output, exit {rc})"


@unittest.skipUnless(os.path.isfile(KEYGEN), "Windows OpenSSH ssh-keygen is not installed")
class ApprovalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.root = os.path.join(t, "root")
        self.station = os.path.join(t, "station")
        os.makedirs(self.root)
        os.makedirs(os.path.join(self.station, "approvals"))
        self.key = os.path.join(t, "operator")
        self.other_key = os.path.join(t, "agent")
        keygen(self.key)
        keygen(self.other_key)
        with open(self.key + ".pub", encoding="utf-8") as f:
            pub = " ".join(f.read().split()[:2])
        with open(os.path.join(self.root, "allowed_signers"), "w", encoding="utf-8") as f:
            f.write(f'{PRINCIPAL} namespaces="wstx-station-approval" {pub}\n')
        with open(os.path.join(self.root, "policy.json"), "w", encoding="utf-8") as f:
            json.dump({"destination": DEST, "signer_principal": PRINCIPAL}, f)
        with open(os.path.join(self.root, "revoked.txt"), "w", encoding="utf-8") as f:
            f.write("")

    def tearDown(self):
        self.tmp.cleanup()

    def approve(self, key=None, namespace="wstx-station-approval", file_commit=COMMIT, **fields):
        record = {"schema": "wstx-station-approval/1", "commit": COMMIT, "artifact_sha256": DIGEST,
                  "destination": DEST, "requested_utc": "2026-11-02T08:00:00Z"}
        record.update(fields)
        record = {k: v for k, v in record.items() if v is not None}
        path = os.path.join(self.station, "approvals", f"{file_commit}.approval.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(record, f, indent=2)
        subprocess.run([KEYGEN, "-Y", "sign", "-f", key or self.key, "-n", namespace, path], check=True, capture_output=True)
        return path

    def check(self, commit=COMMIT, digest=DIGEST):
        return lib_call(f"$null = Test-StationApproval {pwsh.ps_quote(self.root)} {pwsh.ps_quote(self.station)} '{commit}' '{digest}'")

    def test_operator_approval_of_this_candidate_passes(self):
        self.approve()
        self.assertEqual(self.check(), "OK")

    def test_request_signed_by_the_operator_verifies(self):
        pkg = os.path.join(self.tmp.name, "pkg")
        os.makedirs(os.path.join(pkg, "package"))
        with open(os.path.join(pkg, "package", "wstx-rust.exe"), "wb") as f:
            f.write(b"approved image")
        with open(os.path.join(pkg, "gates.json"), "w", encoding="utf-8") as f:
            json.dump({"status": "passed", "prepush_passed": True, "gate_receipt": {"path": "log"}}, f)
        with open(os.path.join(pkg, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump({"source_commit": COMMIT, "artifact_sha256": DIGEST, "gate_receipt_path": os.path.join(pkg, "gates.json")}, f)
        rc, out = pwsh.run(os.path.join(AUTH, "request-approval.ps1"), ["-Manifest", os.path.join(pkg, "manifest.json")])
        self.assertEqual(rc, 0, out)
        request = os.path.join(pkg, f"{COMMIT}.approval.json")
        subprocess.run([KEYGEN, "-Y", "sign", "-f", self.key, "-n", "wstx-station-approval", request], check=True, capture_output=True)
        for suffix in ("", ".sig"):
            os.replace(request + suffix, os.path.join(self.station, "approvals", f"{COMMIT}.approval.json{suffix}"))
        self.assertEqual(self.check(), "OK")

    def test_missing_approval_refuses(self):
        self.assertIn("refused: no operator approval for 123456789", self.check())

    def test_approval_changed_after_signing_refuses(self):
        path = self.approve()
        with open(path, encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(DEST, "HB9BLA-station 192.168.0.37:18082"))
        self.assertIn("refused: approval signature is not the operator's", self.check())

    def test_approval_signed_by_another_key_refuses(self):
        self.approve(key=self.other_key)
        self.assertIn("refused: approval signature is not the operator's", self.check())

    def test_signature_for_another_purpose_refuses(self):
        self.approve(namespace="file")
        self.assertIn("refused: approval signature is not the operator's", self.check())

    def test_approval_of_another_commit_refuses(self):
        self.approve(commit=OTHER)
        self.assertIn(f"refused: approval names commit {OTHER}", self.check())

    def test_approval_of_another_artifact_refuses(self):
        self.approve()
        self.assertIn("refused: approval names artifact", self.check(digest=hashlib.sha256(b"other").hexdigest()))

    def test_approval_for_another_destination_refuses(self):
        self.approve(destination="test-bench 127.0.0.1:18081")
        self.assertIn("refused: approval names destination", self.check())

    def test_unknown_field_refuses(self):
        self.approve(expires="never")
        self.assertIn("refused: approval fields are", self.check())

    def test_revoked_artifact_refuses(self):
        self.approve()
        with open(os.path.join(self.root, "revoked.txt"), "w", encoding="utf-8") as f:
            f.write(DIGEST.upper() + "\n")
        self.assertIn("refused: artifact", self.check())
        self.assertIn("is revoked", self.check())


class ProtectionTests(unittest.TestCase):
    def sid(self):
        out = subprocess.run(["whoami", "/user", "/fo", "csv", "/nh"], capture_output=True, text=True, check=True).stdout
        return out.strip().split(",")[-1].strip('"')

    def test_user_owned_folder_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIn("refused:", lib_call(f"Assert-Protected {pwsh.ps_quote(tmp)}"))
            self.assertIn("is owned by", lib_call(f"Assert-Protected {pwsh.ps_quote(tmp)}"))

    def test_folder_another_account_may_change_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            trusted = f"@('{self.sid()}','S-1-5-18','S-1-5-32-544')"
            self.assertEqual(lib_call(f"Assert-Protected {pwsh.ps_quote(tmp)} {trusted}"), "OK")
            subprocess.run(["icacls", tmp, "/grant", "*S-1-1-0:(M)"], check=True, capture_output=True)
            self.assertIn("refused: S-1-1-0 may change", lib_call(f"Assert-Protected {pwsh.ps_quote(tmp)} {trusted}"))

    def test_this_machines_system_paths_pass(self):
        """enable-authority.ps1 would not refuse on HB9BLA for its ancestors and system tools."""
        self.assertEqual(lib_call(r"Assert-Protected 'C:\ProgramData' -Ancestor; Assert-Protected 'C:\' -Ancestor"), "OK")
        self.assertEqual(lib_call(r"Assert-Protected (Join-Path $PSHOME 'powershell.exe'); Assert-Protected (Get-SshKeygen)"), "OK")

    def test_ancestor_check_is_narrower_than_leaf(self):
        # Users may create folders in C:\ProgramData: harmless for an ancestor, not for the root.
        self.assertIn("may change", lib_call(r"Assert-Protected 'C:\ProgramData'"))


class LauncherStartTests(unittest.TestCase):
    def test_pinned_executable_starts_and_the_receipt_names_it(self):
        """The launcher's start block runs the exe while it is pinned and records it."""
        with tempfile.TemporaryDirectory() as base:
            exe = os.path.join(base, COMMIT[:9], "wstx-rust.exe")
            os.makedirs(os.path.dirname(exe))
            with open(os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\whoami.exe"), "rb") as src, open(exe, "wb") as dst:
                dst.write(src.read())
            os.makedirs(os.path.join(base, "secrets"))
            os.makedirs(os.path.join(base, "logs"))
            with open(os.path.join(base, "secrets", "access-token.txt"), "w", encoding="utf-8") as f:
                f.write("test-token\n")
            body = (f"$pin = Open-Pinned {pwsh.ps_quote(exe)}; try {{ $d = Get-StreamSha256 $pin; "
                    f"$code = Start-ApprovedStation {pwsh.ps_quote(base)} '{COMMIT}' {pwsh.ps_quote(exe)} $d 'stamp'; "
                    f"try {{ [IO.File]::WriteAllText({pwsh.ps_quote(exe)}, 'x'); throw 'exe was writable' }} catch [IO.IOException] {{}} }} "
                    f"finally {{ $pin.Dispose() }}; if ($code -ne 1) {{ throw \"exit code $code\" }}")
            self.assertEqual(lib_call(body), "OK")
            with open(os.path.join(base, "station-running.json"), encoding="utf-8") as f:
                receipt = json.load(f)
            self.assertEqual(receipt["source_commit"], COMMIT)
            self.assertEqual(receipt["executable"], exe)
            self.assertEqual(receipt["launcher"], "active.json")
            with open(exe, "rb") as f:
                self.assertEqual(receipt["artifact_sha256"], hashlib.sha256(f.read()).hexdigest())
            # whoami rejects --profile with exit code 1 (checked above), so it really ran.
            self.assertTrue(os.path.exists(os.path.join(base, "logs", "stamp.stdout.log")))


class EntryTests(unittest.TestCase):
    def test_verifier_outside_the_protected_root_refuses(self):
        rc, out = pwsh.run(os.path.join(AUTH, "verify-approval.ps1"), ["-Manifest", "x"])
        self.assertEqual(rc, 1, out)
        self.assertIn(r"REFUSED run from C:\ProgramData\WstxRust\deploy-authority", out)

    def test_every_authority_script_parses(self):
        for name in sorted(os.listdir(AUTH)):
            if name.endswith(".ps1"):
                script = ("$e=$null; $null=[System.Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText("
                          + pwsh.ps_quote(os.path.join(AUTH, name)) + "),[ref]$e); if ($e.Count) { $e | % { $_.Message }; exit 1 }")
                proc = subprocess.run([pwsh.POWERSHELL, "-NoProfile", "-NonInteractive", "-Command", script], capture_output=True, text=True)
                self.assertEqual(proc.returncode, 0, name + proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
