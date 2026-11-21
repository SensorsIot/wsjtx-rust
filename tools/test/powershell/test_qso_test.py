"""qso-test.ps1: the QSO test driver against a scripted station (TC-171-05).

The station client the driver dot-sources is a scripted station: its GET views (/transmit,
/contact, /automation, /radio, /receive and its results), its commands, the radio.tx_level
pushes and the clock are driven by a scenario this test writes. The radio preflight is a
scripted script that records its arguments. Nothing reaches a station, radio or network.
Each run's log holds the commands, the keyed periods and the preflight calls; the verdict is
the line the driver appends to qso-tests.jsonl.

The driver's own /ws seams run against a station-like WebSocket endpoint in this file
(TC-192-03), on the loopback interface only; attempts per revision and radio are TC-192-04.
"""
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest

# The one copy of the PowerShell runner is tools/deploy/tests/pwsh.py.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "deploy", "tests"))
import pwsh  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER = os.path.join(HERE, "qso-test.ps1")

T0 = 1_800_000_000_000  # an even FT8 period start
LEN = 15_000
SIM_ID = "11111111-1111-4111-8111-111111111111"
OPERATOR_ID = "22222222-2222-4222-8222-222222222222"
BOOT = "33333333-3333-4333-8333-333333333333"
SOURCE = "44444444-4444-4444-8444-444444444444"
JOB = "55555555-5555-4555-8555-555555555555"
OWN = "HB9BLA"
SIM_ENDPOINT = "icom7300://COM4?baud=115200&radio=94&controller=e0"
# Two deployed revisions (x-wstx-source-commit of GET /) and the real radio's profile.
REV_A = "0123456789abcdef0123456789abcdef01234567"
REV_B = "fedcba9876543210fedcba9876543210fedcba98"
REAL_RADIO = "ic7300"
# Startup on the scripted clock: GET /radio ready 2 s after each preflight, 1 s of pushes
# before Tune, 3 s of Tune: the 0255 read-back is at 8 s and the polls fall on whole seconds.
T255 = 8_000

STATION = r"""
# Scripted station for test_qso_test.py, dot-sourced by qso-test.ps1 as its station client.
function global:ConvertTo-FHash($o) {
  if ($null -eq $o) { return $null }
  if ($o -is [System.Management.Automation.PSCustomObject]) { $h = @{}; foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = ConvertTo-FHash $p.Value }; return $h }
  if ($o -is [System.Collections.IList]) { $l = New-Object System.Collections.ArrayList; foreach ($x in $o) { [void]$l.Add((ConvertTo-FHash $x)) }; return , $l }
  return $o
}
function global:Copy-F($o) {
  if ($o -is [hashtable]) { $h = @{}; foreach ($k in @($o.Keys)) { $h[$k] = Copy-F $o[$k] }; return $h }
  if ($o -is [System.Collections.IList]) { $l = New-Object System.Collections.ArrayList; foreach ($x in $o) { [void]$l.Add((Copy-F $x)) }; return , $l }
  return $o
}
function global:Merge-F([hashtable]$Dst, [hashtable]$Patch) {
  foreach ($k in @($Patch.Keys)) {
    if ($Dst[$k] -is [hashtable] -and $Patch[$k] -is [hashtable]) { Merge-F $Dst[$k] $Patch[$k] } else { $Dst[$k] = Copy-F $Patch[$k] }
  }
}
function global:Json-F($o) { ($o | ConvertTo-Json -Depth 20 -Compress) | ConvertFrom-Json }
$global:FScn = ConvertTo-FHash ([IO.File]::ReadAllText($env:QSO_SCENARIO) | ConvertFrom-Json)
$global:FT0 = [long]$global:FScn.t0; $global:FNow = $global:FT0
$global:FLen = if ($global:FScn.mode -eq 'ft4') { 7500 } else { 15000 }
$global:FV = @{ transmit = $global:FScn.transmit; contact = $global:FScn.contact; automation = $global:FScn.automation }
$global:FTimes = @{}; $global:FRecs = New-Object System.Collections.ArrayList; $global:FContactN = 0
$global:FLease = $null; $global:FReadyAt = $global:FT0
$global:FKey = $global:FScn.key; $global:FKey['enabled'] = $false; $global:FKey['next'] = $null; $global:FKey['dx'] = $null; $global:FKey['parity'] = 1
if (-not $global:FKey.ContainsKey('stuck')) { $global:FKey['stuck'] = $false }
# The send on the air: its period and end (FT8 12.64 s, FT4 5.04 s); the running profile.
$global:FSend = $null; $global:FSendMs = if ($global:FScn.mode -eq 'ft4') { 5040 } else { 12640 }
$global:FRunning = $global:FScn.transmit.profile_id

function global:Fake-Log([hashtable]$E) {
  $E['t'] = $global:FNow - $global:FT0
  [IO.File]::AppendAllText($env:QSO_LOG, (([pscustomobject]$E | ConvertTo-Json -Compress -Depth 12) + "`n"))
}
function global:Fake-Mark([string]$What, [long]$At) {
  if (-not $global:FTimes.ContainsKey($What)) { $global:FTimes[$What] = New-Object System.Collections.ArrayList }
  [void]$global:FTimes[$What].Add($At)
}
# When an event is due: `at` (ms from t0), or `after` the nth mark of an action, a key, a GET
# (get:<route>) or an applied change (change:<id>) plus `delay`; with `then`, at the first mark
# of `then` from that time on.
function global:Fake-Due($Ev) {
  if ($null -ne $Ev['at']) { return $global:FT0 + [long]$Ev['at'] }
  if (-not $Ev['after']) { return $null }
  $times = $global:FTimes[$Ev['after']]
  $nth = 1; if ($Ev['nth']) { $nth = [int]$Ev['nth'] }
  if ($null -eq $times -or $times.Count -lt $nth) { return $null }
  $delay = 0; if ($Ev['delay']) { $delay = [long]$Ev['delay'] }
  $base = [long]$times[$nth - 1] + $delay
  if (-not $Ev['then']) { return $base }
  foreach ($m in @($global:FTimes[$Ev['then']])) { if ($null -ne $m -and [long]$m -ge $base) { return [long]$m } }
  return $null
}
function global:Fake-NextKey {
  $n = [long][Math]::Floor($global:FNow / $global:FLen) + 1
  while ($n % 2 -ne $global:FKey['parity']) { $n++ }
  $n * $global:FLen
}
function global:Fake-Apply([hashtable]$Patch) {
  foreach ($key in @($Patch.Keys)) {
    if ($key -eq '_key') {
      $was = $global:FKey['enabled']; Merge-F $global:FKey $Patch[$key]
      if ($global:FKey['enabled'] -and -not $was) { $global:FKey['next'] = Fake-NextKey }
    } elseif ($key -eq '_lease') { $global:FLease = $Patch[$key] }
    elseif ($key -eq '_running') { $global:FRunning = $Patch[$key] }
    else { Merge-F $global:FV[$key] $Patch[$key] }
  }
  Fake-Log @{ kind = 'change'; keys = @($Patch.Keys) }
}
function global:Fake-Advance {
  for (;;) {
    $now = $global:FNow; $bestT = $null; $best = $null
    foreach ($ch in $global:FScn.changes) {
      if ($ch['done']) { continue }
      $t = Fake-Due $ch
      if ($null -ne $t -and $t -le $now -and ($null -eq $bestT -or $t -lt $bestT)) { $bestT = $t; $best = $ch }
    }
    $k = $global:FKey
    $send = $global:FSend
    if ($send -and $send['end'] -le $now -and ($null -eq $bestT -or $send['end'] -le $bestT)) {
      $global:FV.transmit['transmitting'] = $false
      if (-not $k['stuck']) { $global:FV.transmit['ptt'] = 'released' }
      $global:FSend = $null
      continue
    }
    if ($k['enabled'] -and $null -ne $k['next'] -and $k['next'] -le $now -and ($null -eq $bestT -or $k['next'] -lt $bestT)) {
      $tr = $global:FV.transmit.transmit
      $tr['last_period_utc'] = [long]$k['next']; $tr['last_text'] = ([string]$k['text']).Replace('{dx}', [string]$k['dx'])
      $global:FSend = @{ period = [long]$k['next']; end = [long]$k['next'] + $global:FSendMs }
      $global:FV.transmit['transmitting'] = $true; $global:FV.transmit['ptt'] = 'asserted'
      Fake-Mark 'key' $k['next']
      Fake-Log @{ kind = 'key'; period = $k['next'] - $global:FT0; text = $tr['last_text']; arm_state = $tr['arm_state'] }
      $k['next'] = [long]$k['next'] + 2 * $global:FLen
      continue
    }
    if (-not $best) { break }
    $best['done'] = $true
    Fake-Apply $best['patch']
    if ($best['id']) { Fake-Mark "change:$($best['id'])" $now }
  }
  foreach ($r in $global:FScn.records) {
    if ($r['done']) { continue }
    if ($null -ne $r['period']) { $period = $global:FT0 + [long]$r['period'] }
    else {
      $due = Fake-Due $r
      if ($null -eq $due) { continue }
      $period = $due + [long]$r['periods'] * $global:FLen
    }
    if ($period + $global:FLen - 2000 -gt $global:FNow) { continue }
    $r['done'] = $true
    $rec = Copy-F $r['record']; $rec['sequence'] = $global:FRecs.Count; $rec['_period_ms'] = $period
    $rec['period_start_utc'] = [DateTimeOffset]::FromUnixTimeMilliseconds($period).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture)
    [void]$global:FRecs.Add($rec)
  }
}
function global:Fake-Automation {
  $v = Copy-F $global:FV.automation; $b = $null
  foreach ($e in $global:FScn.builds) { if ($global:FT0 + [long]$e['from'] -le $global:FNow) { $b = Copy-F $e['build'] } }
  if ($b) {
    if ($b['rx_parity'] -eq 'alternate') { $b['rx_parity'] = @('even', 'odd')[[long][Math]::Floor($global:FNow / $global:FLen) % 2] }
    $b['at_utc_ms'] = $global:FNow; $b['mode'] = $global:FScn.mode; $b['qso'] = $false; $b['periods'] = 4
  }
  $v['free_tx_slots'] = $b
  $v
}
# An abort or a Halt stops the send on the air at once (contact_tests.rs: abort stops the
# transmission now); a send it cuts is logged as `cut`.
function global:Fake-Stop([string]$By) {
  if ($global:FSend) {
    Fake-Log @{ kind = 'cut'; by = $By; period = $global:FSend['period'] - $global:FT0; end = $global:FSend['end'] - $global:FT0 }
    $global:FSend = $null; $global:FV.transmit['transmitting'] = $false
  }
  if ($By -eq 'halt' -or -not $global:FKey['stuck']) { $global:FV.transmit['ptt'] = 'released' }
}
function global:Fake-Contact([string]$Action, [hashtable]$B) {
  $tr = $global:FV.transmit.transmit; $s = $global:FV.contact.settings
  switch ($Action) {
    'tune' { $tr['tune'] = [bool]$B['enabled']; if ($B['enabled']) { $tr['last_period_utc'] = $global:FNow; $tr['last_text'] = $null } }
    'set_hold_tx' { $s['hold_tx'] = [bool]$B['enabled'] }
    'set_frequency' { if ($null -ne $B['rx_hz']) { $s['rx_hz'] = $B['rx_hz'] }; if ($null -ne $B['tx_hz']) { $s['tx_hz'] = $B['tx_hz'] } }
    'reply' {
      $rec = $global:FRecs[[int]$B['row']['sequence']]
      $global:FContactN++
      $global:FV.contact.contact = @{ id = "contact-$($global:FContactN)"; dx_call = $rec.fields.from.text; state = 'replying'; dialogue = (New-Object System.Collections.ArrayList) }
      $s['rx_hz'] = [int][Math]::Round([double]$rec.frequency_hz)
      if (-not $s['hold_tx']) { $s['tx_hz'] = $s['rx_hz'] }
      if ($global:FKey['arm_on_reply']) { $tr['arm_state'] = 'armed' }
      $global:FKey['dx'] = $rec.fields.from.text
      $global:FKey['parity'] = 1 - ([long][Math]::Floor($rec['_period_ms'] / $global:FLen) % 2)
      if ($global:FKey['on_reply']) {
        $global:FKey['enabled'] = $true
        if ($global:FKey['first_delay']) { $global:FKey['next'] = $global:FNow + [long]$global:FKey['first_delay'] } else { $global:FKey['next'] = Fake-NextKey }
      }
    }
    'abort' {
      if ($global:FV.contact.contact) { $global:FV.contact.contact['state'] = 'cancelled' }
      $tr['arm_state'] = 'disarmed'; $tr['last_disarm_cause'] = 'contact_cancelled'; $global:FKey['enabled'] = $false
      Fake-Stop 'abort'
    }
  }
  $global:FV.contact['contact_revision'] = 1 + [long]$global:FV.contact['contact_revision']
}

function Open-AgentSession { [pscustomobject]@{ Session = $null } }
function Agent-Get($c, [string]$Route) {
  Fake-Mark "get:$(($Route -split '\?')[0])" $global:FNow
  Fake-Advance
  if ($Route -eq '/transmit') { return Json-F $global:FV.transmit }
  if ($Route -eq '/contact') { return Json-F $global:FV.contact }
  if ($Route -eq '/automation') { return Json-F (Fake-Automation) }
  if ($Route -eq '/radio') { $state = 'connecting'; if ($global:FNow -ge $global:FReadyAt) { $state = 'ready' }; return Json-F @{ state = $state; profile_id = $global:FV.transmit.profile_id } }
  if ($Route -eq '/receive') { return Json-F @{ v = 1; generation = 1; source = @{ id = $global:FScn.source_id }; job = @{ id = $global:FScn.job_id; mode = $global:FScn.mode; first_sequence = 0; next_sequence = $global:FRecs.Count } } }
  if ($Route.StartsWith('/receive/results?')) {
    $cursor = [int][regex]::Match($Route, 'cursor=(\d+)').Groups[1].Value
    $end = [Math]::Min($global:FRecs.Count, $cursor + 16)
    $recs = @(for ($i = $cursor; $i -lt $end; $i++) { $global:FRecs[$i] })
    return Json-F @{ v = 1; records = $recs; next = $end; more = ($end -lt $global:FRecs.Count) }
  }
  throw "scripted station: no route $Route"
}
function Agent-Post($c, [string]$Route, $Body) {
  Fake-Advance
  $b = ConvertTo-FHash (Json-F $Body)
  $action = [string]$b['action']
  if ($Route -eq '/transmit/halt') { $action = 'halt' } elseif ($Route -eq '/automation/command') { $action = "auto_$action" }
  # Every command route refuses a body profile_id other than the running profile's.
  if ($b['profile_id'] -ne $global:FRunning) {
    Fake-Log @{ kind = 'refused'; route = $Route; action = $action; body = $b; running = $global:FRunning }
    return [pscustomobject]@{ Status = 403; Body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'wrong_profile'; field = 'profile_id' } } }
  }
  if ($Route -eq '/transmit/halt') { Fake-Stop 'halt' }
  elseif ($Route -eq '/automation/command') { if ($global:FV.automation.run) { $global:FV.automation.run['state'] = 'stopped' } }
  else { Fake-Contact $action $b }
  Fake-Mark $action $global:FNow
  $dx = $null; if ($global:FV.contact.contact) { $dx = $global:FV.contact.contact.dx_call }
  Fake-Log @{ kind = 'command'; route = $Route; action = $action; body = $b; dx = $dx }
  [pscustomobject]@{ Status = 202; Body = [pscustomobject]@{ accepted = $true } }
}
function Qso-Now { $global:FNow }
function Qso-Sleep([long]$Ms) { $global:FNow += $Ms }
function Qso-OpenPushes($c) { Fake-Log @{ kind = 'subscribe' } }
function Qso-ReceivePushes([long]$Until) {
  if ($Until -gt $global:FNow) { $global:FNow = $Until }
  Fake-Advance
  $out = New-Object System.Collections.ArrayList
  foreach ($p in $global:FScn.pushes) {
    if ($p['done']) { continue }
    $t = Fake-Due $p
    if ($null -eq $t -or $t -gt $Until) { continue }
    $p['done'] = $true
    [void]$out.Add([pscustomobject]@{ at = $t; data = (Json-F $p['data']) })
  }
  $out.ToArray()
}
function Qso-ClosePushes { }
function Qso-Revision($c) { foreach ($v in $global:FScn.revision) { $v } }
"""

