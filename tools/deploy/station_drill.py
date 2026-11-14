"""Show each refusal of station-update.ps1 happening before the destination changes (#34, #171).

usage: python tools/deploy/station_drill.py [--script <station-update.ps1>] [--keep <dir>]

Runs the install script against a sandbox station (LOCALAPPDATA points into a temporary
directory) with every command that reaches the system replaced by a mock: the scheduled
task, the firewall rule, processes, the network, git, GitHub and the clock. Commands that
would change the system (start/stop the task, start/stop a process, web requests, posting on
GitHub, cr_state.py) record a sentinel and throw. Before running, the drill refuses a script
that uses a command, .NET type or call target it has not classified, `$ExecutionContext`, an
environment variable other than LOCALAPPDATA, or a literal absolute path other than the
repository (whose git is mocked; the drill passes a sandbox -Repo) and the protected
deploy-authority root. The one call without a static name it accepts is the dot-source of
`$AgentClient`, the package's agent client: in the drill that is the sandbox's fake client.
This keeps the commands the drill knows away from the live station; it is no sandbox against
code written to escape it, so read a changed script's diff before drilling it.

For each case it builds a package as make_package.py does (with the mechanism files under
deploy\\ and the script under test among them), gives the commit and the running commit their
deploy pins (a mocked `git show` of Project-Specifics.md), damages one thing, runs the
package's copy of the script and requires: a non-zero exit, the refusal's own message (a
refusal for another reason fails the case), no sentinel, and the sandbox station (version
directories, active.json, profiles, launcher) unchanged byte for byte; only logs\\ may change.
A busy station gives up with exit 3, a radio that does not answer with exit 6; a changed
mechanism (#196) is no refusal and reaches the stop, while a commit without pins, pins out of
order and a package file that differs from its pin refuse with exit 1. Positive controls show that the mocks do not refuse everything: the intact
package passes -DryRun unchanged, and without -DryRun it reaches the station stop. Cases
marked LIMIT are not refused today; they are reported so that the rule stays stated as
unmet (#31, #32) and fail the drill if that ever changes unnoticed.

Exit 0: every case as expected. Exit 1: a case differs. Exit 2: the drill could not run.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "station-update", "station-update.ps1")
POWERSHELL = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), r"System32\WindowsPowerShell\v1.0\powershell.exe")
CURRENT = "c" * 40
COMMIT = "1234567890" + "ab" * 15
OLDER = "0" * 40
PREVIOUS = "d" * 40
TASK = "WSTX Rust Station HB9BLA"
COMMENT_ID = "987654321"
# The removed parameter of the deploy that asked for an operator's OK (#196). Built from two
# parts: no tracked text but the test of TC-196-07 may state it.
REMOVED_PARAMETER = "-Ok" + "Comment"
# The mechanism files in pin order (docs/harness/Project-Specifics.md, Deploy pins).
MECHANISM = ("tools/deploy/station-update/station-update.ps1", "tools/deploy/station-update/make_package.py",
             "tools/deploy/station-update/launcher.ps1", "tools/deploy/agent-client.ps1",
             "tools/deploy/station-probe.ps1", "tools/deploy/live-page-check.ps1")
LAUNCHER = b"# drill: station launcher\n"

# Every Verb-Noun command the script may use. Mocked ones are replaced in the prelude; the
# rest only touch paths under the sandbox the script derives from LOCALAPPDATA, -Manifest and -Repo.
MOCKED = {"Get-ScheduledTask", "Start-ScheduledTask", "Stop-ScheduledTask", "Get-NetFirewallRule",
          "Get-NetFirewallAddressFilter", "Get-NetFirewallPortFilter", "Get-CimInstance", "Start-Process",
          "Stop-Process", "Invoke-WebRequest", "git", "powershell.exe", "gh", "python", "Get-Date", "Start-Sleep",
          "Open-AgentSession", "Agent-Get"}
LOCAL = {"Set-StrictMode", "Join-Path", "Split-Path", "Test-Path", "Get-Item", "Get-FileHash", "Get-ChildItem",
         "Copy-Item", "New-Item", "Remove-Item", "Rename-Item", "Get-Content", "Add-Content", "ConvertFrom-Json",
         "ConvertTo-Json", "Resolve-Path", "Write-Output", "Where-Object", "Out-Null", "Sort-Object",
         "Push-Location", "Pop-Location", "ForEach-Object", "(dot-source-agent-client)",
         "Safe-Child", "Station-Processes", "Assert-Setup", "Firewall-Scope", "Send-CtrlC", "Stop-Station",
         "Start-Ready", "Write-Active", "Save-Profile", "Restore-Profile", "Restore-Launcher", "Switch-Back", "Step",
         "Hash", "Now", "Read-Pins", "Pins-Text", "Issue-Skip", "Take-Lock", "Read-State", "Station-Busy",
         "Busy-Reason", "Clean", "Last-Line", "Move-Installed", "Issues-Named"}
# .NET types the script may name; file and path methods act on the same sandbox paths.
TYPES = {"[Convert]", "[DateTime]", "[IO.FileAttributes]", "[IO.File]", "[IO.Path]", "[NullString]", "[StringComparison]",
         "[Text.Encoding]", "[Text.UTF8Encoding]", "[bool]", "[int]", "[ordered]", "[string]", "[switch]",
         "[pscustomobject]", "[Globalization.CultureInfo]", "[regex]"}

# The scripted clock (Get-Date and Start-Sleep) and the busy station: DRILL_BUSY names one busy
# reason, which holds while the clock is less than DRILL_BUSY_UNTIL seconds past 12:00:00.
CLOCK = r"""
$global:DrillT0 = [DateTime]::new(2026, 11, 13, 12, 0, 0, [DateTimeKind]::Utc)
$global:DrillClock = $global:DrillT0
$global:DrillLock = $null; $global:DrillSecondDone = $false
function Drill-Busy($kind) {
  $until = if ($env:DRILL_BUSY_UNTIL) { [double]$env:DRILL_BUSY_UNTIL } else { 1e9 }
  $env:DRILL_BUSY -eq $kind -and ($global:DrillClock - $global:DrillT0).TotalSeconds -lt $until }
