"""Show each refusal of station-update.ps1 happening before the destination changes (#34).

usage: python .harness/deploy/station_drill.py [--script <station-update.ps1>] [--keep <dir>]

Runs a copy of the install script against a sandbox station (LOCALAPPDATA points into a
temporary directory) with every command that reaches the system replaced by a mock: the
scheduled task, the firewall rule, processes, the network and git. Commands that would
change the system (start/stop the task, start/stop a process, web requests) record a
sentinel and throw. Before running, the drill refuses a script that uses a command, .NET
type or call target it has not classified, `$ExecutionContext`, an environment variable
other than LOCALAPPDATA, or a literal absolute path other than the repository (used only
by the mocked git) and the protected deploy-authority root. This keeps the commands the
drill knows away from the live station; it is no sandbox against code written to escape
it, so read a changed script's diff before drilling it.

For each case it builds a package as make_package.py does, damages one thing, runs the
script without -DryRun and requires: a non-zero exit, the refusal's own message (a refusal
for another reason fails the case), no sentinel, and the sandbox station (version
directories, active.json, profiles, launcher) unchanged byte for byte; only logs\\ may
change. Two positive controls show that the mocks do not refuse everything: the intact
package passes -DryRun unchanged, and without -DryRun it reaches the station stop. Cases
marked LIMIT are not refused today; they are reported so that the rule stays stated as
unmet (#31, #32) and fail the drill if that ever changes unnoticed.

Exit 0: every case as expected. Exit 1: a case differs. Exit 2: the drill could not run.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
POWERSHELL = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")
CURRENT = "c" * 40
COMMIT = "1234567890" + "ab" * 15
OLDER = "0" * 40
TASK = "WSTX Rust Station HB9BLA"

# Every Verb-Noun command the script may use. Mocked ones are replaced in the prelude; the
# rest only touch paths under the sandbox the script derives from LOCALAPPDATA and -Manifest.
MOCKED = {"Get-ScheduledTask", "Start-ScheduledTask", "Stop-ScheduledTask", "Get-NetFirewallRule",
          "Get-NetFirewallAddressFilter", "Get-NetFirewallPortFilter", "Get-CimInstance", "Start-Process",
          "Stop-Process", "Invoke-WebRequest", "git", "powershell.exe"}
LOCAL = {"Set-StrictMode", "Join-Path", "Split-Path", "Test-Path", "Get-Item", "Get-FileHash", "Get-ChildItem",
         "Copy-Item", "New-Item", "Remove-Item", "Rename-Item", "Get-Content", "Add-Content", "ConvertFrom-Json",
         "ConvertTo-Json", "Resolve-Path", "Write-Output", "Where-Object", "Start-Sleep", "Out-Null",
         "Safe-Child", "Station-Processes", "Assert-Setup", "Firewall-Scope", "Send-CtrlC", "Stop-Station",
         "Start-Ready", "Write-Active", "Save-Profile", "Restore-Profile", "Switch-Back", "Step", "Hash", "ForEach-Object"}
# .NET types the script may name; file and path methods act on the same sandbox paths.
TYPES = {"[Convert]", "[DateTime]", "[IO.FileAttributes]", "[IO.File]", "[IO.Path]", "[NullString]", "[StringComparison]",
         "[Text.Encoding]", "[Text.UTF8Encoding]", "[bool]", "[int]", "[ordered]", "[string]", "[switch]"}

PRELUDE = r"""
$global:DrillSentinel = $env:DRILL_SENTINEL
function Drill-Mutation($name) { Add-Content -LiteralPath $global:DrillSentinel -Value $name; throw "DRILL-SENTINEL $name" }
function Get-ScheduledTask { param($TaskName)
  $a = if ($env:DRILL_TASK_ARGS) { $env:DRILL_TASK_ARGS } else { "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:LOCALAPPDATA\WstxRust\station\launcher.ps1`"" }
  [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = $a }); State = 'Ready' } }
