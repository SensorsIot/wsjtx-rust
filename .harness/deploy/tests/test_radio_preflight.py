"""radio-preflight.ps1: refuses above the authorized RF power, one live writer at a time.

The fake radio is built from the captured reply in wsjtx-rust#44 comment 6683921947
(`RF power 14 0A -> 14 0A 00 26`, COM3, IC-7300, 2026-11-06); the framing FE FE E0 94 ... FD is
the same capture script's parser. Everything that reaches the system (serial port, station
process, scheduled task, station HTTP) is a mock function; no radio or station is touched.
"""
import json
import os
import tempfile
import unittest

import pwsh

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(HERE, "radio-preflight.ps1")


def prelude(log, raw="00 26", running=True, ptt="released", contact="idle", open_fails=False, comes_back=True, stops_after=0):
    """The fake radio answers 14 0A with `raw`; `log` receives what reached the system."""
    reply = "" if raw is None else f"0xFE,0xFE,0xE0,0x94,0x14,0x0A,0x{raw[:2]},0x{raw[3:]},0xFD"
    return f"""
$global:Log = {pwsh.ps_quote(log)}
function Note($t) {{ Add-Content -LiteralPath $global:Log -Value $t }}
$global:Up = ${running}
$global:Started = $false
$global:DownAt = $null
function Get-CimInstance {{ param($ClassName,$Filter)
  if ($global:DownAt -and [DateTime]::UtcNow -ge $global:DownAt) {{ $global:Up = $false; $global:DownAt = $null }}
  if ($global:Up) {{ [pscustomobject]@{{ProcessId=4242; ExecutablePath=(Join-Path $env:FAKE_STATION 'abc\\wstx-rust.exe')}} }} }}
function Start-Process {{ param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait)
  Note 'ctrl-c'
  if ({stops_after} -gt 0) {{ $global:DownAt = [DateTime]::UtcNow.AddSeconds({stops_after}) }} else {{ $global:Up = $false }}
  [pscustomobject]@{{ExitCode=0}} }}
function Stop-ScheduledTask {{ param($TaskName,$ErrorAction) Note 'task-stop' }}
function Get-ScheduledTask {{ param($TaskName) [pscustomobject]@{{State='Ready'}} }}
function Start-ScheduledTask {{ param($TaskName)
  if (@(Get-CimInstance).Count -gt 0) {{ Note 'task-start ignored: still running' }} else {{ Note 'task-start'; $global:Up = ${comes_back} }} }}
function New-Object {{ param($TypeName, [Parameter(ValueFromRemainingArguments=$true)]$Rest)
  if ($TypeName -ne 'System.IO.Ports.SerialPort') {{ return Microsoft.PowerShell.Utility\\New-Object $TypeName @Rest }}
  $p = [pscustomobject]@{{DtrEnable=$true; RtsEnable=$true; ReadTimeout=0; WriteTimeout=0; IsOpen=$false; Queue=$null}}
  $p.Queue = [System.Collections.Generic.Queue[int]]::new()
  $p | Add-Member ScriptProperty BytesToRead {{ $this.Queue.Count }}
  $p | Add-Member ScriptMethod Open {{ if (${open_fails}) {{ throw [UnauthorizedAccessException]::new('Access to the port COM3 is denied.') }}
    Note "open dtr=$($this.DtrEnable) rts=$($this.RtsEnable)"; $this.IsOpen = $true }}
  $p | Add-Member ScriptMethod Close {{ Note 'close'; $this.IsOpen = $false }}
  $p | Add-Member ScriptMethod DiscardInBuffer {{ }}
  $p | Add-Member ScriptMethod Write {{ param($b,$o,$c) Note ('write ' + (($b | ForEach-Object {{ $_.ToString('X2') }}) -join ' ')); foreach ($x in @({reply})) {{ $this.Queue.Enqueue($x) }} }}
  $p | Add-Member ScriptMethod ReadByte {{ $this.Queue.Dequeue() }}
  $p }}
"""


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = os.path.join(self.tmp.name, "state")
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.log = os.path.join(self.tmp.name, "system.log")
        self.client = os.path.join(self.tmp.name, "client.ps1")
        self.set_client()

    def tearDown(self):
        self.tmp.cleanup()

    def set_client(self, ptt="released", contact="idle", broken=False):
        body = "throw 'no session'" if broken else "[pscustomobject]@{}"
        state = f"[pscustomobject]@{{state='{contact}'; dx_call='G4BTY'}}" if contact else "$null"
        with open(self.client, "w", encoding="utf-8") as f:
            f.write(f"""function Open-AgentSession {{ {body} }}
function Agent-Get($c, $Route) {{ if ($Route -eq '/transmit') {{ [pscustomobject]@{{ptt='{ptt}'; transmitting=$false}} }} else {{ [pscustomobject]@{{contact={state}}} }} }}
""")

    def run_tool(self, *args, **radio):
        return pwsh.run(TOOL, [*args, "-StateDir", self.state, "-Station", self.station, "-AgentClient", self.client],
                        prelude(self.log, **radio), env={"FAKE_STATION": self.station})

    def preflight(self, holder="cr44-a", **radio):
        return self.run_tool("-Holder", holder, **radio)

    def system(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return f.read().splitlines()

    def records(self):
        with open(os.path.join(self.state, "preflight.jsonl"), encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()]

    def lease(self):
        rc, out = self.run_tool("-Status")
        self.assertEqual(rc, 0, out)
        return out.strip()

    def test_refuses_at_0026_prints_and_records_the_old_value(self):
        rc, out = self.preflight(raw="00 26")
        self.assertEqual(rc, 1, out)
        self.assertIn("PREFLIGHT REFUSED", out)
        self.assertIn("0026 (10.2 %)", out)
        self.assertIn("above the authorized 0003", out)
        record = self.records()[-1]
        self.assertEqual((record["rf_power_bcd"], record["verdict"], record["holder"]), (26, "REFUSED", "cr44-a"))
        self.assertEqual(self.lease(), "lease: free", "a refusal keeps no lease")

    def test_full_power_is_refused_and_no_flag_gets_past_the_limit(self):
        rc, out = self.preflight(raw="02 55")
        self.assertEqual(rc, 1, out)
        self.assertIn("PREFLIGHT REFUSED", out)
        self.assertEqual(self.lease(), "lease: free")
        other = os.path.join(self.tmp.name, "wide-open.json")
        with open(other, "w", encoding="utf-8") as f:
            json.dump({"port": "COM3", "baud": 9600, "rf_power_max_bcd": 255, "authorized_watts": 100}, f)
        # The script has no CmdletBinding, so PowerShell ignores a flag it does not declare.
        for flag in (["-Attended"], ["-Authorization", other]):
            rc, out = self.run_tool("-Holder", "cr44-a", *flag, raw="02 55")
            self.assertEqual(rc, 1, f"{flag}: {out}")
            self.assertIn("PREFLIGHT REFUSED", out, flag)
            self.assertEqual(self.lease(), "lease: free", flag)

    def test_refuses_just_above_and_passes_at_the_authorized_value(self):
        self.assertEqual(self.preflight(raw="00 04")[0], 1)
        rc, out = self.preflight(raw="00 03")
        self.assertEqual(rc, 0, out)
        self.assertIn("PREFLIGHT PASS", out)
        self.assertIn("held by cr44-a", self.lease())

    def test_a_higher_byte_counts(self):
        # BCD: 01 03 is 103, never 3.
        self.assertEqual(self.preflight(raw="01 03")[0], 1)

    def test_reads_with_dtr_and_rts_off_and_writes_only_the_read_frame(self):
        self.preflight(raw="00 03")
        system = self.system()
        self.assertIn("open dtr=False rts=False", system)
        self.assertEqual([line for line in system if line.startswith("write")], ["write FE FE 94 E0 14 0A FD"])

    def test_the_station_is_stopped_read_and_started_again_in_that_order(self):
        self.preflight(raw="00 26")
        system = self.system()
        self.assertEqual([line.split()[0] for line in system if line != "task-stop"],
                         ["ctrl-c", "open", "write", "close", "task-start"])

    def test_a_station_that_is_not_running_is_read_and_not_started(self):
        rc, out = self.preflight(raw="00 03", running=False)
        self.assertEqual(rc, 0, out)
        self.assertNotIn("task-start", self.system())
        self.assertNotIn("ctrl-c", self.system())

    def test_no_reply_is_no_pass_and_the_station_comes_back(self):
        rc, out = self.preflight(raw=None)
        self.assertEqual(rc, 2, out)
        self.assertIn("no RF power reply", out)
        self.assertIn("task-start", self.system())
        self.assertEqual(self.lease(), "lease: free")

    def test_a_held_port_is_no_pass_and_the_station_comes_back(self):
        rc, out = self.preflight(open_fails=True)
        self.assertEqual(rc, 2, out)
        self.assertIn("denied", out)
        self.assertIn("task-start", self.system())

    def test_a_station_that_does_not_come_back_is_said_loudly(self):
        rc, out = self.preflight(raw="00 03", comes_back=False)
        self.assertEqual(rc, 2, out)
        self.assertIn("THE STATION IS DOWN", out)

    def test_a_stop_slower_than_its_deadline_still_brings_the_station_back(self):
        # Ctrl+C has gone out: the station exits 13 s later, after the 12 s deadline.
        rc, out = self.preflight(raw="00 03", stops_after=13)
        self.assertEqual(rc, 2, out)
        self.assertIn("did not stop on Ctrl+C", out)
        self.assertIn("task-start", self.system(), out)
        self.assertNotIn("task-start ignored: still running", self.system(), out)
        self.assertNotIn("THE STATION IS DOWN", out)

    def test_a_station_that_never_stops_is_said_loudly(self):
        rc, out = self.preflight(raw="00 03", stops_after=600)
        self.assertEqual(rc, 2, out)
        self.assertIn("THE STATION IS DOWN", out)
        self.assertNotIn("task-start", self.system())

    def test_a_contact_or_ptt_leaves_the_station_alone(self):
        for client in ({"contact": "report"}, {"ptt": "asserted"}, {"broken": True}):
            self.set_client(**client)
            rc, out = self.preflight(raw="00 03")
            self.assertEqual(rc, 3, f"{client}: {out}")
            self.assertIn("was not stopped", out)
            self.assertEqual(self.system(), [], client)

    def test_an_update_in_progress_leaves_the_station_alone(self):
        with open(os.path.join(self.station, "logs", "update.lock"), "w"):
            rc, out = self.preflight(raw="00 03")
        self.assertEqual(rc, 3, out)
        self.assertEqual(self.system(), [])

    def test_a_second_live_writer_is_refused_before_it_touches_the_station(self):
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0)
        os.unlink(self.log)
        rc, out = self.preflight("cr55-b", raw="00 03")
        self.assertEqual(rc, 3, out)
        self.assertIn("cr44-a", out)
        self.assertEqual(self.system(), [], "a refused writer never stops the station")

    def test_the_holder_renews_and_releases_and_only_the_holder(self):
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0)
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0, "the holder runs it again")
        self.assertEqual(self.run_tool("-Release", "-Holder", "cr55-b")[0], 3)
        self.assertEqual(self.run_tool("-Release", "-Holder", "cr44-a")[0], 0)
        self.assertEqual(self.lease(), "lease: free")
        self.assertEqual(self.preflight("cr55-b", raw="00 03")[0], 0)

    def test_a_holder_refused_as_busy_keeps_its_lease_as_it_was(self):
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0)
        before = self.lease()
        self.set_client(contact="report")
        rc, out = self.run_tool("-Holder", "cr44-a", "-Minutes", "240", raw="00 03")
        self.assertEqual(rc, 3, out)
        self.assertEqual(self.lease(), before, "its own contact runs: neither dropped nor extended")
        self.assertEqual(self.preflight("cr55-b", raw="00 03")[0], 3, "a second writer stays out")

    def test_a_new_writer_refused_as_busy_holds_no_lease(self):
        self.set_client(contact="report")
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 3)
        self.assertEqual(self.lease(), "lease: free")

    def test_a_holder_whose_renewal_is_refused_or_unread_loses_its_lease(self):
        for raw, code in (("00 26", 1), (None, 2)):
            self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0)
            self.assertEqual(self.preflight("cr44-a", raw=raw)[0], code)
            self.assertEqual(self.lease(), "lease: free", raw)

    def test_an_expired_lease_is_free(self):
        os.makedirs(self.state)
        with open(os.path.join(self.state, "lease.json"), "w", encoding="utf-8") as f:
            json.dump({"holder": "gone", "acquired": "2026-01-01T00:00:00Z", "expires": "2026-01-01T00:30:00Z"}, f)
        self.assertEqual(self.lease(), "lease: free")
        self.assertEqual(self.preflight("cr44-a", raw="00 03")[0], 0)


if __name__ == "__main__":
    unittest.main()