function Get-Date { $global:DrillClock }
function Start-Sleep { param($Seconds = 0, $Milliseconds = 0)
  $global:DrillClock = $global:DrillClock.AddSeconds([double]$Seconds).AddMilliseconds([double]$Milliseconds)
  if ($global:DrillLock -and -not (Drill-Busy 'lock')) { $global:DrillLock.Dispose(); $global:DrillLock = $null } }
if ($env:DRILL_BUSY -eq 'lock') { $global:DrillLock = [IO.File]::Open("$env:LOCALAPPDATA\WstxRust\station\logs\update.lock", 'OpenOrCreate', 'ReadWrite', 'None') }
"""

PRELUDE = CLOCK + r"""
$global:DrillSentinel = $env:DRILL_SENTINEL
function Drill-Mutation($name) { Add-Content -LiteralPath $global:DrillSentinel -Value $name; throw "DRILL-SENTINEL $name" }
function Get-ScheduledTask { param($TaskName)
  $a = if ($env:DRILL_TASK_ARGS) { $env:DRILL_TASK_ARGS } else { "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$env:LOCALAPPDATA\WstxRust\station\launcher.ps1`"" }
  [pscustomobject]@{ Actions = @([pscustomobject]@{ Arguments = $a }); State = 'Ready' } }
function Start-ScheduledTask { Drill-Mutation 'Start-ScheduledTask' }
function Stop-ScheduledTask { Drill-Mutation 'Stop-ScheduledTask' }
# A second update started at the stop, while the first holds update.lock (DRILL_SECOND).
function Start-Process {
  if ($env:DRILL_SECOND -and -not $global:DrillSecondDone) {
    $global:DrillSecondDone = $true
    $out = try { & $env:DRILL_SECOND_SCRIPT -Manifest $env:DRILL_SECOND_MANIFEST -Repo $env:DRILL_SECOND_REPO *>&1 | Out-String } catch { 'THREW ' + $_.Exception.Message }
    Set-Content -LiteralPath $env:DRILL_SECOND_OUT -Value ($out + "`nEXIT $LASTEXITCODE")
  }
  Drill-Mutation 'Start-Process' }
function Stop-Process { Drill-Mutation 'Stop-Process' }
function Invoke-WebRequest { Drill-Mutation 'Invoke-WebRequest' }
function Get-CimInstance { param($ClassName, $Filter)
  $n = if (Drill-Busy 'procs0') { 0 } elseif (Drill-Busy 'procs2') { 2 } else { 1 }
  for ($i = 0; $i -lt $n; $i++) { [pscustomobject]@{ ProcessId = 4242 + $i; ExecutablePath = "$env:LOCALAPPDATA\WstxRust\station\ccccccccc\wstx-rust.exe" } } }
function Get-NetFirewallRule { param($Name) [pscustomobject]@{ Enabled = 'True'; Direction = 'Inbound'; Action = 'Allow' } }
function Get-NetFirewallAddressFilter { process { [pscustomobject]@{ LocalAddress = '192.168.0.37'; RemoteAddress = $(if ($env:DRILL_REMOTE) { $env:DRILL_REMOTE } else { '192.168.0.6' }) } } }
function Get-NetFirewallPortFilter { process { [pscustomobject]@{ Protocol = 'TCP'; LocalPort = '18081' } } }
function git {
  if ($args -contains 'fetch') { $global:LASTEXITCODE = $(if ($env:DRILL_FETCH_FAIL) { 1 } else { 0 }); return }
  if ($args -contains 'merge-base') { $c = $args[$args.Count - 2]; $global:LASTEXITCODE = $(if (($env:DRILL_ON_MASTER -split ',') -contains $c) { 0 } else { 1 }); return }
  if ($args -contains 'show') {
    $spec = [string]$args[$args.Count - 1]; $i = $spec.IndexOf(':')
    $file = Join-Path (Join-Path $env:DRILL_GIT_STORE $spec.Substring(0, $i)) ($spec.Substring($i + 1) -replace '/', '\')
    if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file; $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 128 }
    return }
  Drill-Mutation "git $args" }
function gh { Drill-Mutation "gh $args" }
function python { Drill-Mutation "python $args" }
function powershell.exe {
  if (-not ($args -like '*\deploy-authority\verify-approval.ps1')) { Drill-Mutation "powershell.exe $args" }
  if ($env:DRILL_APPROVAL -eq 'refused') { 'REFUSED approval names artifact (drill)'; $global:LASTEXITCODE = 1 } else { 'APPROVED (drill)'; $global:LASTEXITCODE = 0 } }
"""

# The package's agent client in the sandbox: the station state the idle check reads.
FAKE_AGENT_CLIENT = r"""# drill: agent client
$AgentUrl = 'https://drill.invalid'
# The radio's state: DRILL_RADIO (default ready) while the clock is less than DRILL_RADIO_UNTIL
# seconds past 12:00:00; the value unreadable is a reply that cannot be read.
function Drill-Radio {
  $until = if ($env:DRILL_RADIO_UNTIL) { [double]$env:DRILL_RADIO_UNTIL } else { 1e9 }
  if ($env:DRILL_RADIO -and ($global:DrillClock - $global:DrillT0).TotalSeconds -lt $until) { $env:DRILL_RADIO } else { 'ready' } }
function Open-AgentSession { if (Drill-Busy 'unreadable') { throw [Net.WebException]::new('drill: state unreadable') }; [pscustomobject]@{ Session = $null } }
function Agent-Get($c, [string]$Route) {
  if (Drill-Busy 'unreadable') { throw [Net.WebException]::new('drill: state unreadable') }
  $t = [pscustomobject]@{ ptt = 'released'; transmitting = $false; transmit = [pscustomobject]@{ arm_state = 'disarmed'; last_disarm_cause = $null } }
  $contact = $null; $run = $null
  if (Drill-Busy 'armed') { $t.transmit.arm_state = 'armed' }
  if (Drill-Busy 'ptt') { $t.ptt = 'keyed' }
  if (Drill-Busy 'transmitting') { $t.transmitting = $true }
  if (Drill-Busy 'contact') { $contact = [pscustomobject]@{ state = 'replying' } }
  if (Drill-Busy 'device-lost') { $contact = [pscustomobject]@{ state = 'replying' }; $t.transmit.last_disarm_cause = 'device_lost' }
  if (Drill-Busy 'run') { $run = [pscustomobject]@{ state = 'waiting' } }
  switch ($Route) { '/transmit' { $t } '/contact' { [pscustomobject]@{ contact = $contact } } '/automation' { [pscustomobject]@{ run = $run } }
    '/radio' { $st = Drill-Radio; if ($st -eq 'unreadable') { throw [Net.WebException]::new('drill: radio reply unreadable') }; [pscustomobject]@{ state = $st } } }
}
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


def pins_text(pins, heading="### Deploy pins"):
    """A Project-Specifics.md whose Deploy pins section holds `pins` [(sha256, path)]."""
    lines = ["# Project-specific harness bindings", "", "## Deployment authority", "", heading, "", "```text"]
    lines += [f"{h}  {p}" for h, p in pins]
    lines += ["```", "", "## References", ""]
    return "\n".join(lines) + "\n"


TOKENIZE = r"""
$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput([IO.File]::ReadAllText($env:DRILL_SCRIPT), [ref]$tokens, [ref]$errs)
if ($errs.Count) { 'PARSE-ERROR'; exit 1 }
$L = [System.Management.Automation.Language.Ast].Assembly
function All($type) { $t = $L.GetType("System.Management.Automation.Language.$type"); $ast.FindAll({ param($n) $t.IsInstanceOfType($n) }.GetNewClosure(), $true) }
# Every command, also inside "$(...)" of a string; `& $path`, `& "...exe"` or `. $x` has no
# static name and is refused, except `. $AgentClient` (the package's agent client).
foreach ($c in All 'CommandAst') {
  $n = $c.GetCommandName()
  if ($n) { $n }
  elseif ($c.InvocationOperator -eq 'Dot' -and $c.CommandElements.Count -eq 1 -and $c.CommandElements[0] -is [System.Management.Automation.Language.VariableExpressionAst] -and $c.CommandElements[0].VariablePath.UserPath -eq 'AgentClient') { '(dot-source-agent-client)' }
  else { '(call-without-name)' }
}
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


def takes(script, name):
    """Whether the script's param() names -<name> (an older script is drilled without it)."""
    with open(script, encoding="utf-8-sig") as f:
        return re.search(r"(?im)^param\(.*\$" + name + r"\b", f.read()) is not None


class Sandbox:
    def __init__(self, root, script):
        self.root = root
        self.local = os.path.join(root, "LocalAppData")
        self.station = os.path.join(self.local, "WstxRust", "station")
        self.repo = os.path.join(root, "repo")
        self.store = os.path.join(root, "git-objects")
        self.pkg = os.path.join(root, "pkg", COMMIT[:9])
        self.sentinel = os.path.join(root, "sentinel.txt")
        with open(script, "rb") as f:
            self.script_bytes = f.read()
        self.run_script = None
        self.extra = []
        write(os.path.join(self.station, CURRENT[:9], "wstx-rust.exe"), b"current station image")
        write(os.path.join(self.station, "launcher.ps1"), LAUNCHER)
        write(os.path.join(self.station, "profiles", "ic7300", "station.json"), '{"profile": 1}')
        self.set_active(None)
        os.makedirs(os.path.join(self.station, "logs"), exist_ok=True)
        os.makedirs(os.path.join(self.repo, ".git", "harness-parallel", "radio"), exist_ok=True)
        self.package()
        self.pin(COMMIT)
        self.pin(CURRENT)

    @property
    def script(self):
        return os.path.join(self.pkg, "deploy", *MECHANISM[0].split("/"))

    def set_active(self, previous):
        write_json(os.path.join(self.station, "active.json"),
                   {"version": CURRENT[:9], "source_commit": CURRENT, "previous": previous, "switched_utc": "2026-11-01T00:00:00Z"})

    def mechanism(self):
        """The bytes of each mechanism file the package carries, as make_package.py copies them."""
        return {MECHANISM[0]: self.script_bytes, MECHANISM[1]: b"# drill: make_package.py\n", MECHANISM[2]: LAUNCHER,
                MECHANISM[3]: FAKE_AGENT_CLIENT.encode("utf-8"), MECHANISM[4]: b"# drill: station-probe.ps1\n",
                MECHANISM[5]: b"# drill: live-page-check.ps1\n"}

    def package(self, commit=COMMIT, exe=b"candidate image"):
        """Write a package as make_package.py does."""
        pkg = self.pkg
        write(os.path.join(pkg, "package", "wstx-rust.exe"), exe)
        write(os.path.join(pkg, "package", "licenses", "COPYING"), "license text\n")
        files = [{"path": p, "sha256": sha256(os.path.join(pkg, "package", p))} for p in ("wstx-rust.exe", r"licenses\COPYING")]
        deploy = []
        for path, data in self.mechanism().items():
            write(os.path.join(pkg, "deploy", *path.split("/")), data)
            deploy.append({"path": path, "sha256": sha256_bytes(data)})
        receipt = os.path.join(pkg, f"gate-receipt-{commit[:9]}.log")
        write(receipt, f"... suites, green\n   abc..{commit[:9]}  HEAD -> master\n")
        gates = {"source_commit": commit, "artifact_sha256": files[0]["sha256"], "status": "passed", "prepush_passed": True,
                 "gate_receipt": {"path": receipt, "sha256": sha256(receipt)}}
        self.write_gates(gates)
        self.manifest = {"source_commit": commit, "artifact_sha256": files[0]["sha256"], "package_files": files,
                         "deploy_files": deploy, "gate_receipt_path": os.path.join(pkg, "gates.json"),
                         "gate_receipt_sha256": sha256(os.path.join(pkg, "gates.json"))}
        self.write_manifest()

    def pins(self):
        """[(sha256, path)] of the package's mechanism files, in pin order."""
        return [(sha256(os.path.join(self.pkg, "deploy", *p.split("/"))), p) for p in MECHANISM]

    def pin(self, commit, pins=None, text=None):
        """Give `commit` a Project-Specifics.md (git show) with these pins (default: the package's)."""
        path = os.path.join(self.store, commit, "docs", "harness", "Project-Specifics.md")
        write(path, text if text is not None else pins_text(self.pins() if pins is None else pins))

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

    def command(self, script, dry_run=False, rollback=False):
        args = ["-Rollback"] if rollback else [f"-Manifest '{os.path.join(self.pkg, 'manifest.json')}'"] + (["-DryRun"] if dry_run else [])
        if takes(script, "Repo"):
            args.append(f"-Repo '{self.repo}'")
        args += self.extra
        return f"& '{script}' {' '.join(args)}"

    def env(self, env=None):
        child_env = {k: v for k, v in os.environ.items() if not k.startswith("DRILL_")}
        child_env.update({"LOCALAPPDATA": self.local, "DRILL_SENTINEL": self.sentinel, "DRILL_ON_MASTER": f"{COMMIT},{OLDER}",
                          "DRILL_GIT_STORE": self.store,
                          "DRILL_SECOND_SCRIPT": self.script, "DRILL_SECOND_MANIFEST": os.path.join(self.pkg, "manifest.json"),
                          "DRILL_SECOND_REPO": self.repo, "DRILL_SECOND_OUT": os.path.join(self.root, "second.txt")})
        child_env.update(env or {})
        return child_env

    def run(self, dry_run=False, env=None, rollback=False, prelude=PRELUDE):
        if os.path.exists(self.sentinel):
            os.remove(self.sentinel)
        pre = os.path.join(self.root, "prelude.ps1")
        write(pre, prelude)
        script = self.run_script or self.script
        # An error that ends the script (a throw, a parameter that does not bind) is exit 1: an
        # advanced script's terminating error does not stop the -Command by itself.
        command = f". '{pre}'; try {{ {self.command(script, dry_run, rollback)} }} catch {{ $_.Exception.Message; exit 1 }}; exit $LASTEXITCODE"
        proc = subprocess.run([POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command],
                              capture_output=True, text=True, encoding="utf-8", errors="replace", env=self.env(env), timeout=300)
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
    s.pin(OLDER)


def nothing(s):
    pass


def lease(s):
    write_json(os.path.join(s.repo, ".git", "harness-parallel", "radio", "lease.json"),
               {"holder": "drill-qso", "expires": "2099-01-01T00:00:00Z"})


def working_folder_copy(s):
    """A copy of the script outside the package, edited, as in a working folder."""
    s.run_script = os.path.join(s.root, "working-folder", "station-update.ps1")
    write(s.run_script, s.script_bytes + b"\n# edited in the working folder\n")


def package_file_edited(s):
    path = os.path.join(s.pkg, "deploy", *MECHANISM[3].split("/"))
    with open(path, "ab") as f:
        f.write(b"# edited after the build\n")


def running_pins_differ(s):
    pins = s.pins()
    pins[4] = ("0" * 64, pins[4][1])
    s.pin(CURRENT, pins)


def commit_without_pins(s):
    s.pin(COMMIT, text="# Project-specific harness bindings\n\n## Deployment authority\n\nNo pins.\n")


def running_without_pins(s):
    s.pin(CURRENT, text="# Project-specific harness bindings\n")


def station_launcher_differs(s):
    write(os.path.join(s.station, "launcher.ps1"), b"# another launcher\n")


def removed_parameter(s):
    """A call with the parameter that asked for an operator's OK before #196."""
    s.extra = [REMOVED_PARAMETER, COMMENT_ID]


def pins_in_another_order(s):
    s.pin(COMMIT, list(reversed(s.pins())))


def rollback_previous(s):
    write(os.path.join(s.station, PREVIOUS[:9], "wstx-rust.exe"), b"previous station image")
    s.set_active(PREVIOUS)


def rollback_with_other_pins(s):
    rollback_previous(s)
    running_pins_differ(s)


# (name, change, environment, expected messages, outcome) where outcome is "refused",
# "busy", "radio", "binding refused", "dry-run accepted", "reaches stop", "rollback reaches
# stop", "second refused" or "LIMIT accepted".
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

# TC-171-01: the deploy refuses a station that is not idle before it stops anything, and waits
# at most 300 s (10 s polls on the scripted clock from 12:00:00).
IDLE_CASES = [
    ("busy: update lock held", nothing, {"DRILL_BUSY": "lock"}, "the update lock is held", "busy"),
    ("busy: live radio lease", lease, {}, "drill-qso holds the radio lease", "busy"),
    ("busy: no station process", nothing, {"DRILL_BUSY": "procs0"}, "0 station processes are running", "busy"),
    ("busy: two station processes", nothing, {"DRILL_BUSY": "procs2"}, "2 station processes are running", "busy"),
    ("busy: transmit armed", nothing, {"DRILL_BUSY": "armed"}, "transmit is armed", "busy"),
    ("busy: PTT keyed", nothing, {"DRILL_BUSY": "ptt"}, "PTT is keyed", "busy"),
    ("busy: transmitting", nothing, {"DRILL_BUSY": "transmitting"}, "transmitting: True", "busy"),
    ("busy: contact replying", nothing, {"DRILL_BUSY": "contact"}, "a contact is replying", "busy"),
    ("busy: contact replying after a device_lost disarm", nothing, {"DRILL_BUSY": "device-lost"}, "a contact is replying", "busy"),
    ("busy: automation run active", nothing, {"DRILL_BUSY": "run"}, "an automation run is waiting", "busy"),
    ("busy: state unreadable", nothing, {"DRILL_BUSY": "unreadable"}, "its state cannot be read", "busy"),
    # TC-196-04 (a) to (e): the radio does not answer for 300 s; the run ends with exit 6.
    *[(f"radio {state}: waits, gives up with exit 6", nothing, {"DRILL_RADIO": state},
       [f"waiting for the radio (state {state})", "12:05:00 WAITING FOR THE RADIO"], "radio")
      for state in ("closed", "connecting", "closing", "unavailable", "unreadable")],
    ("radio ready from the first reading: proceeds", nothing, {"DRILL_RADIO": "ready"}, "stop station", "reaches stop"),
    ("radio ready from 290 s: proceeds", nothing, {"DRILL_RADIO": "closed", "DRILL_RADIO_UNTIL": "290"},
     ["12:04:40 waiting for the radio", "12:04:50 stop station"], "reaches stop"),
    ("transmit armed until 310 s and the radio closed: busy is read first", nothing,
     {"DRILL_BUSY": "armed", "DRILL_BUSY_UNTIL": "310", "DRILL_RADIO": "closed"},
     "12:05:00 BUSY: the station was not idle for 300 s", "busy"),
    ("busy clears at 290 s: proceeds", nothing, {"DRILL_BUSY": "armed", "DRILL_BUSY_UNTIL": "290"},
     ["12:04:40 waiting: transmit is armed", "12:04:50 stop station"], "reaches stop"),
    ("still busy at 300 s: gives up", nothing, {"DRILL_BUSY": "armed", "DRILL_BUSY_UNTIL": "310"},
     ["12:04:50 waiting: transmit is armed", "12:05:00 BUSY: the station was not idle for 300 s"], "busy"),
    ("second update between the check and the stop", nothing, {"DRILL_SECOND": "1"}, "stop station", "second refused"),
]

# TC-196-01 and TC-196-02 (#196): a changed mechanism needs no OK; the pins still guard the package.
PIN_CASES = [
    ("pins: all equal, -DryRun", nothing, {}, ["deploy mechanism equals its pins", "dry run: nothing changed"], "dry-run accepted"),
    ("pins: a working-folder copy of the script is not run", working_folder_copy, {}, "run the package's own copy", "refused"),
    ("pins: package file edited after the build", package_file_edited, {}, "tools/deploy/agent-client.ps1 differs from its pin", "refused"),
    ("pins: commit without pins", commit_without_pins, {}, "commit 123456789 has no deploy pins", "refused"),
    ("pins: pins in another order", pins_in_another_order, {}, "do not name the mechanism files in their order", "refused"),
    ("changed mechanism: new pins differ from the running pins", running_pins_differ, {},
     ["deploy mechanism changed: the pins of 123456789 differ from those of the running ccccccccc", "stop station"], "reaches stop"),
    ("changed mechanism: running commit without pins", running_without_pins, {},
     ["deploy mechanism changed: the running commit ccccccccc has no deploy pins", "stop station"], "reaches stop"),
    ("changed mechanism: station launcher differs from its pin", station_launcher_differs, {},
     ["deploy mechanism changed: the launcher in the station folder differs from its pin", "stop station"], "reaches stop"),
    ("the removed OK parameter stops at binding", removed_parameter, {}, REMOVED_PARAMETER.lstrip("-"), "binding refused"),
    ("rollback with differing pins never asks", rollback_with_other_pins, {}, "rollback: ccccccccc -> ddddddddd", "rollback reaches stop"),
    ("rollback with the radio closed never asks", rollback_previous, {"DRILL_RADIO": "closed"}, "rollback: ccccccccc -> ddddddddd", "rollback reaches stop"),
    ("dry run with the radio closed does not read it", nothing, {"DRILL_RADIO": "closed"}, "dry run: nothing changed", "dry-run accepted"),
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
STOP_SENTINELS = ("Start-Process", "Stop-ScheduledTask")


def run_case(root, script, case):
    name, change, env, expect, outcome = case
    s = Sandbox(root, script)
    change(s)
    before = s.snapshot()
    dry = outcome in ("dry-run accepted", "LIMIT accepted")
    rc, out, sentinels = s.run(dry_run=dry, env=env, rollback=outcome == "rollback reaches stop")
    after = s.snapshot()
    problems = []
    for text in [expect] if isinstance(expect, str) else expect:
        if text not in out:
            problems.append(f"expected message {text!r} not shown")
    if outcome in ("reaches stop", "rollback reaches stop", "second refused"):
        if not sentinels or sentinels[0] not in STOP_SENTINELS:
            problems.append(f"did not reach the station stop (sentinels {sentinels})")
        if outcome == "second refused":
            second = os.path.join(root, "second.txt")
            text = ""
            if os.path.exists(second):
                with open(second, encoding="utf-8", errors="replace") as f:
                    text = f.read()
            if "the update lock is held" not in text or "EXIT 3" not in text:
                problems.append(f"the second update was not refused for the held lock: {text[-300:]!r}")
    else:
        if sentinels:
            problems.append(f"reached {sentinels}")
        if before != after:
            changed = sorted(set(before.items()) ^ set(after.items()))
            problems.append(f"destination changed: {[c[0] for c in changed][:5]}")
        failing = ("refused", "busy", "radio", "binding refused")
        if outcome in failing and rc == 0:
            problems.append("exit 0")
        if outcome in ("refused", "binding refused") and rc != 1:
            problems.append(f"exit {rc}, not 1 (refused)")
        if outcome == "busy" and rc != 3:
            problems.append(f"exit {rc}, not 3 (busy)")
        if outcome == "radio" and rc != 6:
            problems.append(f"exit {rc}, not 6 (the radio did not answer)")
        if outcome == "binding refused" and "verify package" in out:
            problems.append("a step ran before the parameter was refused")
        if outcome not in failing and rc != 0:
            problems.append(f"exit {rc}")
    if any(line.startswith("Deploy " + "OK:") for line in out.splitlines()):
        problems.append("a Deploy OK line is printed")
    return problems, out


def run_cases(script, cases, base, report=print):
    """Run each case in its own sandbox under base; returns the number that differ."""
    failures = 0
    for i, case in enumerate(cases):
        root = os.path.join(base, f"case{i:02d}")
        os.makedirs(root, exist_ok=True)
        problems, out = run_case(root, script, case)
        verdict = "ok  " if not problems else "FAIL"
        report(f"{verdict} {case[4]:<21} {case[0]}" + ("" if not problems else f": {'; '.join(problems)}"))
        if problems:
            failures += 1
            report("     " + out.strip().replace("\n", "\n     ")[-1500:])
    return failures


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--script", help="station-update.ps1 to drill (default: tools/deploy/station-update/station-update.ps1)")
    parser.add_argument("--keep", help="keep the sandboxes in this directory")
    a = parser.parse_args(argv)
    try:
        script = a.script or SCRIPT
        open(script, "rb").close()
    except OSError as e:
        print(f"DRILL ERROR cannot read the install script: {e}")
        return 2
    unknown = classify(script)
    if unknown:
        print(f"DRILL ERROR {script} uses commands the drill has not classified: {', '.join(unknown)}; extend MOCKED or LOCAL after review")
        return 2
    print(f"drill of {script}\nsha256 {sha256(script)}")
    with open(script, encoding="utf-8-sig") as f:
        amended = AMENDMENT_MARK in f.read()
    cases = CASES + IDLE_CASES + PIN_CASES + (APPROVAL_CASES if amended else [])
    if not amended:
        print("authority amendment not in the script: approval cases not applicable (deploy authority off)")
    base = a.keep or tempfile.mkdtemp(prefix="station-drill-")
    try:
        failures = run_cases(script, cases, base)
    finally:
        if not a.keep:
            shutil.rmtree(base, ignore_errors=True)
    print(f"{len(cases) - failures}/{len(cases)} cases as expected")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