function Start-ScheduledTask { Drill-Mutation 'Start-ScheduledTask' }
function Stop-ScheduledTask { Drill-Mutation 'Stop-ScheduledTask' }
function Start-Process { Drill-Mutation 'Start-Process' }
function Stop-Process { Drill-Mutation 'Stop-Process' }
function Invoke-WebRequest { Drill-Mutation 'Invoke-WebRequest' }
function Get-CimInstance { @() }
function Get-NetFirewallRule { param($Name) [pscustomobject]@{ Enabled = 'True'; Direction = 'Inbound'; Action = 'Allow' } }
function Get-NetFirewallAddressFilter { process { [pscustomobject]@{ LocalAddress = '192.168.0.37'; RemoteAddress = $(if ($env:DRILL_REMOTE) { $env:DRILL_REMOTE } else { '192.168.0.6' }) } } }
function Get-NetFirewallPortFilter { process { [pscustomobject]@{ Protocol = 'TCP'; LocalPort = '18081' } } }
function git {
  if ($args -contains 'fetch') { $global:LASTEXITCODE = $(if ($env:DRILL_FETCH_FAIL) { 1 } else { 0 }); return }
  if ($args -contains 'merge-base') { $c = $args[$args.Count - 2]; $global:LASTEXITCODE = $(if (($env:DRILL_ON_MASTER -split ',') -contains $c) { 0 } else { 1 }); return }
  Drill-Mutation "git $args" }
function powershell.exe {
  if (-not ($args -like '*\deploy-authority\verify-approval.ps1')) { Drill-Mutation "powershell.exe $args" }
  if ($env:DRILL_APPROVAL -eq 'refused') { 'REFUSED approval names artifact (drill)'; $global:LASTEXITCODE = 1 } else { 'APPROVED (drill)'; $global:LASTEXITCODE = 0 } }
