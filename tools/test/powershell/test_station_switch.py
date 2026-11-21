"""station-switch.ps1: switches the station to SIM-IC7300 and back.

The station folder is a temporary fake (launcher, profiles, receipt) and everything that reaches
the system (station process, Ctrl+C helper, scheduled task, station HTTP) is a mock function; the
fake task "runs" the fake launcher: it reads its profile line and writes the receipt as
launcher.ps1 does. The build check reads a scratch git repository made here. No station, task,
COM port or network is touched.
"""
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

# The one copy of the PowerShell runner is tools/deploy/tests/pwsh.py.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "station-switch.ps1")
# The checkout: three folders above tools/test/powershell/.
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))

# The lines of tools/deploy/station-update/launcher.ps1 the switch reads and writes.
LAUNCHER = ("$ErrorActionPreference='Stop'\r\n"
            "$base=Join-Path $env:LOCALAPPDATA 'WstxRust\\station'\r\n"
            "$env:WSTX_TOKEN='x'\r\n"
            "$env:WSTX_TLS_CERT='c.pem';$env:WSTX_TLS_KEY='k.pem'\r\n"
            "$stationProfilePath=Join-Path $base 'profiles\\ic7300';$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd')\r\n"
            "$child=Start-Process -FilePath $exe\r\n")
# The removed switch variables a launcher may still name; the station does not read them.
REMOVED = [f"WSTX_{name}" for name in ("RADIO_DISCOVERY", "UDP", "PSKR")]
OLD_LINE = ";".join(f"$env:{name}='off'" for name in REMOVED)
IDS = {"ic7300": "11111111-0000-0000-0000-000000000000", "SIM-IC7300": "50a24529-f7d9-4dcb-b555-77d652d771b6"}
SIM = os.path.join("profiles", "SIM-IC7300")


def git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, text=True).stdout.strip()


def prelude(log, running=True, runs=None, touches_logbook=False, device="COM4", headers=None, stops=99,
            pskr=None, garble=""):
    """`runs`: the profile the fake station starts whatever the launcher says (None: the launcher's).
    `headers`: the x-wstx-source-commit values GET / answers with. `stops`: how many Ctrl+C reach
    the station. `pskr`: GET /pskr's enabled whatever pskr.json says. `garble`: a file whose
    read-back differs from what was written."""
    header = "@(" + ",".join(pwsh.ps_quote(h) for h in headers) + ")"
    forced_pskr = "$null" if pskr is None else ("$true" if pskr else "$false")
    return f"""
$global:Log = {pwsh.ps_quote(log)}
function Note($t) {{ Add-Content -LiteralPath $global:Log -Value $t }}
$global:Up = ${running}
$global:Pid0 = 4242
$global:Stops = {stops}
$global:ForcedPskr = {forced_pskr}
function Get-CimInstance {{ param($ClassName,$Filter)
  if ($global:Up) {{ [pscustomobject]@{{ProcessId=$global:Pid0; ExecutablePath=(Join-Path $env:FAKE_STATION 'abc\\wstx-rust.exe')}} }} }}
function Start-Process {{ param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait)
  Note 'ctrl-c'; if ($global:Stops -gt 0) {{ $global:Stops--; $global:Up = $false }}; [pscustomobject]@{{ExitCode=0}} }}
function Stop-ScheduledTask {{ param($TaskName,$ErrorAction) Note 'task-stop' }}
function Get-ScheduledTask {{ param($TaskName) [pscustomobject]@{{State='Ready'}} }}
function Invoke-WebRequest {{ param($Uri,[switch]$UseBasicParsing,$TimeoutSec)
  [pscustomobject]@{{StatusCode=200; Headers=@{{'x-wstx-source-commit'={header}}}}} }}
function Get-Content {{ param($LiteralPath,[switch]$Raw,$Encoding)
  $text = Microsoft.PowerShell.Management\\Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8
  if ({pwsh.ps_quote(garble)} -and $LiteralPath.EndsWith({pwsh.ps_quote(garble)})) {{ $text + ' ' }} else {{ $text }} }}
function Start-ScheduledTask {{ param($TaskName)
  Note 'task-start'
  $text = [IO.File]::ReadAllText((Join-Path $env:FAKE_STATION 'launcher.ps1'))
  $name = [regex]::Match($text, "profiles\\\\([^'\\\\]+)'").Groups[1].Value
  $forced = {pwsh.ps_quote(runs or '')}
  if ($forced) {{ $name = $forced }}
  $global:Running = $name
  $global:Pid0 = $global:Pid0 + 1; $global:Up = $true
  if (${touches_logbook}) {{ Add-Content -LiteralPath (Join-Path $env:FAKE_STATION 'profiles\\ic7300\\contacts.adi') -Value '<call:5>G4BTY <eor>' }}
  $receipt = [ordered]@{{profile=(Join-Path $env:FAKE_STATION ('profiles\\' + $name)); process_id=$global:Pid0; source_commit=$env:FAKE_COMMIT}}
  [IO.File]::WriteAllText((Join-Path $env:FAKE_STATION 'station-running.json'), ($receipt | ConvertTo-Json))
}}
$global:Running = 'ic7300'
$global:Device = {pwsh.ps_quote(device)}
"""


class StationSwitchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # A scratch checkout: an older build without radio-discovery.json, then the current one.
        cls.repo_dir = tempfile.TemporaryDirectory()
        cls.repo = cls.repo_dir.name
        git(cls.repo, "init", "-q")
        source = os.path.join(cls.repo, "server", "src", "radioControl", "radio_setup.rs")
        os.makedirs(os.path.dirname(source))
        for text, label in (("// discovery without a setting\n", "old"),
                            ('pub(crate) const DISCOVERY_FILE: &str = "radio-discovery.json";\n', "new")):
            with open(source, "w", encoding="utf-8") as f:
                f.write(text)
            git(cls.repo, "add", "-A")
            git(cls.repo, "-c", "user.name=bench", "-c", "user.email=bench@localhost", "-c", "commit.gpgsign=false", "commit", "-q", "-m", label)
            setattr(cls, label.upper(), git(cls.repo, "rev-parse", "HEAD"))

    @classmethod
    def tearDownClass(cls):
        cls.repo_dir.cleanup()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.write("launcher.ps1", LAUNCHER)
        self.profile("ic7300", "icom7300://COM3?baud=115200&radio=94&controller=e0")
        self.write(os.path.join("profiles", "ic7300", "contacts.adi"), "<call:6>HB9BLA <eor>\n")
        self.profile("SIM-IC7300", "icom7300://COM4?baud=115200&radio=94&controller=e0")
        self.receipt(self.NEW)
        self.pin = os.path.join(self.tmp.name, "pin-launcher.ps1")
        with open(self.pin, "w", encoding="utf-8", newline="") as f:
            f.write(LAUNCHER)
        self.log = os.path.join(self.tmp.name, "system.log")
        self.client = os.path.join(self.tmp.name, "client.ps1")
        self.set_client()

    def tearDown(self):
        for top, _, files in os.walk(self.tmp.name):
            for name in files:
                os.chmod(os.path.join(top, name), stat.S_IWRITE | stat.S_IREAD)
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.station, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)

    def read(self, rel):
        with open(os.path.join(self.station, rel), encoding="utf-8", newline="") as f:
            return f.read()

    def exists(self, rel):
        return os.path.exists(os.path.join(self.station, rel))

    def read_only(self, rel):
        os.chmod(os.path.join(self.station, rel), stat.S_IREAD)

    def profile(self, name, endpoint):
        self.write(os.path.join("profiles", name, "profile.json"),
                   json.dumps({"profile_id": IDS[name], "control": {"mode": "cat", "endpoint": endpoint, "ptt": "cat"}}))

    def receipt(self, commit, process_id=4242):
        self.write("station-running.json", json.dumps({"profile": os.path.join(self.station, "profiles", "ic7300"),
                                                       "process_id": process_id, "source_commit": commit}))

    def set_client(self, contact="idle"):
        with open(self.client, "w", encoding="utf-8") as f:
            f.write(f"""function Open-AgentSession {{ [pscustomobject]@{{}} }}
function Agent-Get($c, $Route) {{
  if ($Route -eq '/transmit') {{ return [pscustomobject]@{{ptt='released'; transmitting=$false}} }}
  if ($Route -eq '/contact') {{ return [pscustomobject]@{{contact=[pscustomobject]@{{state='{contact}'; dx_call='G4BTY'}}}} }}
  $dir = Join-Path $env:FAKE_STATION ('profiles\\' + $global:Running)
  if ($Route -eq '/pskr') {{
    if ($null -ne $global:ForcedPskr) {{ return [pscustomobject]@{{enabled=$global:ForcedPskr}} }}
    $file = Join-Path $dir 'pskr.json'
    $enabled = if (Test-Path -LiteralPath $file) {{ ([IO.File]::ReadAllText($file) | ConvertFrom-Json).enabled }} else {{ $true }}
    return [pscustomobject]@{{enabled=$enabled}} }}
  $p = [IO.File]::ReadAllText((Join-Path $dir 'profile.json')) | ConvertFrom-Json
  [pscustomobject]@{{profile_id=$p.profile_id; state='ready'; device_id=$global:Device}} }}
""")

    def switch(self, *args, repo=None, commit=None, **station):
        commit = self.NEW if commit is None else commit
        station.setdefault("headers", [commit])
        return pwsh.run(TOOL, [*args, "-Station", self.station, "-AgentClient", self.client, "-Pin", self.pin,
                               "-Repo", repo or self.repo, "-ReadBackSeconds", "4"],
                        prelude(self.log, **station), env={"FAKE_STATION": self.station, "FAKE_COMMIT": commit})

    def system(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return f.read().splitlines()

    def snapshot(self):
        out = {}
        for top, _, files in os.walk(self.station):
            for name in files:
                path = os.path.join(top, name)
                with open(path, "rb") as f:
                    out[os.path.relpath(path, self.station)] = hashlib.sha256(f.read()).hexdigest()
        return out

    def operator_files(self):
        return {k: v for k, v in self.snapshot().items() if k.startswith(os.path.join("profiles", "ic7300"))}

    def in_order(self, out, *marks):
        at = [out.find(m) for m in marks]
        self.assertNotIn(-1, at, f"{marks}: {out}")
        self.assertEqual(at, sorted(at), out)

    def files(self, use=True, revision=0):
        q = json.dumps(IDS["SIM-IC7300"])
        return {"pskr.json": '{"schema_version":2,"profile_id":' + q + ',"enabled":false,"use":' + ("true" if use else "false") + '}',
                "radio-discovery.json": '{"schema_version":1,"profile_id":' + q + ',"at_start":false}',
                "udp.json": '{"schema_version":1,"profile_id":' + q + ',"revision":' + str(revision) + ',"targets":[]}'}

    BACKUP = "launcher.ps1.before-simulator"
    REFUSED = "does not read radio-discovery.json: nothing switched"

    def test_dry_run_prints_every_step_and_changes_nothing(self):
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator", "-DryRun")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH DRY-RUN", out)
        self.in_order(out, "build check: the running build", "would: back up the launcher", "would: stop the station gracefully",
                      "would: write profiles\\SIM-IC7300\\pskr.json", "would: write profiles\\SIM-IC7300\\radio-discovery.json",
                      "would: write profiles\\SIM-IC7300\\udp.json", "would: point the launcher at profiles\\SIM-IC7300",
                      "would: start the task", "would: read back", "would: hash the ic7300 profile")
        self.assertIn("before: ic7300\\contacts.adi sha256", out)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.system(), [], "no stop, no task")

    def test_dry_run_runs_the_build_check(self):
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator", "-DryRun", commit=self.OLD)
        self.assertEqual(rc, 2, out)
        self.assertIn(f"SWITCH ERROR the running build {self.OLD} {self.REFUSED}", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def test_dry_run_back_changes_nothing(self):
        self.assertEqual(self.switch("-To", "simulator")[0], 0)
        before = self.snapshot()
        os.unlink(self.log)
        rc, out = self.switch("-To", "back", "-DryRun")
        self.assertEqual(rc, 0, out)
        self.assertIn("would: write the backup", out)
        self.assertIn("would: start the task", out)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.system(), [])

    def test_simulator_checks_the_build_stops_writes_starts_and_reads_back_in_order(self):
        self.write("launcher.ps1", LAUNCHER.replace("$stationProfilePath", OLD_LINE + "\r\n$stationProfilePath"))
        operator = self.operator_files()
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH PASS the station runs profiles\\SIM-IC7300", out)
        self.in_order(out, f"build check: the running build {self.NEW} reads radio-discovery.json",
                      "step: stop the station", "step: write profiles\\SIM-IC7300\\pskr.json",
                      "step: write profiles\\SIM-IC7300\\radio-discovery.json", "step: write profiles\\SIM-IC7300\\udp.json",
                      "step: point the launcher", "step: start the task", "read back: GET /radio", "read back: GET /pskr enabled False")
        self.assertIn(f"GET /radio profile_id {IDS['SIM-IC7300']}, state ready", out)
        for name, text in self.files().items():
            self.assertEqual(self.read(os.path.join(SIM, name)), text, name)
        launcher = self.read("launcher.ps1")
        self.assertEqual(launcher, LAUNCHER.replace("'profiles\\ic7300'", "'profiles\\SIM-IC7300'"),
                         "the profile line follows, the switch lines go, the token and TLS lines stay")
        for name in REMOVED:
            self.assertNotIn(name, launcher)
        self.assertEqual(self.system(), ["ctrl-c", "task-stop", "task-start"])
        self.assertEqual(self.operator_files(), operator, "nothing is written in profiles\\ic7300")
        self.assertIn("after: ic7300\\profile.json sha256", out)

    def test_an_existing_use_false_is_kept(self):
        self.write(os.path.join(SIM, "pskr.json"),
                   json.dumps({"schema_version": 2, "profile_id": IDS["SIM-IC7300"], "enabled": True, "use": False}))
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.read(os.path.join(SIM, "pskr.json")), self.files(use=False)["pskr.json"])

    def test_a_pskr_file_of_another_profile_gets_use_true(self):
        self.write(os.path.join(SIM, "pskr.json"),
                   json.dumps({"schema_version": 2, "profile_id": IDS["ic7300"], "enabled": True, "use": False}))
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.read(os.path.join(SIM, "pskr.json")), self.files()["pskr.json"])

    def test_a_second_switch_keeps_the_first_backup(self):
        self.assertEqual(self.switch("-To", "simulator")[0], 0)
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertIn("the backup is not taken again", out)
        self.assertEqual(self.read(self.BACKUP), LAUNCHER, "the backup stays the operator's launcher")

    def test_back_restores_the_backup_and_reads_back_the_operator_profile(self):
        self.assertEqual(self.switch("-To", "simulator")[0], 0)
        os.unlink(self.log)
        sim_files = {k: v for k, v in self.snapshot().items() if k.startswith(SIM)}
        rc, out = self.switch("-To", "back")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH PASS the station runs profiles\\ic7300", out)
        self.assertEqual(self.read("launcher.ps1"), LAUNCHER)
        self.assertFalse(self.exists(self.BACKUP))
        self.assertEqual(self.system(), ["ctrl-c", "task-stop", "task-start"])
        self.assertEqual({k: v for k, v in self.snapshot().items() if k.startswith(SIM)}, sim_files, "back writes no profile")

    def test_back_without_a_backup_writes_the_pinned_launcher(self):
        self.write("launcher.ps1", LAUNCHER.replace("'profiles\\ic7300'", "'profiles\\SIM-IC7300'"))
        rc, out = self.switch("-To", "back")
        self.assertEqual(rc, 0, out)
        self.assertIn("pinned launcher", out)
        self.assertEqual(self.read("launcher.ps1"), LAUNCHER)

    def test_back_refuses_a_source_that_starts_the_simulator(self):
        self.write(self.BACKUP, LAUNCHER.replace("'profiles\\ic7300'", "'profiles\\SIM-IC7300'"))
        before = self.snapshot()
        rc, out = self.switch("-To", "back")
        self.assertEqual(rc, 2, out)
        self.assertIn("not the operator profile", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def test_no_simulator_profile_is_refused_and_nothing_changes(self):
        shutil.rmtree(os.path.join(self.station, SIM))
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 2, out)
        self.assertIn("does not exist", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def test_a_simulator_profile_on_com3_is_refused(self):
        self.profile("SIM-IC7300", "icom7300://COM3?baud=115200&radio=94&controller=e0")
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 2, out)
        self.assertIn("COM3", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def test_a_station_in_use_is_not_touched(self):
        self.set_client(contact="report")
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 3, out)
        self.assertIn("SWITCH BUSY", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def test_an_update_in_progress_is_not_touched(self):
        before = self.snapshot()
        with open(os.path.join(self.station, "logs", "update.lock"), "w"):
            rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 3, out)
        self.assertEqual(self.system(), [])
        self.assertEqual(self.read("launcher.ps1"), LAUNCHER)
        self.assertEqual({k: v for k, v in self.snapshot().items() if "update.lock" not in k}, before)

    def test_each_build_the_check_refuses_switches_nothing(self):
        unheld = "0123456789abcdef0123456789abcdef01234567"
        not_a_repo = os.path.join(self.tmp.name, "no-repo")
        os.makedirs(not_a_repo)
        cases = {
            "no station running": ({"running": False}, "unknown"),
            "no header": ({"headers": []}, "unknown"),
            "a repeated header": ({"headers": [self.NEW, self.NEW]}, "unknown"),
            "a header that is no commit": ({"headers": ["unknown"]}, "unknown"),
            "header and receipt differ": ({"headers": [self.OLD]}, self.OLD),
            "a commit the checkout does not hold": ({"commit": unheld}, unheld),
            "a git that fails": ({"repo": not_a_repo}, self.NEW),
            "an older build": ({"commit": self.OLD}, self.OLD),
        }
        for label, (station, shown) in cases.items():
            with self.subTest(label):
                if os.path.exists(self.log):
                    os.unlink(self.log)
                self.receipt(station.get("commit", self.NEW))
                before = self.snapshot()
                rc, out = self.switch("-To", "simulator", **station)
                self.assertEqual(rc, 2, out)
                self.assertIn(f"SWITCH ERROR the running build {shown} {self.REFUSED}", out)
                self.assertEqual(self.system(), [], "no stop")
                self.assertEqual(self.snapshot(), before, "no file written, launcher and backup untouched")
                self.assertFalse(self.exists(self.BACKUP))

    def test_a_stop_that_fails_writes_nothing(self):
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator", stops=0)
        self.assertEqual(rc, 2, out)
        self.assertIn("SWITCH ERROR THE STATION: the station did not stop", out)
        after = {k: v for k, v in self.snapshot().items() if k != self.BACKUP}
        self.assertEqual(after, before, "no profile file and no launcher written")
        self.assertNotIn("task-start", self.system())

    def test_a_failed_write_or_read_back_leaves_the_station_stopped_and_the_launcher_unchanged(self):
        for name in ("pskr.json", "radio-discovery.json", "udp.json", "launcher.ps1"):
            for how in ("write", "read-back"):
                with self.subTest(f"{name} {how}"):
                    self.tearDown()
                    self.setUp()
                    rel = name if name == "launcher.ps1" else os.path.join(SIM, name)
                    if name == "udp.json":
                        self.udp("192.168.0.10:22370")
                    garble = ""
                    if how == "write":
                        if not self.exists(rel):
                            self.write(rel, "{}")
                        self.read_only(rel)
                    else:
                        garble = name
                    rc, out = self.switch("-To", "simulator", garble=garble)
                    self.assertEqual(rc, 2, out)
                    self.assertIn(f"SWITCH ERROR THE STATION IS STOPPED: {name}: ", out)
                    self.assertEqual(self.system(), ["ctrl-c", "task-stop"], "stopped, not started")
                    self.assertEqual(self.read("launcher.ps1"), LAUNCHER, "the launcher holds its old text")

    def test_a_read_back_difference_after_the_start_stops_the_station(self):
        cases = {
            "GET /pskr enabled true": ({"pskr": True}, "GET /pskr shows enabled True, not false"),
            "GET /radio of another profile": ({"runs": "ic7300"}, f"runs profile {IDS['ic7300']}, not SIM-IC7300"),
            "a changed operator hash": ({"touches_logbook": True}, "ic7300\\contacts.adi changed"),
            "a station on COM3": ({"device": "COM3"}, "real radio's port"),
        }
        for label, (station, why) in cases.items():
            with self.subTest(label):
                self.tearDown()
                self.setUp()
                rc, out = self.switch("-To", "simulator", **station)
                self.assertEqual(rc, 2, out)
                self.assertIn("SWITCH ERROR THE STATION IS STOPPED: ", out)
                self.assertIn(why, out)
                self.assertEqual(self.system(), ["ctrl-c", "task-stop", "task-start", "ctrl-c", "task-stop"],
                                 "a stop after the start; no station runs")

    def test_a_read_back_difference_whose_stop_fails_names_both(self):
        rc, out = self.switch("-To", "simulator", pskr=True, stops=1)
        self.assertEqual(rc, 2, out)
        self.assertIn("SWITCH ERROR THE STATION: GET /pskr shows enabled True, not false; it was not stopped: the station did not stop", out)

    def test_only_simulator_or_back(self):
        for args in ((), ("-To", "ic7300"), ("-To", "")):
            rc, out = self.switch(*args)
            self.assertEqual(rc, 2, f"{args}: {out}")
            self.assertIn("need -To simulator or -To back", out)
        self.assertEqual(self.system(), [])

    def test_without_agent_client_and_pin_the_checkouts_own_files_are_used(self):
        # The defaults resolve tools/deploy/ from the repository root. -To back
        # -DryRun with the station stopped reads the pin and changes nothing.
        self.write("launcher.ps1", LAUNCHER.replace("'profiles\\ic7300'", "'profiles\\SIM-IC7300'"))
        seen = os.path.join(self.tmp.name, "seen.txt")
        hook = (f"\nSet-PSBreakpoint -Command Launcher-Profile -Action {{ "
                f"Add-Content -LiteralPath {pwsh.ps_quote(seen)} -Value $AgentClient; "
                f"Add-Content -LiteralPath {pwsh.ps_quote(seen)} -Value $Pin }} | Out-Null\n")
        before = self.snapshot()
        rc, out = pwsh.run(TOOL, ["-To", "back", "-DryRun", "-Station", self.station],
                           prelude(self.log, running=False, headers=[]) + hook, env={"FAKE_STATION": self.station})
        self.assertEqual(rc, 0, out)
        with open(seen, encoding="utf-8-sig") as f:
            client, pin = f.read().splitlines()[:2]
        expected = (os.path.join(REPO, "tools", "deploy", "agent-client.ps1"),
                    os.path.join(REPO, "tools", "deploy", "station-update", "launcher.ps1"))
        self.assertEqual((os.path.normcase(client), os.path.normcase(pin)), tuple(os.path.normcase(e) for e in expected))
        for path in (client, pin):
            self.assertTrue(os.path.isfile(path), path)
        self.assertIn(f"pinned launcher {pin}", out)
        self.assertEqual((self.snapshot(), self.system()), (before, []))

    def udp(self, *addresses, raw=None, revision=1):
        doc = raw if raw is not None else json.dumps({"profile_id": IDS["SIM-IC7300"], "revision": revision, "schema_version": 1,
                                                      "targets": [{"address": a, "enabled": True, "messages": ["qso_logged"]}
                                                                  for a in addresses]})
        self.write(os.path.join(SIM, "udp.json"), doc)

    def test_a_udp_file_whose_targets_are_all_loopback_listeners_is_kept(self):
        self.udp("127.0.0.1:22370", "127.0.0.1:22371")
        kept = self.read(os.path.join(SIM, "udp.json"))
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertIn("UDP kept: every target of the simulator profile is on 127.0.0.1", out)
        self.assertNotIn("write profiles\\SIM-IC7300\\udp.json", out)
        self.assertEqual(self.read(os.path.join(SIM, "udp.json")), kept)

    def test_udp_targets_are_emptied_for_each_target_that_is_not_a_loopback_listener(self):
        cases = {
            "another address": (("192.168.0.10:22370",), "is not on 127.0.0.1"),
            "the logger port": (("127.0.0.1:2237",), "on the operator logger's port 2237"),
            "a mix": (("127.0.0.1:22370", "192.168.0.10:2237"), "is not on 127.0.0.1"),
            "a name for loopback": (("localhost:22370",), "is not on 127.0.0.1"),
            "no port": (("127.0.0.1",), "is not on 127.0.0.1"),
            "no target": ((), "udp.json has no target"),
        }
        for label, (addresses, why) in cases.items():
            with self.subTest(label):
                self.write("launcher.ps1", LAUNCHER)
                self.udp(*addresses, revision=7)
                rc, out = self.switch("-To", "simulator")
                self.assertEqual(rc, 0, out)
                self.assertIn("UDP targets emptied: ", out)
                self.assertIn(why, out)
                self.assertEqual(self.read(os.path.join(SIM, "udp.json")), self.files(revision=8)["udp.json"])

    def test_udp_targets_are_emptied_at_revision_0_without_a_readable_udp_file(self):
        for label, raw in (("no file", None), ("not JSON", "{not json")):
            with self.subTest(label):
                path = os.path.join(self.station, SIM, "udp.json")
                if raw is None:
                    if os.path.exists(path):
                        os.unlink(path)
                else:
                    self.udp(raw=raw)
                rc, out = self.switch("-To", "simulator")
                self.assertEqual(rc, 0, out)
                self.assertIn("UDP targets emptied: ", out)
                self.assertEqual(self.read(os.path.join(SIM, "udp.json")), self.files(revision=0)["udp.json"])

    def test_the_script_writes_only_the_launcher_and_the_simulator_profile_and_opens_no_port(self):
        with open(TOOL, encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("SerialPort", text)
        self.assertNotIn("Set-Content", text)
        writes = [line for line in text.splitlines()
                  if "WriteAllText" in line or "Write-Checked" in line or "Copy-Item" in line or "Remove-Item" in line]
        for line in writes:
            self.assertRegex(line, r"\$launcher|\$backup|\$simDir|\$path, \$text|function Write-Checked", line)
            self.assertNotIn("ic7300", line, line)


if __name__ == "__main__":
    unittest.main()