PREFLIGHT = r"""
param([string]$Holder, [string]$PowerBcd, [int]$Minutes = 30, [switch]$Status, [switch]$Release, [switch]$Restore,
      [switch]$NoWrite, [string]$Port, [string]$Baud, [string]$StateDir, [string]$Station, [string]$AgentClient)
$what = if ($Status) { 'status' } elseif ($Release) { 'release' } elseif ($Restore) { 'restore' } else { $PowerBcd }
Fake-Log @{ kind = 'preflight'; what = $what; holder = $Holder; minutes = $Minutes; port = $Port; baud = $Baud }
if ($Status) { if ($global:FLease) { "lease: held by $($global:FLease) until 2099-01-01T00:00:00Z" } else { 'lease: free' }; exit 0 }
if ($Release) { $global:FLease = $null; "lease: released by $Holder"; exit 0 }
$code = 0
$codes = $global:FScn.preflight[$what]
if ($codes -and $codes.Count) { $code = [int]$codes[0]; $codes.RemoveAt(0) }
if ($code -eq 0) { if ($Restore) { $global:FLease = $null } else { $global:FLease = $Holder } }
if ($null -eq $global:FScn.radio_ready_ms) { $global:FReadyAt = [long]::MaxValue } else { $global:FReadyAt = $global:FNow + [long]$global:FScn.radio_ready_ms }
"PREFLIGHT $(@{0 = 'PASS'; 3 = 'BUSY'}[$code]) scripted $what"
exit $code
"""


def rec(frm, to, hz=1500.0, kind="standard", to_kind=None, worked="not_worked", exchange=("grid", "JN47"), text=None):
    """A decoded record as /receive/results publishes it (fields, worked_status)."""
    fields = {"type": kind, "to": {"kind": to_kind or ("token" if to.startswith("CQ") else "call"), "text": to},
              "from": {"kind": "call", "text": frm}, "ack": False,
              "exchange": {"kind": exchange[0], "value": exchange[1]}}
    r = {"status": "decoded", "fields": fields, "frequency_hz": hz, "snr_db": -10,
         "text": text or f"{to} {frm} {exchange[1]}"}
    if worked is not None:
        r["worked_status"] = worked
    return r