"""


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256(path):
    with open(path, "rb") as f:
        return sha256_bytes(f.read())


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("utf-8"))


def write_json(path, obj):
    write(path, json.dumps(obj, indent=2))


TOKENIZE = r"""
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($env:DRILL_SCRIPT), [ref]$tokens, [ref]$errs)
if ($errs.Count) { 'PARSE-ERROR'; exit 1 }
$L = [System.Management.Automation.Language.Ast].Assembly
function All($type) { $t = $L.GetType("System.Management.Automation.Language.$type"); $ast.FindAll({ param($n) $t.IsInstanceOfType($n) }.GetNewClosure(), $true) }
# Every command, also inside "$(...)" of a string; `& $path`, `& "...exe"` or `. $x` has no
# static name and is refused.
foreach ($c in All 'CommandAst') { $n = $c.GetCommandName(); if ($n) { $n } else { '(call-without-name)' } }
foreach ($t in @(All 'TypeExpressionAst') + @(All 'TypeConstraintAst')) { '[' + $t.TypeName.FullName + ']' }
# Script invocation by the engine, and environment other than the redirected LOCALAPPDATA.
foreach ($v in All 'VariableExpressionAst') {
  $p = $v.VariablePath.UserPath
  if (@('ExecutionContext', 'PSCmdlet') -contains $p -or ($p -like 'env:*' -and $p -ne 'env:LOCALAPPDATA')) { '(variable-' + $p + ')' }
}
# A literal absolute path could name the live station; only these two are known.
$allowed = @('D:\Github\wsjtx-rust', 'C:\ProgramData\WstxRust\deploy-authority')
foreach ($s in @(All 'StringConstantExpressionAst') + @(All 'ExpandableStringExpressionAst')) {
  foreach ($m in [regex]::Matches([string]$s.Value, '(?i)(?<![\w])[a-z]:\\[^''"`$\s]*|\\\\[^''"`$\s]+')) {
    if (-not ($allowed | Where-Object { $m.Value.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) { '(path-' + $m.Value + ')' }
  }
}
"""


def classify(script):
    """Return what the script uses (by the PowerShell parser) that the drill has not classified.

    The text of a here-string is not code: the Ctrl+C helper inside one runs only through
    Start-Process, which is mocked; the variables expanded into it are checked.
    """
    proc = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-Command", TOKENIZE], capture_output=True, text=True,
                          env=dict(os.environ, DRILL_SCRIPT=script), timeout=60)
    names = proc.stdout.split()
    if proc.returncode != 0 or not names or "PARSE-ERROR" in names:
        return ["(the script does not parse)"]
    return sorted({n for n in names if n not in MOCKED | LOCAL | TYPES})


class Sandbox:
    def __init__(self, root, script):
        self.root = root
        self.local = os.path.join(root, "LocalAppData")
        self.station = os.path.join(self.local, "WstxRust", "station")
        self.pkg = os.path.join(root, "pkg", COMMIT[:9])
        self.sentinel = os.path.join(root, "sentinel.txt")
        self.script = os.path.join(root, "station-update.ps1")
        shutil.copyfile(script, self.script)
        write(os.path.join(self.station, CURRENT[:9], "wstx-rust.exe"), b"current station image")
        write(os.path.join(self.station, "launcher.ps1"), "# launcher\n")
        write(os.path.join(self.station, "profiles", "ic7300", "station.json"), '{"profile": 1}')
        write_json(os.path.join(self.station, "active.json"),
                   {"version": CURRENT[:9], "source_commit": CURRENT, "previous": None, "switched_utc": "2026-11-01T00:00:00Z"})
        os.makedirs(os.path.join(self.station, "logs"), exist_ok=True)
        self.package()

    def package(self, commit=COMMIT, exe=b"candidate image"):
        """Write a package as make_package.py does."""
        pkg = self.pkg
        write(os.path.join(pkg, "package", "wstx-rust.exe"), exe)
        write(os.path.join(pkg, "package", "licenses", "COPYING"), "license text\n")
        files = [{"path": p, "sha256": sha256(os.path.join(pkg, "package", p))} for p in ("wstx-rust.exe", r"licenses\COPYING")]
        receipt = os.path.join(pkg, f"gate-receipt-{commit[:9]}.log")
        write(receipt, f"... suites, green\n   abc..{commit[:9]}  HEAD -> master\n")
        gates = {"source_commit": commit, "artifact_sha256": files[0]["sha256"], "status": "passed", "prepush_passed": True,
                 "gate_receipt": {"path": receipt, "sha256": sha256(receipt)}}
        self.write_gates(gates)
        self.manifest = {"source_commit": commit, "artifact_sha256": files[0]["sha256"], "package_files": files,
                         "gate_receipt_path": os.path.join(pkg, "gates.json"), "gate_receipt_sha256": sha256(os.path.join(pkg, "gates.json"))}
        self.write_manifest()

    def write_gates(self, gates, rehash=False):
        write_json(os.path.join(self.pkg, "gates.json"), gates)
        if rehash:
            self.manifest["gate_receipt_sha256"] = sha256(os.path.join(self.pkg, "gates.json"))
            self.write_manifest()

    def gates(self):
        with open(os.path.join(self.pkg, "gates.json"), encoding="utf-8") as f:
            return json.load(f)

    def write_manifest(self):
        write_json(os.path.join(self.pkg, "manifest.json"), self.manifest)

    def snapshot(self):
        """Every file and directory of the destination except logs\\, with its digest."""
        state = {}
        for dirpath, dirnames, filenames in os.walk(self.station):
            rel = os.path.relpath(dirpath, self.station)
            if rel == "logs" or rel.startswith("logs" + os.sep):
                continue
            state[rel + os.sep] = "dir"
            for name in filenames:
                state[os.path.join(rel, name)] = sha256(os.path.join(dirpath, name))
        return state

    def run(self, dry_run=False, env=None):
        if os.path.exists(self.sentinel):
            os.remove(self.sentinel)
        pre = os.path.join(self.root, "prelude.ps1")
        write(pre, PRELUDE)
        args = f"-Manifest '{os.path.join(self.pkg, 'manifest.json')}'" + (" -DryRun" if dry_run else "")
        command = f". '{pre}'; & '{self.script}' {args}; exit $LASTEXITCODE"
        child_env = {k: v for k, v in os.environ.items() if not k.startswith("DRILL_")}
        child_env.update({"LOCALAPPDATA": self.local, "DRILL_SENTINEL": self.sentinel, "DRILL_ON_MASTER": f"{COMMIT},{OLDER}"})
        child_env.update(env or {})
        proc = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
                              capture_output=True, text=True, encoding="utf-8", errors="replace", env=child_env, timeout=180)
        sentinels = []
        if os.path.exists(self.sentinel):
            with open(self.sentinel, encoding="utf-8") as f:
                sentinels = f.read().split()
        return proc.returncode, proc.stdout + proc.stderr, sentinels


def tamper_artifact(s):
    write(os.path.join(s.pkg, "package", "wstx-rust.exe"), b"tampered image")


def manifest_artifact(s):
    s.manifest["artifact_sha256"] = sha256_bytes(b"another image")
    s.write_manifest()


def gates_edited(s):
    g = s.gates()
    g["toolchain"] = "edited"
    s.write_gates(g)


def gates_field(field, value):
    def change(s):
        g = s.gates()
        g[field] = value
        s.write_gates(g, rehash=True)
    return change


def push_log_changed(s):
    path = s.gates()["gate_receipt"]["path"]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    write(path, text.replace("green", "red"))


def short_commit(s):
    s.manifest["source_commit"] = COMMIT[:9]
    s.write_manifest()


def file_path(value):
    def change(s):
        s.manifest["package_files"][1]["path"] = value
        s.write_manifest()
    return change


def receipt_outside(s):
    outside = os.path.join(s.root, "elsewhere.json")
    shutil.copyfile(os.path.join(s.pkg, "gates.json"), outside)
    s.manifest["gate_receipt_path"] = outside
    s.write_manifest()


def no_exe(s):
    s.manifest["package_files"] = [f for f in s.manifest["package_files"] if f["path"] != "wstx-rust.exe"]
    s.write_manifest()


def staged_differs(s):
    write(os.path.join(s.station, COMMIT[:9], "wstx-rust.exe"), b"something else staged")


def consistent_rewrite(s):
    """An agent replaces the executable and rewrites every record beside it consistently."""
    s.package(exe=b"replacement image built elsewhere")


def older_commit(s):
    s.package(commit=OLDER)


def nothing(s):
    pass


# (name, change, environment, expected message, outcome) where outcome is "refused",
# "dry-run accepted", "reaches stop" or "LIMIT accepted".
CASES = [
    ("intact package, -DryRun", nothing, {}, "dry run: nothing changed", "dry-run accepted"),
    ("intact package reaches the station stop", nothing, {}, "stop station", "reaches stop"),
    ("tampered artifact", tamper_artifact, {}, "Package file wstx-rust.exe does not match the manifest.", "refused"),
    ("manifest names another artifact", manifest_artifact, {}, "Manifest artifact_sha256 is not the packaged executable.", "refused"),
    ("gate record changed", gates_edited, {}, "Gate receipt missing or changed.", "refused"),
    ("gate record of another commit", gates_field("source_commit", OLDER), {}, "Gate receipt does not say the push gate passed", "refused"),
    ("gate record of another artifact", gates_field("artifact_sha256", "0" * 64), {}, "Gate receipt does not say the push gate passed", "refused"),
    ("gate record not passed", gates_field("status", "failed"), {}, "Gate receipt does not say the push gate passed", "refused"),
    ("push-gate log changed", push_log_changed, {}, "Push-gate log changed.", "refused"),
    ("commit not on GitHub master (unapproved)", nothing, {"DRILL_ON_MASTER": OLDER}, "is not on GitHub master.", "refused"),
    ("GitHub master unreachable", nothing, {"DRILL_FETCH_FAIL": "1"}, "git fetch of GitHub master failed.", "refused"),
    ("abbreviated commit", short_commit, {}, "Manifest source_commit is not a full commit id.", "refused"),
    ("package path escapes the package", file_path(r"..\..\escape.dll"), {}, "Path escapes", "refused"),
    # .NET refuses the stream syntax inside Safe-Child before its own check; the message is localized.
    ("package path names a stream", file_path("wstx-rust.exe:evil"), {}, '"GetFullPath"', "refused"),
    ("gate record outside the package", receipt_outside, {}, "Path escapes", "refused"),
    ("package without the executable", no_exe, {}, "Package has no wstx-rust.exe.", "refused"),
    ("wrong destination: firewall scope", nothing, {"DRILL_REMOTE": "192.168.0.99"}, "Firewall rule scope is", "refused"),
    ("wrong destination: task not on the launcher", nothing, {"DRILL_TASK_ARGS": r"-File C:\elsewhere\run.ps1"}, "setup-once.ps1 has not been run", "refused"),
    ("staged version differs from the package", staged_differs, {}, "differs from the package", "refused"),
    ("consistent rewrite of artifact and records (#32)", consistent_rewrite, {}, "dry run: nothing changed", "LIMIT accepted"),
    ("older commit on master (stale, #31)", older_commit, {}, "dry run: nothing changed", "LIMIT accepted"),
]

# With the deploy authority on (#31), station-update.ps1 carries the amendment of
# Project-Specifics.md#deployment-authority and asks the protected verifier first. The
# verifier's own refusals are tested in tests/test_authority.py; here the mock answers for it.
PROTECTED_TASK = {"DRILL_TASK_ARGS": r'-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramData\WstxRust\deploy-authority\protected-launcher.ps1"'}
APPROVAL_CASES = [
    ("authority on: approved package, -DryRun", nothing, PROTECTED_TASK, "dry run: nothing changed", "dry-run accepted"),
    ("authority on: approval missing or mismatched", nothing, dict(PROTECTED_TASK, DRILL_APPROVAL="refused"),
     "The operator has not approved this package.", "refused"),
]
AMENDMENT_MARK = "verify-approval.ps1"


def run_case(root, script, case):
    name, change, env, expect, outcome = case
    s = Sandbox(root, script)
    change(s)
    before = s.snapshot()
    dry = outcome in ("dry-run accepted", "LIMIT accepted")
    rc, out, sentinels = s.run(dry_run=dry, env=env)
    after = s.snapshot()
    problems = []
    if expect not in out:
        problems.append(f"expected message {expect!r} not shown")
    if outcome == "reaches stop":
        if "Stop-ScheduledTask" not in sentinels:
            problems.append("did not reach the station stop")
    else:
        if sentinels:
            problems.append(f"reached {sentinels}")
        if before != after:
            changed = sorted(set(before.items()) ^ set(after.items()))
            problems.append(f"destination changed: {[c[0] for c in changed][:5]}")
        if outcome == "refused" and rc == 0:
            problems.append("exit 0")
        if outcome != "refused" and rc != 0:
            problems.append(f"exit {rc}")
    return problems, out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--script", help="station-update.ps1 to drill (default: the shared resources copy)")
    parser.add_argument("--keep", help="keep the sandboxes in this directory")
    a = parser.parse_args(argv)
    try:
        script = a.script
        if not script:
            common = subprocess.run(["git", "-C", HERE, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                    capture_output=True, text=True, check=True).stdout.strip()
            script = os.path.join(common, "harness-parallel", "resources", "station-update", "station-update.ps1")
        open(script, "rb").close()
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"DRILL ERROR cannot read the install script: {e}")
        return 2
    unknown = classify(script)
    if unknown:
        print(f"DRILL ERROR {script} uses commands the drill has not classified: {', '.join(unknown)}; extend MOCKED or LOCAL after review")
        return 2
    print(f"drill of {script}\nsha256 {sha256(script)}")
    with open(script, encoding="utf-8-sig") as f:
        amended = AMENDMENT_MARK in f.read()
    cases = CASES + (APPROVAL_CASES if amended else [])
    if not amended:
        print("authority amendment not in the script: approval cases not applicable (deploy authority off)")
    base = a.keep or tempfile.mkdtemp(prefix="station-drill-")
    failures = 0
    try:
        for i, case in enumerate(cases):
            root = os.path.join(base, f"case{i:02d}")
            os.makedirs(root, exist_ok=True)
            problems, out = run_case(root, script, case)
            verdict = "ok  " if not problems else "FAIL"
            print(f"{verdict} {case[4]:<16} {case[0]}" + ("" if not problems else f": {'; '.join(problems)}"))
            if problems:
                failures += 1
                print("     " + out.strip().replace("\n", "\n     ")[-1500:])
    finally:
        if not a.keep:
            shutil.rmtree(base, ignore_errors=True)
    print(f"{len(cases) - failures}/{len(cases)} cases as expected")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
