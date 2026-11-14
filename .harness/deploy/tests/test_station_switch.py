"""station-switch.ps1: switches the station to SIM-IC7300 and back (harness#114).

The station folder is a temporary fake (launcher, profiles, receipt) and everything that reaches
the system (station process, Ctrl+C helper, scheduled task, station HTTP) is a mock function; the
fake task "runs" the fake launcher: it reads its profile line and writes the receipt as
launcher.ps1 does. No station, task, COM port or network is touched.
"""
import hashlib
import json
import os
import sys
import tempfile
import unittest

# The one copy of the PowerShell runner is tools/deploy/tests/pwsh.py.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tools", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(HERE, "station-switch.ps1")

# The lines of tools/deploy/station-update/launcher.ps1 the switch reads and writes.
LAUNCHER = ("$ErrorActionPreference='Stop'\r\n"
            "$base=Join-Path $env:LOCALAPPDATA 'WstxRust\\station'\r\n"
            "$env:WSTX_TOKEN='x'\r\n"
            "$stationProfilePath=Join-Path $base 'profiles\\ic7300';$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd')\r\n"
            "$child=Start-Process -FilePath $exe\r\n")
ENV_LINE = "$env:WSTX_RADIO_DISCOVERY='off';$env:WSTX_UDP='off';$env:WSTX_PSKR='off'"
IDS = {"ic7300": "11111111-0000-0000-0000-000000000000", "SIM-IC7300": "50a24529-f7d9-4dcb-b555-77d652d771b6"}


def prelude(log, running=True, runs=None, touches_logbook=False, device="COM4"):
    """`runs`: the profile the fake station starts whatever the launcher says (None: the launcher's)."""
    return f"""
$global:Log = {pwsh.ps_quote(log)}
function Note($t) {{ Add-Content -LiteralPath $global:Log -Value $t }}
$global:Up = ${running}
$global:Pid0 = 4242
function Get-CimInstance {{ param($ClassName,$Filter)
  if ($global:Up) {{ [pscustomobject]@{{ProcessId=$global:Pid0; ExecutablePath=(Join-Path $env:FAKE_STATION 'abc\\wstx-rust.exe')}} }} }}
function Start-Process {{ param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait)
  Note 'ctrl-c'; $global:Up = $false; [pscustomobject]@{{ExitCode=0}} }}
function Stop-ScheduledTask {{ param($TaskName,$ErrorAction) Note 'task-stop' }}
function Get-ScheduledTask {{ param($TaskName) [pscustomobject]@{{State='Ready'}} }}
function Start-ScheduledTask {{ param($TaskName)
  Note 'task-start'
  $text = [IO.File]::ReadAllText((Join-Path $env:FAKE_STATION 'launcher.ps1'))
  $name = [regex]::Match($text, "profiles\\\\([^'\\\\]+)'").Groups[1].Value
  $forced = {pwsh.ps_quote(runs or '')}
  if ($forced) {{ $name = $forced }}
  $global:Running = $name
  $global:Pid0 = $global:Pid0 + 1; $global:Up = $true
  if (${touches_logbook}) {{ Add-Content -LiteralPath (Join-Path $env:FAKE_STATION 'profiles\\ic7300\\contacts.adi') -Value '<call:5>G4BTY <eor>' }}
  $receipt = [ordered]@{{profile=(Join-Path $env:FAKE_STATION ('profiles\\' + $name)); process_id=$global:Pid0}}
  [IO.File]::WriteAllText((Join-Path $env:FAKE_STATION 'station-running.json'), ($receipt | ConvertTo-Json))
}}
$global:Running = 'ic7300'
$global:Device = {pwsh.ps_quote(device)}
"""


class StationSwitchTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.write("launcher.ps1", LAUNCHER)
        self.profile("ic7300", "icom7300://COM3?baud=115200&radio=94&controller=e0")
        self.write(os.path.join("profiles", "ic7300", "contacts.adi"), "<call:6>HB9BLA <eor>\n")
        self.profile("SIM-IC7300", "icom7300://COM4?baud=115200&radio=94&controller=e0")
        self.pin = os.path.join(self.tmp.name, "pin-launcher.ps1")
        with open(self.pin, "w", encoding="utf-8", newline="") as f:
            f.write(LAUNCHER)
        self.log = os.path.join(self.tmp.name, "system.log")
        self.client = os.path.join(self.tmp.name, "client.ps1")
        self.set_client()

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        path = os.path.join(self.station, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(text)

    def read(self, rel):
        with open(os.path.join(self.station, rel), encoding="utf-8", newline="") as f:
            return f.read()

    def profile(self, name, endpoint):
        self.write(os.path.join("profiles", name, "profile.json"),
                   json.dumps({"profile_id": IDS[name], "control": {"mode": "cat", "endpoint": endpoint, "ptt": "cat"}}))

    def set_client(self, contact="idle"):
        with open(self.client, "w", encoding="utf-8") as f:
            f.write(f"""function Open-AgentSession {{ [pscustomobject]@{{}} }}
function Agent-Get($c, $Route) {{
  if ($Route -eq '/transmit') {{ return [pscustomobject]@{{ptt='released'; transmitting=$false}} }}
  if ($Route -eq '/contact') {{ return [pscustomobject]@{{contact=[pscustomobject]@{{state='{contact}'; dx_call='G4BTY'}}}} }}
  $p = [IO.File]::ReadAllText((Join-Path $env:FAKE_STATION ('profiles\\' + $global:Running + '\\profile.json'))) | ConvertFrom-Json
  [pscustomobject]@{{profile_id=$p.profile_id; state='ready'; device_id=$global:Device}} }}
""")

    def switch(self, *args, **station):
        return pwsh.run(TOOL, [*args, "-Station", self.station, "-AgentClient", self.client, "-Pin", self.pin,
                               "-ReadBackSeconds", "4"],
                        prelude(self.log, **station), env={"FAKE_STATION": self.station})

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

    BACKUP = "launcher.ps1.before-simulator"

    def test_dry_run_prints_every_step_and_changes_nothing(self):
        before = self.snapshot()
        rc, out = self.switch("-To", "simulator", "-DryRun")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH DRY-RUN", out)
        for step in ("would: back up the launcher", "would: point the launcher at profiles\\SIM-IC7300",
                     "would: stop the station gracefully", "would: start the task", "would: read back",
                     "would: hash the ic7300 profile"):
            self.assertIn(step, out)
        self.assertIn("before: ic7300\\contacts.adi sha256", out)
        self.assertEqual(self.snapshot(), before)
        self.assertEqual(self.system(), [], "no stop, no task")

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

    def test_simulator_backs_up_switches_restarts_and_reads_back(self):
        operator = self.operator_files()
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH PASS the station runs profiles\\SIM-IC7300", out)
        self.assertIn(f"GET /radio profile_id {IDS['SIM-IC7300']}, state ready", out)
        self.assertEqual(self.read(self.BACKUP), LAUNCHER)
        launcher = self.read("launcher.ps1")
        self.assertIn("$stationProfilePath=Join-Path $base 'profiles\\SIM-IC7300';$stamp", launcher)
        self.assertEqual(launcher.count(ENV_LINE), 1)
        self.assertIn(ENV_LINE + "\r\n$stationProfilePath", launcher, "its own line, the launcher's line ends")
        self.assertEqual(launcher.replace(ENV_LINE + "\r\n", "").replace("SIM-IC7300", "ic7300"), LAUNCHER,
                         "nothing else changes")
        self.assertEqual(self.system(), ["ctrl-c", "task-stop", "task-start"])
        self.assertEqual(self.operator_files(), operator)
        self.assertIn("after: ic7300\\profile.json sha256", out)

    def test_a_second_switch_keeps_the_first_backup(self):
        self.assertEqual(self.switch("-To", "simulator")[0], 0)
        rc, out = self.switch("-To", "simulator")
        self.assertEqual(rc, 0, out)
        self.assertIn("the backup is not taken again", out)
        self.assertEqual(self.read(self.BACKUP), LAUNCHER, "the backup stays the operator's launcher")
        self.assertEqual(self.read("launcher.ps1").count(ENV_LINE), 1)

    def test_back_restores_the_backup_and_reads_back_the_operator_profile(self):
        self.assertEqual(self.switch("-To", "simulator")[0], 0)
        os.unlink(self.log)
        rc, out = self.switch("-To", "back")
        self.assertEqual(rc, 0, out)
        self.assertIn("SWITCH PASS the station runs profiles\\ic7300", out)
        self.assertEqual(self.read("launcher.ps1"), LAUNCHER)
        self.assertFalse(os.path.exists(os.path.join(self.station, self.BACKUP)))
        self.assertEqual(self.system(), ["ctrl-c", "task-stop", "task-start"])

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
        import shutil
        shutil.rmtree(os.path.join(self.station, "profiles", "SIM-IC7300"))
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

    def test_a_changed_logbook_exits_non_zero(self):
        rc, out = self.switch("-To", "simulator", touches_logbook=True)
        self.assertEqual(rc, 2, out)
        self.assertIn("ic7300\\contacts.adi changed", out)

    def test_a_station_that_reads_back_another_profile_exits_non_zero(self):
        rc, out = self.switch("-To", "simulator", runs="ic7300")
        self.assertEqual(rc, 2, out)
        self.assertIn(f"runs profile {IDS['ic7300']}, not SIM-IC7300", out)

    def test_a_station_on_com3_exits_non_zero(self):
        rc, out = self.switch("-To", "simulator", device="COM3")
        self.assertEqual(rc, 2, out)
        self.assertIn("real radio's port", out)

    def test_a_station_that_is_not_running_is_started(self):
        rc, out = self.switch("-To", "simulator", running=False)
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.system(), ["task-start"])

    def test_only_simulator_or_back(self):
        for args in ((), ("-To", "ic7300"), ("-To", "")):
            rc, out = self.switch(*args)
            self.assertEqual(rc, 2, f"{args}: {out}")
            self.assertIn("need -To simulator or -To back", out)
        self.assertEqual(self.system(), [])

    def test_the_script_writes_no_profile_and_opens_no_port(self):
        with open(TOOL, encoding="utf-8") as f:
            text = f.read()
        self.assertNotIn("SerialPort", text)
        self.assertNotIn("Set-Content", text)
        writes = [line for line in text.splitlines() if "WriteAllText" in line or "Copy-Item" in line or "Remove-Item" in line]
        for line in writes:
            self.assertRegex(line, r"\$launcher|\$backup", line)


if __name__ == "__main__":
    unittest.main()