class Scenario:
    def __init__(self, tx_calls=6, ready_ms=2000):
        self.d = {
            "t0": T0, "mode": "ft8", "source_id": SOURCE, "job_id": JOB, "radio_ready_ms": ready_ms,
            "revision": [REV_A],
            "transmit": {"v": 1, "profile_id": SIM_ID, "boot_id": BOOT,
                         "transmit": {"capability": "available", "arm_state": "disarmed", "last_disarm_cause": "startup",
                                      "last_arm_cause": None, "tune": False, "pending_sequence": None, "last_text": None,
                                      "last_period_utc": None, "halt_state": "idle", "refusal": None},
                         "ptt": "released", "transmitting": False,
                         "watchdog": {"tx_calls": tx_calls, "tx_remaining_calls": None, "tx_expired": False},
                         "outcomes": []},
            "contact": {"v": 1, "profile_id": SIM_ID, "boot_id": BOOT, "contact_revision": 1,
                        "transmit": {"safety_revision": 7},
                        "settings": {"hold_tx": False, "rx_hz": 1200, "tx_hz": 1500},
                        "contact": None, "log": None, "watchdog": {"busy_with": None}},
            "automation": {"v": 1, "profile_id": SIM_ID, "boot_id": BOOT, "run": None},
            "builds": [{"from": 0, "build": {"rx_parity": "alternate", "open": [[1000, 1300]]}}],
            "records": [], "changes": [], "preflight": {},
            "pushes": [{"after": "tune", "nth": 1, "delay": 1000,
                        "data": {"meters": {"alc": 0, "po_pct": 40, "swr_x10": 12}, "warnings": []}}],
            "key": {"text": "{dx} " + OWN + " JN47", "on_reply": True, "arm_on_reply": True, "first_delay": None},
        }

    def cq(self, call, periods, hz=1500.0, **kw):
        for p in periods:
            self.record(p, rec(call, "CQ", hz, **kw))
        return self

    def record(self, period, record):
        self.d["records"].append({"period": period, "record": record})
        return self

    def answer(self, record, nth=1, periods=1):
        """A record in the period after our nth key."""
        self.d["records"].append({"after": "key", "nth": nth, "periods": periods, "record": record})
        return self

    def change(self, patch, at=None, after=None, nth=1, delay=0, then=None, name=None):
        ev = {"patch": patch}
        if at is not None:
            ev["at"] = at
        else:
            ev.update({"after": after, "nth": nth, "delay": delay})
        if then:
            ev["then"] = then
        if name:
            ev["id"] = name
        self.d["changes"].append(ev)
        return self

    def end_at(self, at):
        """Ends the run: the station switches to another profile (not tested)."""
        return self.change({"transmit": {"profile_id": OPERATOR_ID}}, at=at)

    def disarm(self, cause, after="key", nth=1, delay=500, failure=None, refusal=None, name=None):
        view = {"transmit": {"arm_state": "disarmed", "last_disarm_cause": cause, "refusal": refusal}}
        if failure:
            view["outcomes"] = [{"outcome_sequence": 3, "request_sequence": 2, "kind": "failed", "refusal": None,
                                 "failure": failure, "audio_start_utc_ms": None}]
        return self.change({"transmit": view, "_key": {"enabled": False}}, after=after, nth=nth, delay=delay, name=name)

    def pushes(self, *pushes):
        self.d["pushes"] = list(pushes)
        return self

    def complete_qso(self, call="K1ABC", log="saved", error=None, change_text=True):
        """He answers our first call; the exchange runs report, signoff, completed. Without
        `change_text` the station keys its first message again after each advancing decode."""
        self.answer(rec(call, OWN, 1500.0, exchange=("report", -10), text=f"{OWN} {call} -10"), nth=1)
        report = {"contact": {"contact": {"state": "report", "dialogue": [
            {"dir": "tx", "text": f"{call} {OWN} JN47", "period_utc_ms": None, "count": 1},
            {"dir": "rx", "text": f"{OWN} {call} -10", "period_utc_ms": None, "count": 1}]}}}
        if change_text:
            report["_key"] = {"text": "{dx} " + OWN + " R-12"}
        self.change(report, after="key", nth=1, delay=LEN + 13_000)
        self.answer(rec(call, OWN, 1500.0, exchange=("roger", "RR73"), text=f"{OWN} {call} RR73"), nth=2)
        signoff = {"contact": {"contact": {"state": "signoff", "dialogue": [
            {"dir": "tx", "text": f"{call} {OWN} JN47", "period_utc_ms": None, "count": 1},
            {"dir": "rx", "text": f"{OWN} {call} -10", "period_utc_ms": None, "count": 1},
            {"dir": "tx", "text": f"{call} {OWN} R-12", "period_utc_ms": None, "count": 1},
            {"dir": "rx", "text": f"{OWN} {call} RR73", "period_utc_ms": None, "count": 1}]}}}
        if change_text:
            signoff["_key"] = {"text": "{dx} " + OWN + " 73"}
        self.change(signoff, after="key", nth=2, delay=LEN + 13_000)
        self.change({"contact": {"contact": {"state": "completed", "dialogue": [
            {"dir": "tx", "text": f"{call} {OWN} JN47", "period_utc_ms": None, "count": 1},
            {"dir": "rx", "text": f"{OWN} {call} -10", "period_utc_ms": None, "count": 1},
            {"dir": "tx", "text": f"{call} {OWN} R-12", "period_utc_ms": None, "count": 1},
            {"dir": "rx", "text": f"{OWN} {call} RR73", "period_utc_ms": None, "count": 1},
            {"dir": "tx", "text": f"{call} {OWN} 73", "period_utc_ms": None, "count": 1}]},
            "log": {"contact_id": "contact-1", "call": call, "outcome": log, "error": error}},
            "transmit": {"transmit": {"arm_state": "disarmed", "last_disarm_cause": "contact_completed"}},
            "_key": {"enabled": False}}, after="key", nth=3, delay=2000)
        return self


def standard(scenario=None, call="K1ABC"):
    """He calls CQ in every even period from 0 s: a target at 73 s, called in that period."""
    s = scenario or Scenario()
    return s.cq(call, range(0, 2_100_000, 30_000))


