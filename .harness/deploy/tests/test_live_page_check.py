"""live-page-check.ps1 (SensorsIot/harness#38 item 3): it restarts the station only when it is free.

Everything that reaches the system is mocked: the agent client, the station process, the Ctrl+C
helper, the scheduled task. The page check is a stand-in that asks for the restart and reports
the lines it was handed (their keys only).
"""
import json
import os
import tempfile
import unittest

import pwsh

SCRIPT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "live-page-check.ps1")

FAKE_CHECK = r"""
const fs=require('node:fs'),path=require('node:path'),readline=require('node:readline');
fs.writeFileSync(path.join(process.env.WSTX_LIVE_PAGE_CONTROL,'restart'),'');
let sessions=0;
readline.createInterface({input:process.stdin}).on('line',line=>{
  const m=JSON.parse(line.replace(/^﻿/,''));
  console.log('CHECK GOT '+Object.keys(m).join(','));
  if(m.abort)process.exit(3);
  if(m.cookies&&++sessions===2)process.exit(0);
});
"""

AGENT_CLIENT = r"""
$AgentUrl = 'https://localhost:9'
function Log($what) { Add-Content -LiteralPath $env:LPC_LOG -Value $what }
function Open-AgentSession {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $s.Cookies.Add((New-Object Net.Cookie 'wstx_session_p', 'secret', '/', 'localhost'))
  [pscustomobject]@{ Session = $s }
}
function Agent-Get($c, [string]$Route) {
  $state = [IO.File]::ReadAllText($env:LPC_STATE) | ConvertFrom-Json
  if ($state.PSObject.Properties['unreadable']) { throw [Net.WebException]::new('down') }
  switch ($Route) {
    '/transmit' { [pscustomobject]@{ ptt = $state.ptt; transmitting = $state.transmitting; transmit = [pscustomobject]@{ arm_state = $state.arm } } }
    '/contact' { [pscustomobject]@{ contact = $state.contact } }
    '/automation' { [pscustomobject]@{ run = $state.run } }
  }
}
"""


def prelude(station):
    exe = pwsh.ps_quote(os.path.join(station, "0d7d5c922", "wstx-rust.exe"))
    down = pwsh.ps_quote(os.path.join(station, "down"))
    return f"""
function Log($what) {{ Add-Content -LiteralPath $env:LPC_LOG -Value $what }}
function Get-CimInstance {{ param($ClassName,$Filter) if (-not (Test-Path -LiteralPath {down})) {{ [pscustomobject]@{{ProcessId=4242; ExecutablePath={exe}}} }} }}
function Start-Process {{ param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,[switch]$Wait) Log 'ctrlc'; Set-Content -LiteralPath {down} -Value ''; [pscustomobject]@{{ExitCode=0}} }}
function Stop-ScheduledTask {{ param($TaskName,$ErrorAction) }}
function Get-ScheduledTask {{ param($TaskName) [pscustomobject]@{{State='Ready'}} }}
function Start-ScheduledTask {{ param($TaskName) Log 'start'; Remove-Item -LiteralPath {down} }}
function Start-Sleep {{ param($Seconds,$Milliseconds) [Threading.Thread]::Sleep(20) }}
"""


FREE = {"arm": "disarmed", "ptt": "released", "transmitting": False, "contact": None, "run": None}


class LivePageCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.station = os.path.join(self.tmp.name, "station")
        os.makedirs(os.path.join(self.station, "logs"))
        self.radio = os.path.join(self.tmp.name, "radio")
        os.makedirs(self.radio)
        self.log = os.path.join(self.tmp.name, "log.txt")
        open(self.log, "w").close()
        self.state = os.path.join(self.tmp.name, "state.json")
        self.check = os.path.join(self.tmp.name, "check.cjs")
        with open(self.check, "w", encoding="utf-8") as f:
            f.write(FAKE_CHECK)
        self.client = os.path.join(self.tmp.name, "agent-client.ps1")
        with open(self.client, "w", encoding="utf-8") as f:
            f.write(AGENT_CLIENT)

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, state):
        with open(self.state, "w", encoding="utf-8") as f:
            json.dump(state, f)
        rc, out = pwsh.run(SCRIPT, ["-WaitSeconds", "1", "-Station", self.station, "-AgentClient", self.client,
                                    "-RadioDir", self.radio, "-Check", self.check], prelude(self.station),
                           env={"LPC_LOG": self.log, "LPC_STATE": self.state})
        with open(self.log, encoding="utf-8") as f:
            return rc, out, f.read().split()

    def assert_busy(self, state, why):
        rc, out, log = self.run_check(state)
        self.assertEqual(rc, 3, out)
        self.assertNotIn("ctrlc", log, out)
        self.assertNotIn("start", log, out)
        self.assertIn("CHECK GOT abort", out)
        self.assertIn(why, out)
        self.assertIn("LIVE PAGE CHECK BUSY", out)

    def test_free_station_is_restarted_once_and_the_new_session_handed_on(self):
        rc, out, log = self.run_check(FREE)
        self.assertEqual(rc, 0, out)
        self.assertEqual(log, ["ctrlc", "start"], out)
        self.assertEqual([l for l in out.splitlines() if l.startswith("CHECK GOT")],
                         ["CHECK GOT cookies", "CHECK GOT stopping", "CHECK GOT cookies"], out)
        self.assertNotIn("secret", out)
        self.assertIn("LIVE PAGE CHECK PASS", out)

    def test_armed(self):
        self.assert_busy(dict(FREE, arm="armed"), "transmit is armed")

    def test_ptt_keyed(self):
        self.assert_busy(dict(FREE, ptt="keyed"), "PTT is keyed")

    def test_transmitting(self):
        self.assert_busy(dict(FREE, transmitting=True), "transmitting: True")

    def test_contact_running(self):
        self.assert_busy(dict(FREE, contact={"state": "report"}), "a contact is report")

    def test_automation_run(self):
        self.assert_busy(dict(FREE, run={"state": "waiting"}), "an automation run is waiting")

    def test_unreadable_state(self):
        self.assert_busy(dict(FREE, unreadable=True), "its state cannot be read")

    def test_radio_lease(self):
        with open(os.path.join(self.radio, "lease.json"), "w", encoding="utf-8") as f:
            json.dump({"holder": "qso-test", "expires": "2099-01-01T00:00:00Z"}, f)
        self.assert_busy(FREE, "qso-test holds the radio lease")

    def test_update_running(self):
        with open(os.path.join(self.station, "logs", "update.lock"), "w"):
            self.assert_busy(FREE, "an update is running")

    def test_the_update_lock_is_free_again_after_the_restart(self):
        rc, out, _ = self.run_check(FREE)
        self.assertEqual(rc, 0, out)
        with open(os.path.join(self.station, "logs", "update.lock"), "a"):
            pass


if __name__ == "__main__":
    unittest.main()