class DriverBase(unittest.TestCase):
    """The scripted station, the scripted preflight and the run helpers; no test of its own."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = os.path.join(self.tmp.name, "state")
        self.station = os.path.join(self.tmp.name, "station")
        self.log = os.path.join(self.tmp.name, "run.log")
        self.client = os.path.join(self.tmp.name, "client.ps1")
        self.preflight_tool = os.path.join(self.tmp.name, "preflight.ps1")
        os.makedirs(self.state)
        self.runs = 0
        with open(self.client, "w", encoding="utf-8-sig") as f:
            f.write(STATION)
        with open(self.preflight_tool, "w", encoding="utf-8-sig") as f:
            f.write(PREFLIGHT)
        self.write_profile()

    def tearDown(self):
        self.tmp.cleanup()

    def write_profile(self, endpoint=SIM_ENDPOINT, profile_id=SIM_ID):
        folder = os.path.join(self.station, "profiles", "SIM-IC7300")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "profile.json"), "w", encoding="utf-8") as f:
            json.dump({"profile_id": profile_id, "callsign": OWN, "control": {"endpoint": endpoint}}, f)

    def run_driver(self, scenario, item=None):
        """Each run of a test is its own acceptance item unless `item` is named."""
        self.runs += 1
        item = item or str(self.runs)
        path = os.path.join(self.tmp.name, "scenario.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(scenario.d, f)
        if os.path.exists(self.log):
            os.unlink(self.log)
        rc, out = pwsh.run(DRIVER, ["-Holder", "run7", "-Issue", "192", "-Item", item, "-Station", self.station,
                                    "-StateDir", self.state, "-AgentClient", self.client, "-Preflight", self.preflight_tool],
                           env={"QSO_SCENARIO": path, "QSO_LOG": self.log}, timeout=900)
        return rc, out

    def events(self, kind=None):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
        return [r for r in rows if kind is None or r["kind"] == kind]

    def commands(self, action=None):
        return [e for e in self.events("command") if action is None or e["action"] == action]

    def preflights(self):
        return [e for e in self.events("preflight") if e["what"] != "status"]

    def keys(self):
        return self.events("key")

    def verdict(self):
        with open(os.path.join(self.state, "qso-tests.jsonl"), encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()][-1]

    def assert_not_tested(self, rc, out, text):
        self.assertEqual(rc, 3, out)
        v = self.verdict()
        self.assertEqual(v["verdict"], "not_tested", out)
        self.assertTrue(any(text in n for n in v["not_tested"]), f"{text!r} not in {v['not_tested']}\n{out}")
        return v

    def assert_failed(self, rc, out, text):
        self.assertEqual(rc, 1, out)
        v = self.verdict()
        self.assertEqual(v["verdict"], "failed", out)
        self.assertTrue(any(text in w for w in v["wrong_actions"]), f"{text!r} not in {v['wrong_actions']}\n{out}")
        return v


class DriverTests(DriverBase):
    # --- Profile guard, power, Tx frequency and the pass ---

    # Proves: TC-171-05
    def test_a_complete_qso_on_the_simulator_passes_with_the_bounds_kept(self):
        rc, out = self.run_driver(standard().complete_qso())
        self.assertEqual(rc, 0, out)
        self.assertIn("QSO-TEST PASSED", out)
        v = self.verdict()
        self.assertEqual((v["verdict"], v["wrong_actions"], v["not_tested"], v["contact_id"]), ("passed", [], [], "contact-1"))
        # The preflight: 0128 and 0255 on SIM-IC7300's port, lease 90 min, then the restore.
        pre = self.preflights()
        self.assertEqual([p["what"] for p in pre], ["0128", "0255", "restore"])
        for p in pre[:2]:
            self.assertEqual((p["holder"], p["minutes"], p["port"], p["baud"]), ("run7", 90, "COM4", "115200"))
        # 0128 before Tune, Tune before 0255; Tune is not counted.
        tune_on = self.commands("tune")[0]
        self.assertEqual(tune_on["body"]["enabled"], True)
        self.assertLess(pre[0]["t"], tune_on["t"])
        self.assertLess(tune_on["t"], pre[1]["t"])
        self.assertEqual([t["text"] for t in v["transmissions"]], ["K1ABC HB9BLA JN47", "K1ABC HB9BLA R-12", "K1ABC HB9BLA 73"])
        # Hold Tx Freq on and tx_hz set before the first call; the reply moved rx_hz.
        actions = [c["action"] for c in self.commands()]
        reply = actions.index("reply")
        self.assertEqual(actions[reply - 2:reply], ["set_hold_tx", "set_frequency"])
        self.assertEqual(self.commands("set_hold_tx")[0]["body"]["enabled"], True)
        self.assertEqual(self.commands("set_frequency")[0]["body"]["rx_hz"], 1200)
        self.assertEqual(self.commands("set_frequency")[0]["body"]["tx_hz"], 1250)
        # One cycle: his CQ at 60 s is the second decoded period after a CQ (published at 73 s).
        self.assertEqual(self.commands("reply")[0]["t"], 73_000)
        self.assertEqual(self.commands("reply")[0]["dx"], "K1ABC")
        # At the end all three, Hold Tx Freq, rx_hz and tx_hz, read the values recorded at the start.
        self.assertEqual(v["after"], {"hold_tx": False, "rx_hz": 1200, "tx_hz": 1500})
        last = self.commands("set_frequency")[-1]["body"]
        self.assertEqual((last["rx_hz"], last["tx_hz"]), (1200, 1500))
        self.assertNotIn("halt", actions, "PTT was released: no Halt")
        self.assertNotIn("abort", actions)

    # Proves: TC-171-05
    def test_no_radio_ready_within_60_s_is_not_tested_and_nothing_keys(self):
        rc, out = self.run_driver(standard(Scenario(ready_ms=None)))
        self.assert_not_tested(rc, out, "did not read ready within 60 s")
        self.assertEqual(self.commands("tune"), [])
        self.assertEqual(self.commands("reply"), [])
        self.assertEqual(self.keys(), [])
        self.assertEqual([p["what"] for p in self.preflights()], ["0128", "restore"])

    # Proves: TC-171-05
    def test_the_operator_profile_is_refused_before_any_preflight(self):
        s = standard()
        s.d["transmit"]["profile_id"] = OPERATOR_ID
        rc, out = self.run_driver(s)
        self.assertEqual(rc, 2, out)
        self.assertIn("agents key only the simulator", out)
        self.assertEqual(self.events("preflight"), [])
        self.assertEqual(self.commands(), [])

    # Proves: TC-171-05
    def test_an_endpoint_on_com3_or_one_that_does_not_parse_is_refused(self):
        for endpoint in ("icom7300://COM3?baud=9600&radio=94", "icom7300://COM4", "serial:COM4@115200", ""):
            self.write_profile(endpoint=endpoint)
            rc, out = self.run_driver(standard())
            self.assertEqual(rc, 2, f"{endpoint}: {out}")
            self.assertEqual(self.events("preflight"), [], endpoint)
            self.assertEqual(self.commands(), [], endpoint)

    # Proves: TC-171-05
    def test_a_profile_change_before_the_call_keys_nothing_and_runs_the_stop_order(self):
        rc, out = self.run_driver(standard().end_at(70_000))
        v = self.assert_not_tested(rc, out, "agents key only the simulator")
        self.assertEqual(self.commands("reply"), [])
        self.assertEqual(self.keys(), [])
        self.assertIn("restore", [p["what"] for p in self.preflights()])
        self.assertEqual(v["transmissions"], [])

    # --- profile_id in every command (item 3): the station refuses another profile itself ---

    def refused(self, scenario, action):
        """The station switched to the operator profile after the driver's last read of it: the
        command carries SIM-IC7300's profile_id, is refused with wrong_profile, and the driver
        stops; nothing is sent to the station after it but the power restore."""
        rc, out = self.run_driver(scenario)
        v = self.assert_not_tested(rc, out, "wrong_profile")
        refused = [e for e in self.events("refused") if e["action"] == action]
        self.assertEqual(len(refused), 1, out)
        self.assertEqual(refused[0]["body"]["profile_id"], SIM_ID)
        self.assertEqual(self.commands(action), [], f"{action} reached the operator profile")
        events = self.events()
        later = [e for e in events[events.index(refused[0]) + 1:] if e["kind"] in ("command", "refused")]
        self.assertEqual(later, [], "the driver went on after wrong_profile")
        self.assertEqual(self.preflights()[-1]["what"], "restore", "the power is still restored")
        return v

    @staticmethod
    def switched(view="contact"):
        return {"_running": OPERATOR_ID, view: {"profile_id": OPERATOR_ID}}

    # Proves: TC-171-05
    def test_tune_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        self.refused(standard().change(self.switched(), at=2_500), "tune")
        self.assertEqual([p["what"] for p in self.preflights()], ["0128", "restore"], "no 0255 write")

    # Proves: TC-171-05
    def test_set_hold_tx_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        self.refused(standard().change(self.switched(), at=73_000), "set_hold_tx")

    # Proves: TC-171-05
    def test_set_frequency_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        self.refused(standard().change(self.switched(), after="set_hold_tx"), "set_frequency")

    # Proves: TC-171-05
    def test_reply_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        self.refused(standard().change(self.switched(), after="set_frequency"), "reply")
        self.assertEqual(self.keys(), [])

    # Proves: TC-171-05
    def test_abort_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        s = standard().disarm("band_changed")
        s.change(self.switched(), after="key", nth=1, delay=500)
        self.refused(s, "abort")

    # Proves: TC-171-05
    def test_halt_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        s = standard()
        s.change({"transmit": {"ptt": "asserted"}, "_key": {"stuck": True}}, after="key", nth=1, delay=400)
        s.disarm("band_changed")
        s.change(self.switched("transmit"), after="abort")
        self.refused(s, "halt")

    # Proves: TC-171-05
    def test_auto_off_carries_the_sim_profile_id_and_wrong_profile_stops_the_run(self):
        s = standard()
        s.d["automation"]["run"] = {"id": "66666666-6666-4666-8666-666666666666", "state": "contact_active"}
        s.disarm("band_changed", name="disarm")
        # After the poll that reads the stop: the GET /automation of that poll.
        s.change(self.switched("transmit"), after="change:disarm", then="get:/automation")
        self.refused(s, "auto_stop")
        self.assertEqual(self.commands("abort"), [], "the abort after Auto off is not sent")

    # --- Targets ---

    # Proves: TC-171-05
    def test_only_a_general_standard_cq_not_worked_on_this_band_and_mode_is_called(self):
        s = Scenario()
        periods = range(0, 20 * 30_000, 30_000)
        s.cq("K1NON", periods, 1100.0, kind="nonstandard")
        s.cq("K2DIR", periods, 1150.0, to_kind="token")  # see below: CQ DX
        for r in s.d["records"]:
            if r["record"]["fields"]["from"]["text"] == "K2DIR":
                r["record"]["fields"]["to"]["text"] = "CQ DX"
        for call, kind, hz in (("K3FD", "field_day", 1200.0), ("K4RT", "rtty", 1250.0), ("K5VHF", "vhf", 1300.0),
                               ("K6DXP", "dxpedition", 1350.0)):
            s.cq(call, periods, hz, kind=kind)
        s.cq("K7WRK", periods, 1400.0, worked="worked_this_band_and_mode")
        s.cq("K8ABS", periods, 1450.0, worked=None)
        s.cq("K0REP", range(0, 30_001, 30_000), 1600.0)
        s.record(60_000, rec("K0REP", "DL1ZZZ", 1600.0, exchange=("report", -5)))
        s.cq("K9OK", range(0, 20 * 30_000, 30_000), 1700.0, worked="worked_other_band_or_mode")
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        self.assertEqual([c["dx"] for c in self.commands("reply")], ["K9OK"], out)

    # Proves: TC-171-05
    def test_one_caller_after_his_last_two_cqs_is_no_pile_up(self):
        s = standard()
        s.record(15_000, rec("DL1AAA", "K1ABC", 1500.0)).record(45_000, rec("DL1AAA", "K1ABC", 1500.0))
        s.disarm("band_changed")
        self.run_driver(s)
        self.assertEqual([c["dx"] for c in self.commands("reply")], ["K1ABC"])

    # Proves: TC-171-05
    def test_two_callers_after_his_last_two_cqs_skip_him_and_two_after_an_older_third_do_not_count(self):
        s = standard(call="K1PIL")
        for period in range(15_000, 2_100_000, 30_000):
            s.record(period, rec("DL1AAA", "K1PIL", 1500.0)).record(period, rec("DL2BBB", "K1PIL", 1500.0))
        s.cq("K2OLD", range(0, 2_100_000, 30_000), 1700.0)
        # Two callers after his CQ at 0 s; after his CQs at 30 and 60 s only one. At 73 s the
        # periods after his CQs at 0 and 30 s are the decoded ones (skipped); from 88 s, when
        # the period from 75 s is published, those after 30 and 60 s: called in his next
        # (even) period, at 90 s.
        s.record(15_000, rec("DL3CCC", "K2OLD", 1700.0)).record(15_000, rec("DL4DDD", "K2OLD", 1700.0))
        s.record(75_000, rec("DL3CCC", "K2OLD", 1700.0))
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        self.assertEqual([(c["dx"], c["t"]) for c in self.commands("reply")], [("K2OLD", 90_000)], out)

    # Proves: TC-171-05
    def test_with_one_decoded_period_after_a_cq_it_waits_then_calls_after_the_second(self):
        s = Scenario().cq("K1ABC", range(30_000, 40 * 30_000, 30_000))
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        # 45 s follows his CQ at 30 s and is decoded at 73 s; 75 s follows his CQ at 60 s and is
        # decoded once 90 s is published, at 103 s, in his (even) period from 90 s.
        reply = self.commands("reply")
        self.assertEqual(len(reply), 1, out)
        self.assertEqual(reply[0]["t"], 103_000)

    # Proves: TC-171-05
    def test_a_cq_again_within_two_cycles_keeps_him_and_a_missing_cq_or_a_reply_drops_him(self):
        s = Scenario()
        s.cq("K3STAY", [0, 30_000, 90_000, 150_000, 210_000], 1500.0)  # 60 s gaps: within two cycles
        s.cq("K1GONE", [0, 30_000], 1700.0)  # no CQ after 30 s
        s.cq("K2REP", [0, 30_000, 60_000], 1100.0)
        s.record(90_000, rec("K2REP", "DL5EEE", 1100.0, exchange=("report", -3)))
        s.record(15_000, rec("DL9ZZZ", "K9ZZZ", 900.0)).record(75_000, rec("DL9ZZZ", "K9ZZZ", 900.0))
        s.d["builds"] = [{"from": 0, "build": None}, {"from": 106_000, "build": {"rx_parity": "alternate", "open": [[1000, 1300]]}}]
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        self.assertEqual([c["dx"] for c in self.commands("reply")], ["K3STAY"], out)
        self.assertIn("K1GONE dropped", out)

    # --- Tx frequency ---

    def tx_for(self, opened, hz):
        s = Scenario().cq("K1ABC", range(0, 600_000, 30_000), hz)
        s.d["builds"] = [{"from": 0, "build": {"rx_parity": "alternate", "open": opened}}]
        s.disarm("band_changed")
        s.end_at(200_000)
        self.run_driver(s)
        commands = self.commands()
        # The tx_hz set just before each call.
        return [c["body"]["tx_hz"] for c, nxt in zip(commands, commands[1:])
                if c["action"] == "set_frequency" and nxt["action"] == "reply"]

    # Proves: TC-171-05
    def test_an_open_range_gives_lo_to_hi_minus_the_signal_width(self):
        self.assertEqual(self.tx_for([[1000, 1100]], 1500.0), [1050])
        self.assertEqual(self.tx_for([[1000, 1049]], 1500.0), [], "no f fits: no call")
        self.assertEqual(self.commands("reply"), [])

    # Proves: TC-171-05
    def test_the_nearest_f_clear_of_his_signal_is_taken_and_else_the_lo_of_the_nearest_range(self):
        # His signal at 1100: 1180 is the top of [1000, 1230] but 80 Hz from him; 1000 is clear.
        self.assertEqual(self.tx_for([[1000, 1230]], 1100.0), [1000])
        # Two ranges: 1200 (100 Hz above him, in the second) is nearer than 940 (160 Hz below).
        self.assertEqual(self.tx_for([[600, 990], [1150, 1280]], 1100.0), [1200])
        # Nothing clear of him at 1050 (every f within 100 Hz): the lo of the range nearest him.
        self.assertEqual(self.tx_for([[1000, 1080], [1100, 1160]], 1050.0), [1000])

    # Proves: TC-171-05
    def test_another_parity_a_null_build_or_no_open_range_gives_no_call_until_a_fitting_build(self):
        s = standard()
        s.d["builds"] = [{"from": 0, "build": None},
                         {"from": 80_000, "build": {"rx_parity": "alternate", "open": []}},
                         {"from": 100_000, "build": {"rx_parity": "odd", "open": [[1000, 1300]]}},
                         {"from": 125_000, "build": {"rx_parity": "alternate", "open": [[1000, 1300]]}}]
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        reply = self.commands("reply")
        self.assertEqual(len(reply), 1, out)
        self.assertEqual(reply[0]["t"], 125_000, "the first moment with a fitting build, in his even period")

    # --- SWR and power ---

    def swr_case(self, *pushes):
        s = standard().pushes(*pushes)
        rc, out = self.run_driver(s)
        self.assertEqual([p["what"] for p in self.preflights()], ["0128", "restore"], out)
        self.assertEqual(self.commands("reply"), [])
        self.assertEqual(self.keys(), [])
        self.assertIn("ASK THE OPERATOR", out)
        return rc, out

    def push(self, delay, meters, warnings=()):
        return {"after": "tune", "nth": 1, "delay": delay, "data": {"meters": meters, "warnings": list(warnings)}}

    # Proves: TC-171-05
    def test_a_push_before_tune_and_none_during_it_is_no_fresh_reading(self):
        rc, out = self.swr_case({"at": 0, "data": {"meters": {"alc": 0, "po_pct": 40, "swr_x10": 10}, "warnings": []}})
        self.assert_not_tested(rc, out, "no fresh reading")

    # Proves: TC-171-05
    def test_null_meters_po_0_swr_30_or_swr_fault_write_no_0255(self):
        for push, text in ((self.push(1000, None), "no fresh reading"),
                           (self.push(1000, {"alc": 0, "po_pct": None, "swr_x10": 12}), "no fresh reading"),
                           (self.push(1000, {"alc": 0, "po_pct": 0, "swr_x10": 12}), "po_pct 0"),
                           (self.push(1000, {"alc": 0, "po_pct": 40, "swr_x10": 30}), "swr_x10 30"),
                           (self.push(1000, {"alc": 0, "po_pct": 40, "swr_x10": 12}, ["swr_fault"]), "swr_fault")):
            with self.subTest(text=text):
                rc, out = self.swr_case(push)
                self.assert_not_tested(rc, out, text)

    # Proves: TC-171-05
    def test_po_1_and_swr_29_go_on_to_0255(self):
        s = standard().pushes(self.push(500, {"alc": 0, "po_pct": 1, "swr_x10": 29}),
                              self.push(1500, {"alc": 0, "po_pct": 0, "swr_x10": 20}))
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        self.assertEqual([p["what"] for p in self.preflights()][:2], ["0128", "0255"], out)
        self.assertEqual(self.verdict()["swr_x10"], 29)

    # --- Count and time ---

    # Proves: TC-171-05
    def test_four_calls_to_one_station_then_another_and_ten_in_total_then_not_tested(self):
        s = Scenario()
        for call, hz in (("K1AAA", 1500.0), ("K2BBB", 1600.0), ("K3CCC", 1700.0)):
            s.cq(call, range(0, 60 * 30_000, 30_000), hz)
        rc, out = self.run_driver(s)
        v = self.assert_not_tested(rc, out, "10 transmissions")
        keyed = [k["text"].split()[0] for k in self.keys()]
        self.assertEqual(len(keyed), 10, out)
        for call in ("K1AAA", "K2BBB"):
            self.assertEqual(keyed.count(call), 4, keyed)
        self.assertEqual(len(v["transmissions"]), 10, "Tune and the waiting periods are not counted")
        self.assertEqual(len(self.commands("abort")), 3)
        self.assert_no_send_cut()

    def assert_no_send_cut(self):
        """Every abort lands after the send before it has ended and before the next own period:
        no send is cut, and none starts after the limit."""
        self.assertEqual(self.events("cut"), [], "a send was cut on the air")
        keys = self.keys()
        for abort in self.commands("abort"):
            before = [k for k in keys if k["period"] <= abort["t"]][-1]
            self.assertGreaterEqual(abort["t"], before["period"] + 12_640, f"abort {abort['t']} inside the send of {before['period']}")
            self.assertLess(abort["t"], before["period"] + 2 * LEN, f"abort {abort['t']} after the next own period of {before['period']}")

    # Proves: TC-171-05
    def test_a_limit_never_cuts_a_running_send(self):
        # One station that never answers: its 4th call is the limit. Then two more: the 10th
        # transmission is. Each abort waits for the send to end and comes before the next period.
        s = Scenario()
        for call, hz in (("K1AAA", 1500.0), ("K2BBB", 1600.0), ("K3CCC", 1700.0)):
            s.cq(call, range(0, 60 * 30_000, 30_000), hz)
        rc, out = self.run_driver(s)
        self.assert_not_tested(rc, out, "10 transmissions")
        aborts = [a["t"] for a in self.commands("abort")]
        # The 4th call to K1AAA is keyed at 165 s and ends at 177.64 s; the next own period is
        # 195 s. K2BBB's 4th at 285 s ends at 297.64 s; the 10th, to K3CCC at 345 s, at 357.64 s.
        self.assertEqual(aborts, [178_000, 298_000, 358_000], out)
        self.assert_no_send_cut()
        keyed = [k["text"].split()[0] for k in self.keys()]
        self.assertEqual((keyed.count("K1AAA"), keyed.count("K2BBB"), len(keyed)), (4, 4, 10), "no 5th and no 11th")

    # Proves: TC-171-05
    def test_a_tx_watchdog_of_7_ends_the_run_before_keying(self):
        rc, out = self.run_driver(standard(Scenario(tx_calls=7)).complete_qso())
        self.assert_not_tested(rc, out, "Tx watchdog is 7")
        self.assertEqual(self.events("preflight"), [])
        self.assertEqual(self.commands(), [])

    def first_call_at(self, at):
        s = standard()
        s.d["builds"] = [{"from": 0, "build": None}, {"from": at, "build": {"rx_parity": "alternate", "open": [[1000, 1300]]}}]
        s.disarm("band_changed")
        return s

    # Proves: TC-171-05
    def test_a_first_call_at_29_59_after_the_0255_read_back_goes_out(self):
        rc, out = self.run_driver(self.first_call_at(T255 + 1_799_000))
        self.assertEqual([c["t"] for c in self.commands("reply")], [T255 + 1_799_000], out)

    # Proves: TC-171-05
    def test_no_first_call_by_30_00_is_not_tested(self):
        rc, out = self.run_driver(self.first_call_at(T255 + 1_800_000))
        self.assert_not_tested(rc, out, "no call within 30 minutes")
        self.assertEqual(self.commands("reply"), [])

    def long_qso(self, done_after):
        s = standard()
        s.answer(rec("K1ABC", OWN, 1500.0, exchange=("report", -10), text=f"{OWN} K1ABC -10"), nth=1)
        dialogue = [{"dir": "tx", "text": f"K1ABC {OWN} JN47", "period_utc_ms": None, "count": 1},
                    {"dir": "rx", "text": f"{OWN} K1ABC -10", "period_utc_ms": None, "count": 1},
                    {"dir": "tx", "text": f"K1ABC {OWN} R-12", "period_utc_ms": None, "count": 1},
                    {"dir": "rx", "text": f"{OWN} K1ABC RR73", "period_utc_ms": None, "count": 1}]
        s.change({"contact": {"contact": {"state": "report", "dialogue": dialogue[:2]}},
                  "_key": {"text": "{dx} " + OWN + " R-12"}}, after="key", nth=1, delay=LEN + 13_000)
        if done_after is not None:
            s.change({"contact": {"contact": {"state": "completed", "dialogue": dialogue},
                                  "log": {"contact_id": "contact-1", "call": "K1ABC", "outcome": "saved", "error": None}},
                      "transmit": {"transmit": {"arm_state": "disarmed", "last_disarm_cause": "contact_completed"}},
                      "_key": {"enabled": False}}, after="reply", delay=done_after)
        return s

    # Proves: TC-171-05
    def test_a_qso_completed_at_29_59_from_the_first_call_goes_on(self):
        rc, out = self.run_driver(self.long_qso(1_799_000))
        self.assertEqual(rc, 0, out)
        self.assertEqual(self.commands("abort"), [])

    # Proves: TC-171-05
    def test_the_backstop_at_30_00_aborts_before_rr73_unlogged_and_fails(self):
        rc, out = self.run_driver(self.long_qso(None))
        self.assertEqual(rc, 1, out)
        v = self.verdict()
        self.assertEqual((v["verdict"], v["backstop"]), ("failed", True))
        abort = self.commands("abort")
        self.assertEqual(len(abort), 1, out)
        self.assertEqual(abort[0]["t"], self.commands("reply")[0]["t"] + 1_800_000)
        self.assertTrue(any("unlogged" in o for o in v["observations"]), v["observations"])
        actions = [c["action"] for c in self.commands()]
        self.assertLess(actions.index("abort"), len(actions) - 2, "abort before the set back")

    # --- Stop ---

    # Proves: TC-171-05
    def test_a_contact_at_rogers_or_signoff_is_not_aborted_and_ends_before_the_restore(self):
        for state in ("rogers", "signoff"):
            with self.subTest(state=state):
                s = standard()
                s.answer(rec("K1ABC", OWN, 1500.0, exchange=("report", -10), text=f"{OWN} K1ABC -10"), nth=1)
                s.change({"contact": {"contact": {"state": state}}, "_key": {"text": "{dx} " + OWN + " RR73"}},
                         after="key", nth=1, delay=LEN + 13_000)
                # The station's tx watchdog ends the run (not tested); the contact ends 40 s later.
                s.disarm("tx_watchdog", nth=2, delay=500)
                s.change({"contact": {"contact": {"state": "completed"}}, "_key": {"enabled": False}},
                         after="key", nth=2, delay=40_000)
                rc, out = self.run_driver(s)
                self.assert_not_tested(rc, out, "tx_watchdog")
                self.assertEqual(self.commands("abort"), [])
                done = [c for c in self.events("change") if c["t"] >= self.keys()[1]["t"] + 40_000][0]["t"]
                restore = [p for p in self.preflights() if p["what"] == "restore"][0]["t"]
                self.assertLess(done, restore)

    # Proves: TC-171-05
    def test_halt_only_while_ptt_is_keyed(self):
        s = standard()
        s.change({"transmit": {"ptt": "asserted"}, "_key": {"stuck": True}}, after="key", nth=1, delay=400)
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        actions = [c["action"] for c in self.commands()]
        self.assertEqual(actions.count("halt"), 1, out)
        self.assertLess(actions.index("abort"), actions.index("halt"), "Halt after the abort")

    # Proves: TC-171-05
    def test_a_busy_restore_is_retried_every_10_s(self):
        s = standard()
        s.d["preflight"] = {"restore": [3, 3, 0]}
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        restores = [p["t"] for p in self.preflights() if p["what"] == "restore"]
        self.assertEqual(len(restores), 3, out)
        self.assertEqual([b - a for a, b in zip(restores, restores[1:])], [10_000, 10_000])

    # Proves: TC-171-05
    def test_with_the_lease_expired_the_first_pass_record_is_restored_on_its_port(self):
        with open(os.path.join(self.state, "preflight.jsonl"), "w", encoding="utf-8") as f:
            for old, target in ((174, 128), (128, 255)):
                f.write(json.dumps({"holder": "run7", "restore": False, "port": "COM4", "baud": 115200,
                                    "rf_power_old_bcd": old, "rf_power_target_bcd": target,
                                    "rf_power_read_bcd": target, "verdict": "PASS"}) + "\n")
        s = standard()
        s.change({"_lease": None}, after="key", nth=1, delay=100)
        s.disarm("band_changed")
        rc, out = self.run_driver(s)
        after = [p for p in self.events("preflight") if p["t"] > self.keys()[0]["t"]]
        self.assertEqual([(p["what"], p["port"], p["baud"]) for p in after if p["what"] != "status"],
                         [("0174", "COM4", "115200"), ("release", "", "")], out)
        self.assertNotIn("0128", [p["what"] for p in after], "never the value of a later record")

    # Proves: TC-171-05
    def test_a_contact_the_driver_did_not_start_is_never_aborted(self):
        s = standard()
        s.change({"contact": {"contact": {"id": "operator-9", "dx_call": "W1OP", "state": "report"}}},
                 after="key", nth=1, delay=300)
        s.disarm("operator", delay=500)
        rc, out = self.run_driver(s)
        self.assert_not_tested(rc, out, "operator")
        self.assertEqual(self.commands("abort"), [])

    # --- Verdicts ---

    # Proves: TC-171-05
    def test_a_new_transmission_while_the_transmit_state_is_off_fails_a(self):
        s = standard()
        s.d["key"]["arm_on_reply"] = False
        rc, out = self.run_driver(s)
        self.assert_failed(rc, out, "(a)")

    # Proves: TC-171-05
    def test_a_keyed_cq_or_a_message_to_another_call_fails_b(self):
        for text in ("CQ " + OWN + " JN47", "K7OTH " + OWN + " JN47"):
            with self.subTest(text=text):
                s = standard()
                s.d["key"]["text"] = text
                rc, out = self.run_driver(s)
                self.assert_failed(rc, out, "(b)")

    def busy(self, patches, auto=False):
        s = standard()
        if auto:
            s.d["automation"]["run"] = {"id": "66666666-6666-4666-8666-666666666666", "state": "contact_active"}
        for delay, patch in patches:
            s.change({"contact": patch}, after="key", nth=1, delay=delay)
        s.disarm("band_changed", delay=6000)
        return self.run_driver(s)

    # Proves: TC-171-05
    def test_a_tx_hz_change_with_hold_on_fails_c_unless_it_is_the_busy_move_or_auto(self):
        rc, out = self.busy([(2000, {"settings": {"tx_hz": 1777}})])
        self.assert_failed(rc, out, "(c)")
        rc, out = self.busy([(2000, {"settings": {"tx_hz": 1777}, "watchdog": {"busy_with": "K5XYZ"}})])
        self.assertEqual(self.verdict()["wrong_actions"], [], out)
        rc, out = self.busy([(1000, {"watchdog": {"busy_with": "K5XYZ"}}),
                             (3000, {"settings": {"tx_hz": 1777}, "watchdog": {"busy_with": None}})])
        self.assertEqual(self.verdict()["wrong_actions"], [], "the step that clears busy_with: " + out)
        rc, out = self.busy([(2000, {"settings": {"tx_hz": 1777}})], auto=True)
        self.assertEqual(self.verdict()["wrong_actions"], [], "Auto: " + out)
        self.assertIn("auto_stop", [c["action"] for c in self.commands()], "Auto off first in the stop order")

    # Proves: TC-171-05
    def test_one_message_keyed_more_often_than_the_tx_watchdog_allows_fails_d(self):
        s = standard()
        s.change({"contact": {"contact": {"dialogue": [{"dir": "tx", "text": f"K1ABC {OWN} JN47", "period_utc_ms": None, "count": 7}]}}},
                 after="key", nth=1, delay=300)
        rc, out = self.run_driver(s)
        self.assert_failed(rc, out, "(d)")

    # Proves: TC-171-05
    def test_a_completed_contact_logged_unsaved_fails_e(self):
        rc, out = self.run_driver(standard().complete_qso(log="unsaved", error="disk_full"))
        self.assert_failed(rc, out, "(e)")

    # Proves: TC-171-05
    def test_the_previous_message_again_in_the_second_own_period_after_an_advancing_decode_fails_f(self):
        rc, out = self.run_driver(standard().complete_qso(change_text=False))
        self.assert_failed(rc, out, "(f)")

    # Proves: TC-171-05
    def test_a_wrong_action_followed_by_device_lost_fails(self):
        s = standard()
        s.change({"contact": {"settings": {"tx_hz": 1777}}}, after="key", nth=1, delay=2000)
        s.disarm("device_lost", delay=2500)
        rc, out = self.run_driver(s)
        self.assert_failed(rc, out, "(c)")

    # Proves: TC-171-05
    def test_a_watchdog_stop_during_a_send_on_the_air_is_no_a(self):
        s = standard()
        s.disarm("tx_watchdog", delay=200)
        rc, out = self.run_driver(s)
        v = self.assert_not_tested(rc, out, "tx_watchdog")
        self.assertEqual(v["wrong_actions"], [])
        self.assertEqual(len(v["transmissions"]), 1)

    # Proves: TC-171-05
    def test_a_start_and_a_stop_between_two_polls_is_judged_on_the_earlier_state(self):
        s = standard()
        s.d["key"].update({"arm_on_reply": False, "first_delay": 300})
        s.disarm("tx_watchdog", delay=100)
        rc, out = self.run_driver(s)
        v = self.assert_not_tested(rc, out, "tx_watchdog")
        self.assertEqual(v["wrong_actions"], [])
        self.assertEqual(len(v["transmissions"]), 1)

    # Proves: TC-171-05
    def test_partner_silence_ended_by_the_tx_watchdog_in_phase_2_is_not_tested_with_the_observation(self):
        s = standard()
        s.answer(rec("K1ABC", OWN, 1500.0, exchange=("report", -10), text=f"{OWN} K1ABC -10"), nth=1)
        s.change({"contact": {"contact": {"state": "report"}}, "_key": {"text": "{dx} " + OWN + " R-12"}},
                 after="key", nth=1, delay=LEN + 13_000)
        s.disarm("tx_watchdog", nth=4, delay=500)
        rc, out = self.run_driver(s)
        v = self.assert_not_tested(rc, out, "tx_watchdog")
        self.assertEqual((v["last_disarm_cause"], v["wrong_actions"]), ("tx_watchdog", []))
        self.assertEqual(len(self.commands("abort")), 1, "the unfinished contact is aborted")

    # Proves: TC-171-05
    def test_each_other_end_of_a_transmission_is_not_tested_with_its_cause_and_failure(self):
        for cause, failure, refusal in (("refused", None, "not_authorized"), ("failed", "audio_stalled", None),
                                        ("failed", "ptt_timeout", None), ("device_lost", None, None),
                                        ("band_changed", None, None), ("run_ended", None, None), ("halt", None, None)):
            with self.subTest(cause=cause, failure=failure):
                s = standard()
                s.disarm(cause, failure=failure, refusal=refusal)
                rc, out = self.run_driver(s)
                v = self.assert_not_tested(rc, out, f"last_disarm_cause {cause}")
                self.assertEqual((v["last_disarm_cause"], v["failure"], v["refusal"]), (cause, failure, refusal))

    # Proves: TC-171-05
    def test_the_third_attempt_runs_and_the_fourth_is_refused_naming_the_operator(self):
        with open(os.path.join(self.state, "qso-tests.jsonl"), "w", encoding="utf-8") as f:
            for attempt in (1, 2):
                for item in ("4", "5"):
                    f.write(json.dumps({"issue": "192", "item": item, "revision": REV_A, "radio": SIM_ID,
                                        "attempt": attempt, "verdict": "not_tested"}) + "\n")
        s = standard()
        s.disarm("band_changed")
        rc, out = self.run_driver(s, item="4")
        self.assertEqual(rc, 3, out)
        v = self.verdict()
        self.assertEqual((v["attempt"], v["revision"], v["radio"]), (3, REV_A, SIM_ID))
        self.assertIn("ASK THE OPERATOR", out, "a third not tested goes to the operator")
        rc, out = self.run_driver(s, item="4")
        self.assertEqual(rc, 4, out)
        self.assertIn("operator", out)
        self.assertEqual(self.events(), [], "a refused attempt touches nothing")


class AttemptTests(DriverBase):
    """Attempts per deployed revision and radio (TC-192-04): the scripted client replaces the
    revision seam, and qso-tests.jsonl is prepared. Each run ends quickly after the 0128
    preflight (GET /radio never reads ready), so a run that is not refused calls the preflight."""

    def prepare(self, *rows):
        """rows: (revision, radio, item, count); revision None writes the form without one."""
        lines = []
        for revision, radio, item, count in rows:
            for n in range(count):
                r = {"issue": "192", "item": item, "attempt": n + 1, "verdict": "not_tested"}
                if revision is not None:
                    r.update({"revision": revision, "radio": radio})
                lines.append(json.dumps(r))
        path = os.path.join(self.state, "qso-tests.jsonl")
        with open(path, "w", encoding="utf-8") as f:
            f.write("".join(line + "\n" for line in lines))
        return lines

    def records(self):
        path = os.path.join(self.state, "qso-tests.jsonl")
        with open(path, encoding="utf-8") as f:
            return [line.rstrip("\n") for line in f if line.strip()]

    def attempt(self, revision=REV_A, radio=SIM_ID):
        s = Scenario(ready_ms=None)
        s.d["revision"] = revision if isinstance(revision, list) else [revision]
        if radio != SIM_ID:
            # The station reports the other radio's profile: the guard would refuse it, so the
            # profile file names that radio as SIM-IC7300's for this count-only case.
            self.write_profile(profile_id=radio)
            for view in ("transmit", "contact", "automation"):
                s.d[view]["profile_id"] = radio
        return self.run_driver(s, item="4")

    def assert_attempt(self, rc, out, n, revision=REV_A, radio=SIM_ID):
        v = self.assert_not_tested(rc, out, "did not read ready")
        self.assertEqual((v["attempt"], v["revision"], v["radio"]), (n, revision, radio), out)
        self.assertIn("0128", [p["what"] for p in self.preflights()], "the preflight is called")
        return v

    # Proves: TC-192-04
    def test_attempts_count_per_revision(self):
        self.prepare((REV_A, SIM_ID, "4", 2))
        rc, out = self.attempt()
        self.assert_attempt(rc, out, 3)

    # Proves: TC-192-04
    def test_a_new_revision_starts_at_0(self):
        self.prepare((REV_A, SIM_ID, "4", 3))
        rc, out = self.attempt(REV_B)
        self.assert_attempt(rc, out, 1, REV_B)

    # Proves: TC-192-04
    def test_an_older_revision_is_ignored(self):
        self.prepare((REV_A, SIM_ID, "4", 3), (REV_B, SIM_ID, "4", 1))
        rc, out = self.attempt(REV_B)
        self.assert_attempt(rc, out, 2, REV_B)

    # Proves: TC-192-04
    def test_attempts_count_per_radio(self):
        self.prepare((REV_A, REAL_RADIO, "4", 3))
        rc, out = self.attempt()
        self.assert_attempt(rc, out, 1)
        self.prepare((REV_A, SIM_ID, "4", 3), (REV_A, REAL_RADIO, "4", 2))
        rc, out = self.attempt()
        self.assertEqual(rc, 4, out)

    # Proves: TC-192-04
    def test_the_real_radio_counts_its_own_attempts(self):
        self.prepare((REV_A, SIM_ID, "4", 3))
        rc, out = self.attempt(radio=REAL_RADIO)
        self.assert_attempt(rc, out, 1, radio=REAL_RADIO)

    # Proves: TC-192-04
    def test_a_4th_attempt_on_the_same_revision_and_radio_is_refused_before_the_preflight(self):
        before = self.prepare((REV_A, SIM_ID, "4", 3))
        rc, out = self.attempt()
        self.assertEqual(rc, 4, out)
        line = [x for x in out.splitlines() if "QSO-TEST REFUSED" in x]
        self.assertEqual(len(line), 1, out)
        # The issue is the -Issue argument of run_driver.
        for part in ("#" + "192 item 4", REV_A[:9], SIM_ID, "operator"):
            self.assertIn(part, line[0])
        self.assertNotIn(REV_A[:10], line[0], "the revision is named by its first 9 characters")
        self.assertEqual(self.events("preflight"), [])
        self.assertEqual(self.commands(), [])
        self.assertEqual(self.records(), before, "no record written")

    # Proves: TC-192-04
    def test_records_without_a_revision_never_count_and_stay_unchanged(self):
        before = self.prepare((None, None, "4", 3))
        rc, out = self.attempt()
        self.assert_attempt(rc, out, 1)
        self.assertEqual(self.records()[:3], before, "the old records are kept as they were")

    # Proves: TC-192-04
    def test_records_of_another_item_do_not_count(self):
        self.prepare((REV_A, SIM_ID, "5", 3))
        rc, out = self.attempt()
        self.assert_attempt(rc, out, 1)

    # Proves: TC-192-04
    def test_the_ask_line_counts_per_revision_and_radio(self):
        self.prepare((REV_A, SIM_ID, "4", 2))
        rc, out = self.attempt()
        self.assert_attempt(rc, out, 3)
        self.assertIn("left not tested 3 times", out)
        self.prepare((REV_A, SIM_ID, "4", 3), (REV_B, SIM_ID, "4", 1))
        rc, out = self.attempt(REV_B)
        self.assert_attempt(rc, out, 2, REV_B)
        self.assertNotIn("left not tested", out)
        rc, out = self.attempt(REV_B)
        self.assert_attempt(rc, out, 3, REV_B)
        self.assertIn("left not tested 3 times", out)

    # Proves: TC-192-04
    def test_a_station_without_a_deployed_revision_is_refused(self):
        for name, header in (("missing", []), ("unknown", ["unknown"]), ("twice", [REV_A, REV_A]),
                             ("39 hex", [REV_A[:39]]), ("40 uppercase hex", [REV_A.upper()])):
            with self.subTest(header=name):
                before = self.prepare((REV_A, SIM_ID, "4", 1))
                rc, out = self.attempt(header)
                self.assertEqual(rc, 2, out)
                self.assertIn("no deployed revision", out)
                self.assertEqual(self.events("preflight"), [])
                self.assertEqual(self.commands(), [])
                self.assertEqual(self.records(), before, "no record written")


WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
WS_COOKIE = ("wstx_session", "test-session")
MAX_ID = 9_007_199_254_740_991


class StationEndpoint:
    """A loopback WebSocket endpoint with the station's /ws rules, stated here in one place
    from server/src/main.rs:
    - upgrade: an Origin other than the station's is 403; no session cookie is 401; no
      Sec-WebSocket-Protocol wstx.v1 is 400; otherwise 101 with the protocol wstx.v1;
    - reply: a message whose id is not a JSON integer from 0 to 2^53 - 1, or that has other
      than three keys, is error {code invalid_request}; v other than 1 is unsupported_version;
      any other type is unknown_command;
    - connection: unknown_command for spectrum.off becomes spectrum.subscription with that id
      and profile off and subscribes the socket, or error {code unavailable} without a
      recording; radio.tx_level reaches only a subscribed socket.
    Per case: `upgrade_delay` and `answer_delay` (s) delay the 101 and the subscription answer
    (None: never answered); `status` forces the upgrade status; `refuse` forces an error code
    for the subscription; `unavailable` is the no-recording mode; `close_after_upgrade` sends a
    close frame at once; `pushes` are (delay after the answer in s, message) sent once
    subscribed."""

    def __init__(self, upgrade_delay=0.0, answer_delay=0.0, status=None, refuse=None, unavailable=False,
                 close_after_upgrade=False, pushes=()):
        self.upgrade_delay, self.answer_delay, self.status = upgrade_delay, answer_delay, status
        self.refuse, self.unavailable, self.close_after_upgrade = refuse, unavailable, close_after_upgrade
        self.pushes = list(pushes)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(4)
        self.url = "http://127.0.0.1:%d" % self.listener.getsockname()[1]
        self.headers = None          # the upgrade request's headers, names in lower case
        self.connect_at = None       # wall-clock ms of the TCP accept
        self.messages = []           # (wall-clock ms, parsed message) received
        self.answered = None         # the upgrade status sent
        self.stop = threading.Event()
        self.conns = []
        threading.Thread(target=self.serve, daemon=True).start()

    def close(self):
        self.stop.set()
        for s in [self.listener] + self.conns:
            try:
                s.close()
            except OSError:
                pass

    def serve(self):
        while not self.stop.is_set():
            try:
                conn, _ = self.listener.accept()
            except OSError:
                return
            self.conns.append(conn)
            if self.connect_at is None:
                self.connect_at = time.time() * 1000
            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()

    def recv_exact(self, conn, n):
        data = b""
        while len(data) < n:
            chunk = conn.recv(n - len(data))
            if not chunk:
                raise ConnectionError("peer closed")
            data += chunk
        return data

    def send_frame(self, conn, opcode, payload):
        n = len(payload)
        head = bytes([0x80 | opcode]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n))
        conn.sendall(head + payload)

    def send_json(self, conn, message):
        self.send_frame(conn, 1, json.dumps(message, separators=(",", ":")).encode())

    def read_frame(self, conn):
        b0, b1 = self.recv_exact(conn, 2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", self.recv_exact(conn, 2))[0]
        elif n == 127:
            n = struct.unpack(">Q", self.recv_exact(conn, 8))[0]
        mask = self.recv_exact(conn, 4) if b1 & 0x80 else b"\0\0\0\0"
        data = bytes(c ^ mask[i % 4] for i, c in enumerate(self.recv_exact(conn, n)))
        return b0 & 0x0F, data

    def upgrade_status(self, headers):
        if headers.get("origin") != self.url:
            return 403
        cookies = dict(p.strip().split("=", 1) for p in headers.get("cookie", "").split(";") if "=" in p)
        if cookies.get(WS_COOKIE[0]) != WS_COOKIE[1]:
            return 401
        if headers.get("sec-websocket-protocol") != "wstx.v1":
            return 400
        return 101

    def reply(self, message):
        """The answer to one client message, or None for no answer."""
        mid = message.get("id") if isinstance(message, dict) else None
        valid = isinstance(mid, int) and not isinstance(mid, bool) and 0 <= mid <= MAX_ID
        rid = mid if valid else None
        if not isinstance(message, dict) or not valid or len(message) != 3 or "v" not in message \
                or not isinstance(message.get("type"), str):
            return {"v": 1, "type": "error", "id": rid, "data": {"code": "invalid_request"}}
        if message["v"] != 1:
            return {"v": 1, "type": "error", "id": rid, "data": {"code": "unsupported_version"}}
        if message["type"] != "spectrum.off":
            return {"v": 1, "type": "error", "id": rid, "data": {"code": "unknown_command"}}
        if self.refuse or self.unavailable:
            return {"v": 1, "type": "error", "id": rid, "data": {"code": self.refuse or "unavailable"}}
        return {"v": 1, "type": "spectrum.subscription", "id": rid, "data": {"profile": "off"}}

    def handle(self, conn):
        try:
            raw = b""
            while b"\r\n\r\n" not in raw:
                chunk = conn.recv(4096)
                if not chunk:
                    return
                raw += chunk
            lines = raw.split(b"\r\n\r\n", 1)[0].decode("latin-1").split("\r\n")
            self.headers = {k.strip().lower(): v.strip() for k, v in (h.split(":", 1) for h in lines[1:] if ":" in h)}
            if self.upgrade_delay is None:
                self.stop.wait(60)
                return
            self.stop.wait(self.upgrade_delay)
            status = self.status or self.upgrade_status(self.headers)
            self.answered = status
            if status != 101:
                text = {400: "Bad Request", 401: "Unauthorized", 403: "Forbidden"}.get(status, "Error")
                conn.sendall(("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % (status, text)).encode())
                return
            accept = base64.b64encode(hashlib.sha1((self.headers["sec-websocket-key"] + WS_GUID).encode()).digest()).decode()
            conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                          "Sec-WebSocket-Accept: %s\r\nSec-WebSocket-Protocol: wstx.v1\r\n\r\n" % accept).encode())
            if self.close_after_upgrade:
                self.send_frame(conn, 8, struct.pack(">H", 1000) + b"going away")
                self.stop.wait(3)
                return
            while not self.stop.is_set():
                opcode, data = self.read_frame(conn)
                if opcode == 8:
                    self.send_frame(conn, 8, data[:2])
                    return
                if opcode != 1:
                    continue
                message = json.loads(data.decode())
                self.messages.append((time.time() * 1000, message))
                answer = self.reply(message)
                if answer is None:
                    continue
                if answer["type"] == "spectrum.subscription":
                    if self.answer_delay is None:
                        continue
                    self.stop.wait(self.answer_delay)
                    self.send_json(conn, answer)
                    threading.Thread(target=self.send_pushes, args=(conn,), daemon=True).start()
                else:
                    self.send_json(conn, answer)
        except (OSError, ConnectionError, ValueError):
            return

    def send_pushes(self, conn):
        start = time.time()
        try:
            for delay, message in sorted(self.pushes, key=lambda p: p[0]):
                if self.stop.wait(max(0.0, start + delay - time.time())):
                    return
                self.send_json(conn, message)
        except OSError:
            return


WS_CLIENT = r"""
# Scripted station client for the /ws cases of test_qso_test.py: the station URL is the test
# endpoint, the session holds its cookie, and the /ws seams stay as the driver defines them.
$AgentUrl = $env:QSO_WS_URL
function global:Ws-Log([hashtable]$E) {
  $E['ms'] = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  [IO.File]::AppendAllText($env:QSO_LOG, (([pscustomobject]$E | ConvertTo-Json -Compress -Depth 8) + "`n"))
}
function Open-AgentSession {
  $s = New-Object Microsoft.PowerShell.Commands.WebRequestSession
  $s.Cookies.Add((New-Object Net.Cookie('wstx_session', 'test-session', '/', '127.0.0.1')))
  [pscustomobject]@{ Session = $s }
}
function Agent-Get($c, [string]$Route) {
  $sim = $env:QSO_SIM_ID; $boot = '33333333-3333-4333-8333-333333333333'
  switch -regex ($Route) {
    '^/transmit$' { return [pscustomobject]@{ v = 1; profile_id = $sim; boot_id = $boot; ptt = 'released'; transmitting = $false; outcomes = @()
        transmit = [pscustomobject]@{ arm_state = 'disarmed'; last_disarm_cause = 'startup'; last_period_utc = $null; tune = $false; last_text = $null; refusal = $null }
        watchdog = [pscustomobject]@{ tx_calls = 6 } } }
    '^/contact$' { return [pscustomobject]@{ v = 1; profile_id = $sim; boot_id = $boot; contact_revision = 1; contact = $null; log = $null
        transmit = [pscustomobject]@{ safety_revision = 7 }; settings = [pscustomobject]@{ hold_tx = $false; rx_hz = 1200; tx_hz = 1500 }
        watchdog = [pscustomobject]@{ busy_with = $null } } }
    '^/radio$' { return [pscustomobject]@{ state = 'ready'; profile_id = $sim } }
    '^/automation$' { return [pscustomobject]@{ v = 1; profile_id = $sim; run = $null; free_tx_slots = $null } }
    '^/receive' { return [pscustomobject]@{ v = 1; source = $null; job = $null } }
  }
  throw "scripted client: no route $Route"
}
function Agent-Post($c, [string]$Route, $Body) {
  Ws-Log @{ kind = 'command'; route = $Route; action = [string]$Body['action']; enabled = $Body['enabled'] }
  [pscustomobject]@{ Status = 202; Body = [pscustomobject]@{ accepted = $true } }
}
function Qso-Revision($c) { '0123456789abcdef0123456789abcdef01234567' }
"""

WS_PREFLIGHT = r"""
param([string]$Holder, [string]$PowerBcd, [int]$Minutes = 30, [switch]$Status, [switch]$Release, [switch]$Restore,
      [switch]$NoWrite, [string]$Port, [string]$Baud, [string]$StateDir, [string]$Station, [string]$AgentClient)
$what = if ($Status) { 'status' } elseif ($Release) { 'release' } elseif ($Restore) { 'restore' } else { $PowerBcd }
Ws-Log @{ kind = 'preflight'; what = $what }
if ($Status) { if ($global:WsLease) { "lease: held by $($global:WsLease) until 2099-01-01T00:00:00Z" } else { 'lease: free' }; exit 0 }
if ($Release) { $global:WsLease = $null; exit 0 }
# The 0255 write fails, so a run that passes the SWR key ends there, before any call.
if ($what -eq '0255') { 'PREFLIGHT FAIL scripted 0255'; exit 1 }
if ($Restore) { $global:WsLease = $null } else { $global:WsLease = $Holder }
"PREFLIGHT PASS scripted $what"
exit 0
"""


def tx_level(po=40, swr=17):
    return {"v": 1, "type": "radio.tx_level",
            "data": {"meters": {"alc": 0, "po_pct": po, "swr_x10": swr}, "warnings": []}}


class WsTests(unittest.TestCase):
    """The driver's own /ws seams (Qso-OpenPushes, Qso-ReceivePushes, Qso-ClosePushes) against
    StationEndpoint (TC-192-03), timed by the test's wall clock."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = os.path.join(self.tmp.name, "state")
        self.station = os.path.join(self.tmp.name, "station")
        self.log = os.path.join(self.tmp.name, "run.log")
        self.client = os.path.join(self.tmp.name, "client.ps1")
        self.preflight_tool = os.path.join(self.tmp.name, "preflight.ps1")
        os.makedirs(self.state)
        folder = os.path.join(self.station, "profiles", "SIM-IC7300")
        os.makedirs(folder)
        with open(os.path.join(folder, "profile.json"), "w", encoding="utf-8") as f:
            json.dump({"profile_id": SIM_ID, "callsign": OWN, "control": {"endpoint": SIM_ENDPOINT}}, f)
        for path, text in ((self.client, WS_CLIENT), (self.preflight_tool, WS_PREFLIGHT)):
            with open(path, "w", encoding="utf-8-sig") as f:
                f.write(text)
        self.endpoint = None

    def tearDown(self):
        if self.endpoint:
            self.endpoint.close()
        self.tmp.cleanup()

    def run_driver(self, endpoint):
        self.endpoint = endpoint
        rc, out = pwsh.run(DRIVER, ["-Holder", "run7", "-Issue", "192", "-Item", "4", "-Station", self.station,
                                    "-StateDir", self.state, "-AgentClient", self.client, "-Preflight", self.preflight_tool],
                           env={"QSO_WS_URL": endpoint.url, "QSO_SIM_ID": SIM_ID, "QSO_LOG": self.log}, timeout=120)
        return rc, out

    def events(self, kind):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding="utf-8") as f:
            return [r for r in (json.loads(line) for line in f if line.strip()) if r["kind"] == kind]

    def verdict(self):
        with open(os.path.join(self.state, "qso-tests.jsonl"), encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()][-1]

    def end_ms(self):
        """When the driver gave up: its restore preflight, the first step after the end."""
        return [e["ms"] for e in self.events("preflight") if e["what"] == "restore"][0]

    def subscription_ms(self):
        return [t for t, m in self.endpoint.messages if m.get("type") == "spectrum.off"][0]

    def assert_ended_before_tune(self, rc, out, start):
        """Not tested before Tune: no 0255 write, nothing keyed, no ask line; the reason starts
        with `start` and is returned."""
        self.assertEqual(rc, 3, out)
        v = self.verdict()
        self.assertEqual(v["verdict"], "not_tested", out)
        reasons = [r for r in v["not_tested"] if r.startswith(start)]
        self.assertEqual(len(reasons), 1, f"{start!r} not leading any of {v['not_tested']}\n{out}")
        self.assertNotIn("Exception calling", reasons[0], "only the outer AggregateException text")
        self.assertNotIn("no fresh reading", " ".join(v["not_tested"]))
        self.assertEqual([c for c in self.events("command") if c["action"] == "tune"], [], "Tune was started")
        self.assertNotIn("0255", [p["what"] for p in self.events("preflight")])
        self.assertEqual(v["transmissions"], [])
        self.assertEqual(v["ask_operator"], [])
        self.assertNotIn("ASK THE OPERATOR", out)
        return reasons[0]

    # Proves: TC-192-03
    def test_the_handshake_and_subscription_follow_the_station_rules_and_pushes_arrive(self):
        pushes = [(0.2, {"v": 1, "type": "clock.time", "data": {"utc_ms": 1}}),
                  (0.4, {"v": 1, "type": "heartbeat", "data": {}}),
                  (2.5, tx_level(po=40, swr=17))]
        rc, out = self.run_driver(StationEndpoint(answer_delay=0.0, pushes=pushes))
        ep = self.endpoint
        self.assertEqual(ep.answered, 101, out)
        self.assertEqual(ep.headers.get("sec-websocket-protocol"), "wstx.v1")
        self.assertEqual(ep.headers.get("origin"), ep.url)
        self.assertIn("%s=%s" % WS_COOKIE, ep.headers.get("cookie", ""))
        subs = [m for _, m in ep.messages if m.get("type") == "spectrum.off"]
        self.assertEqual(len(subs), 1, out)
        self.assertEqual(sorted(subs[0]), ["id", "type", "v"])
        self.assertIsInstance(subs[0]["id"], int)
        self.assertNotIsInstance(subs[0]["id"], bool)
        self.assertIn("subscription is confirmed", out)
        tune = [c for c in self.events("command") if c["action"] == "tune"]
        self.assertTrue(tune and tune[0]["ms"] >= self.subscription_ms(), "Tune only after the subscription")
        # The push sent during Tune is the key's one fresh reading; clock.time and heartbeat are dropped.
        v = self.verdict()
        self.assertEqual((v["swr_x10"], v["po_pct"]), (17, [40]), out)
        self.assertIn("SWR key: 1 fresh readings", out)
        self.assertIn("0255", [p["what"] for p in self.events("preflight")], "the key passed on to 0255")

    # Proves: TC-192-03
    def test_an_upgrade_answered_after_about_8_s_goes_on_to_the_subscription(self):
        rc, out = self.run_driver(StationEndpoint(upgrade_delay=8.0, pushes=[(2.5, tx_level())]))
        self.assertEqual(self.endpoint.answered, 101, out)
        self.assertEqual(len([m for _, m in self.endpoint.messages if m.get("type") == "spectrum.off"]), 1, out)
        self.assertIn("subscription is confirmed", out)

    # Proves: TC-192-03
    def test_an_upgrade_never_answered_ends_not_tested_after_10_s(self):
        rc, out = self.run_driver(StationEndpoint(upgrade_delay=None))
        self.assert_ended_before_tune(rc, out, "the /ws connection")
        waited = self.end_ms() - self.endpoint.connect_at
        self.assertGreaterEqual(waited, 10_000, out)
        self.assertLessEqual(waited, 15_000, out)

    # Proves: TC-192-03
    def test_a_subscription_answered_after_about_4_s_goes_on(self):
        rc, out = self.run_driver(StationEndpoint(answer_delay=4.0, pushes=[(2.5, tx_level())]))
        self.assertIn("subscription is confirmed", out)
        self.assertIn("0255", [p["what"] for p in self.events("preflight")], out)

    # Proves: TC-192-03
    def test_a_subscription_never_answered_ends_not_tested_after_5_s(self):
        rc, out = self.run_driver(StationEndpoint(answer_delay=None))
        reason = self.assert_ended_before_tune(rc, out, "the /ws subscription")
        self.assertIn("subscription", reason)
        waited = self.end_ms() - self.subscription_ms()
        self.assertGreaterEqual(waited, 5_000, out)
        self.assertLessEqual(waited, 8_000, out)

    # Proves: TC-192-03
    def test_an_upgrade_answered_400_names_the_websocket_exception(self):
        rc, out = self.run_driver(StationEndpoint(status=400))
        reason = self.assert_ended_before_tune(rc, out, "the /ws connection")
        self.assertIn("WebSocketException", reason)

    # Proves: TC-192-03
    def test_a_subscription_refused_invalid_request_or_unavailable_names_the_code(self):
        for endpoint, code in ((StationEndpoint(refuse="invalid_request"), "invalid_request"),
                               (StationEndpoint(unavailable=True), "unavailable")):
            with self.subTest(code=code):
                rc, out = self.run_driver(endpoint)
                reason = self.assert_ended_before_tune(rc, out, "the /ws subscription")
                self.assertIn(code, reason)
                endpoint.close()
                os.unlink(os.path.join(self.state, "qso-tests.jsonl"))
                os.unlink(self.log)

    # Proves: TC-192-03
    def test_a_close_after_the_upgrade_names_the_close(self):
        rc, out = self.run_driver(StationEndpoint(close_after_upgrade=True))
        reason = self.assert_ended_before_tune(rc, out, "the /ws subscription")
        self.assertIn("closed", reason)


if __name__ == "__main__":
    unittest.main()
