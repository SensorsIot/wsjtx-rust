# Radio preflight before any agent Tx (harness retrospective 2026-11-06; wsjtx-rust#44 comment
# 6683921947: 8 Tx periods and 2 Set level runs went out at another level than the test assumed).
# The test sets its own power (operator, 2026-11-07), so nothing keys at an assumed level.
#   radio-preflight.ps1 -Holder <run name> -PowerBcd <hhll> [-NoWrite] [-Minutes 30]    take the lease, set the power
#   radio-preflight.ps1 -Restore -Holder <run name>                          put the old power back, end the lease
#   radio-preflight.ps1 -Status                                              who holds the lease
#   radio-preflight.ps1 -Release -Holder <run name>                          give the lease back
# -PowerBcd is the value of CI-V 14 0A the test needs, required, four digits: the radio's RF POWER
# control from 0000 to 0255, not watts. Po also follows the Tx level and the profile's limit, so a
# confirmed value is the control and not the output. Measured on 20 m at -12 dB: 0077 gave Po
# 24-26 %, 0090 gave Po 30-31 %; 0003 showed Po 0 %; no wattmeter. A test that makes QSOs needs at
# least 30 W, so it uses 0090 or more and checks Po on its first Tx; short keying without a QSO may
# use 0003. -NoWrite reads only, and refuses if the radio reads another value. An agent runs it before it keys and keys only on exit 0, while its lease is live.
# Exit 0: PREFLIGHT PASS, the radio's power reads the level asked for. Exit 2: PREFLIGHT ERROR,
# it could not read, write or confirm it by the read-back. Exit 3: PREFLIGHT BUSY, another live
# writer holds the lease, or the station is in use: the station was not stopped.
#
# The running station holds the COM port exclusively and offers no RF power read, so a station
# that is running is stopped gracefully (Ctrl+C), set and started again, always. It is left
# alone while PTT is keyed or a contact runs: such a contact may be the operator's. It reads, writes
# only on a difference and reads back. The old value is printed, kept in the lease for -Restore
# (a renewal keeps the first one) and recorded in <git common dir>/harness-parallel/radio/
# preflight.jsonl beside the lease (lease.json), so every worktree of the repository sees them.
param([string]$Holder, [string]$PowerBcd, [int]$Minutes = 30, [switch]$Status, [switch]$Release, [switch]$Restore, [switch]$NoWrite,
      [string]$StateDir, [string]$Station, [string]$AgentClient,
      [string]$TaskName = 'WSTX Rust Station HB9BLA')
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

function Now { [DateTime]::UtcNow }
function Iso($t) { $t.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }
function Finish($code, $word, $why) { Write-Output "PREFLIGHT $word $why"; exit $code }

# One writer of the lease file at a time, also across worktrees.
function With-LeaseLock([scriptblock]$Do) {
  $path = Join-Path $StateDir 'lease.lock'; $deadline = (Now).AddSeconds(10)
  for (;;) {
    try { $lock = [IO.File]::Open($path, 'OpenOrCreate', 'ReadWrite', 'None'); break }
    catch [IO.IOException] { if ((Now) -gt $deadline) { throw }; Start-Sleep -Milliseconds 100 }
  }
  try { & $Do } finally { $lock.Dispose() }
}
function Read-Lease {
  $path = Join-Path $StateDir 'lease.json'
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  $lease = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  if ([DateTime]::Parse($lease.expires, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal') -le (Now)) { return $null }
  $lease
}
function Write-Lease($lease) {
  [IO.File]::WriteAllText((Join-Path $StateDir 'lease.json'), ($lease | ConvertTo-Json -Compress))
}
function Record($fields) {
  $line = ([pscustomobject]$fields | ConvertTo-Json -Compress) + "`n"
  [IO.File]::AppendAllText((Join-Path $StateDir 'preflight.jsonl'), $line)
}
function Station-Procs {
  @(Get-CimInstance Win32_Process -Filter "Name='wstx-rust.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($Station, [StringComparison]::OrdinalIgnoreCase) })
}
# GenerateConsoleCtrlEvent reaches the attached console's whole group, so a helper process does it.
function Send-CtrlC([int]$TargetPid) {
  $code = @"
Add-Type -Namespace W -Name C -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint p); [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(System.IntPtr h, bool a); [DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint e, uint g);'
[W.C]::FreeConsole() | Out-Null
if (-not [W.C]::AttachConsole($TargetPid)) { exit 3 }
[W.C]::SetConsoleCtrlHandler([IntPtr]::Zero, `$true) | Out-Null
if (-not [W.C]::GenerateConsoleCtrlEvent(0, 0)) { exit 4 }
Start-Sleep -Milliseconds 500
exit 0
"@
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  (Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru -Wait).ExitCode
}
# Why the station cannot be stopped now, or $null. An unreadable state counts as in use.
function Station-InUse {
  try {
    . $AgentClient
    $session = Open-AgentSession
    $transmit = Agent-Get $session '/transmit'
    $contact = (Agent-Get $session '/contact').contact
  } catch { return "its state cannot be read ($($_.Exception.GetType().Name))" }
  if ([string]$transmit.ptt -ne 'released' -or $transmit.transmitting) { return "PTT is $($transmit.ptt)" }
  if ($contact -and [string]$contact.state -notin @('idle', 'completed', 'cancelled')) { return "a contact is $($contact.state), with $($contact.dx_call)" }
  $null
}
function Stop-Station($process) {
  $rc = Send-CtrlC ([int]$process.ProcessId)
  $script:CtrlCExit = $rc
  $deadline = (Now).AddSeconds(12)
  while (@(Station-Procs).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -gt 0) { throw "the station did not stop on Ctrl+C (helper exit $rc)" }
  Settle-Task
}
# The task's launcher outlives the process for a moment; the next start must not race it.
function Settle-Task {
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { Write-Output "note: Stop-ScheduledTask: $($_.Exception.Message)" }
  $deadline = (Now).AddSeconds(10)
  while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 800
}
function Start-Station {
  # A stop that outlasted Stop-Station's deadline may still be under way, and a start now would be
  # ignored by the running task and leave the station down when it exits. Ctrl+C may also never
  # have reached it (the helper's exit code says), so a station that stays up is not called down.
  if (@(Station-Procs).Count -gt 0) {
    $deadline = (Now).AddSeconds(20)
    while (@(Station-Procs).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (@(Station-Procs).Count -gt 0) { $script:StillRuns = $true; throw "it still runs, state unknown, check it: 32 s after Ctrl+C (helper exit $script:CtrlCExit), not restarted" }
    Settle-Task
  }
  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Now).AddSeconds(40)
  while (@(Station-Procs).Count -eq 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -eq 0) { throw 'the station did not come back within 40 s' }
}
# One CI-V command: the matches of the reply `pattern`, or $null after 800 ms ($script:Seen: what came).
function Civ-Exchange($port, [byte[]]$frame, [string]$pattern) {
  $port.DiscardInBuffer(); $port.Write($frame, 0, $frame.Length)
  $script:Seen = New-Object System.Collections.Generic.List[string]; $deadline = (Now).AddMilliseconds(800)
  while ((Now) -lt $deadline) {
    while ($port.BytesToRead -gt 0) { $script:Seen.Add(([byte]$port.ReadByte()).ToString('X2')) }
    if (($script:Seen -join ' ') -match $pattern) { return $Matches }
    Start-Sleep -Milliseconds 20
  }
  $null
}
# The CI-V read of 14 0A: the two BCD bytes of FE FE E0 94 14 0A hh ll FD, in the radio's reply
# as wsjtx-rust#44 captured it (`14 0A 00 26`).
function Read-Power($port, $config) {
  $m = Civ-Exchange $port ([byte[]](0xFE, 0xFE, 0x94, 0xE0, 0x14, 0x0A, 0xFD)) 'FE FE E0 94 14 0A ([0-9]{2}) ([0-9]{2}) FD'
  if (-not $m) { throw "no RF power reply from $($config.port) (read: $($script:Seen -join ' '))" }
  [int]($m[1] + $m[2])
}
# Read, write only on a difference, read back; returns what the radio reads. $script:OldRaw holds
# the value it had from the first read on, also when the write then fails. DTR and RTS stay off:
# they can key this radio.
function Set-RfPower($config, [int]$target) {
  $port = New-Object System.IO.Ports.SerialPort $config.port, ([int]$config.baud), 'None', 8, 'One'
  $port.DtrEnable = $false; $port.RtsEnable = $false; $port.ReadTimeout = 300; $port.WriteTimeout = 500
  try {
    $port.Open()
    $script:OldRaw = Read-Power $port $config
    if ($script:OldRaw -eq $target) { return $target }
    $digits = '{0:D4}' -f $target
    if ($NoWrite) { throw "it reads $('{0:D4}' -f $script:OldRaw), not $digits, and -NoWrite writes nothing" }
    $frame = [byte[]](0xFE, 0xFE, 0x94, 0xE0, 0x14, 0x0A, [Convert]::ToByte($digits.Substring(0, 2), 16), [Convert]::ToByte($digits.Substring(2, 2), 16), 0xFD)
    $script:Written = $true
    $ack = Civ-Exchange $port $frame 'FE FE E0 94 (FB|FA) FD'
    if ($ack -and $ack[1] -eq 'FA') { throw "the radio refused the write of $digits" }
    $back = Read-Power $port $config
    if ($back -ne $target) { throw "wrote $digits, read back $('{0:D4}' -f $back)" }
    $back
  } finally { if ($port.IsOpen) { $port.Close() } }
}
function Old-Power($lease) {
  if ($lease -and $lease.PSObject.Properties['old_power_bcd']) { $lease.old_power_bcd }
}

try {
  if (-not $StateDir) { $StateDir = Join-Path (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\radio' }
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  if (-not $AgentClient) { $AgentClient = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\tools\deploy\agent-client.ps1')) }
  [void][IO.Directory]::CreateDirectory($StateDir)
  if ($Status) {
    $lease = With-LeaseLock { Read-Lease }
    if ($lease) { Write-Output "lease: held by $($lease.holder) until $($lease.expires)" } else { Write-Output 'lease: free' }
    exit 0
  }
  if (-not $Holder -or $Minutes -lt 1 -or $Minutes -gt 240) { Finish 2 'ERROR' 'need -Holder and -Minutes from 1 to 240' }
  if ($Release) {
    $script:GivenUp = $null
    $released = With-LeaseLock { $l = Read-Lease; if ($l -and $l.holder -ne $Holder) { $false } else { $script:GivenUp = Old-Power $l; Remove-Item -LiteralPath (Join-Path $StateDir 'lease.json') -ErrorAction SilentlyContinue; $true } }
    if ($released) {
      $note = if ($null -ne $script:GivenUp) { "; old RF power $('{0:D4}' -f [int]$script:GivenUp) was not restored unless it reads that now" } else { '' }
      Write-Output "lease: released by $Holder$note"; exit 0
    }
    Finish 3 'BUSY' "the lease is not $Holder's"
  }
  if ($Restore) {
    $target = $null
  } else {
    if ($PowerBcd -notmatch '^[0-9]{4}$' -or [int]$PowerBcd -gt 255) { Finish 2 'ERROR' "need -PowerBcd, the level this test keys at, four digits from 0000 to 0255 (the radio's control, not watts), not '$PowerBcd'" }
    $target = [int]$PowerBcd
  }
  $config = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'radio-port.json')) | ConvertFrom-Json

  # Before the station is touched: a second live writer stops here, and learns whose run it is.
  $held = $null
  $taken = With-LeaseLock {
    $l = Read-Lease
    if ($l -and $l.holder -ne $Holder) { return $l }
    $script:held = $l
    if (-not $Restore) { Write-Lease ([pscustomobject]@{ holder = $Holder; acquired = (Iso (Now)); expires = (Iso (Now).AddMinutes($Minutes)); old_power_bcd = (Old-Power $l) }) }
    $null
  }
  if ($Restore -and -not $taken) {
    $target = Old-Power $held
    if ($null -eq $target) { Finish 2 'ERROR' "$Holder has no live lease with an old value: see preflight.jsonl" }
    $target = [int]$target
  }
  if ($taken) { Finish 3 'BUSY' "another live writer holds the lease: $($taken.holder) until $($taken.expires); a contact on the station may be theirs" }

  $code = 2; $word = 'ERROR'; $why = ''; $raw = $null; $stopped = $false; $script:OldRaw = $null; $script:Written = $false; $script:CtrlCExit = 'not run'; $script:StillRuns = $false
  try {
    $updating = $false
    try { ([IO.File]::Open((Join-Path $Station 'logs\update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')).Dispose() }
    catch [IO.IOException] { $updating = $true }
    $procs = @(Station-Procs)
    $busy = if ($updating) { 'an update is running' }
            elseif ($procs.Count -gt 1) { "$($procs.Count) station processes are running" }
            elseif ($procs.Count -eq 1) { Station-InUse }
    if ($busy) {
      $code = 3; $word = 'BUSY'; $why = "the station is in use and was not stopped: $busy"
    } else {
      if ($procs.Count -eq 1) { $stopped = $true; Stop-Station $procs[0] }
      $raw = Set-RfPower $config $target
    }
  } catch { $why = "cannot set RF power: $($_.Exception.Message)" }
  try { if ($stopped) { Start-Station } }
  catch { $code = 2; $word = 'ERROR'; $raw = $null; $why = if ($script:StillRuns) { "$why; THE STATION: $($_.Exception.Message)" } else { "$why; THE STATION IS DOWN: $($_.Exception.Message)" } }

  if ($null -ne $raw) {
    $shown = '{0:D4} ({1:F1} % of the control)' -f $raw, ($raw * 100.0 / 255)
    $old = '{0:D4}' -f $script:OldRaw
    $code = 0; $word = 'PASS'
    $what = if ($script:Written) { "was $old, written and read back" } else { 'unchanged, no write' }
    $why = if ($Restore) { "RF power restored: reads $shown ($what). Lease of $Holder ended." }
           else { "RF power reads $shown ($what). Old value $('{0:D4}' -f (@((Old-Power $script:held), $script:OldRaw) -ne $null)[0]): restore it with -Restore. Lease: $Holder for $Minutes min." }
  }
  Record ([ordered]@{ time = (Iso (Now)); holder = $Holder; restore = [bool]$Restore; rf_power_old_bcd = $script:OldRaw; rf_power_target_bcd = $target; rf_power_read_bcd = $raw; written = $script:Written; verdict = $word; station_stopped = $stopped; why = $why })
  # Nobody keys on a result but exit 0, so only that takes or renews the lease; it keeps the first
  # old value for -Restore. BUSY says nothing about the power: a lease this holder already had,
  # for its own contact, stays as it was, and so does the lease of a restore that failed, which
  # can be tried again.
  With-LeaseLock {
    $l = Read-Lease
    if ($l -and $l.holder -eq $Holder) {
      if ($Restore) {
        if ($code -eq 0) { Remove-Item -LiteralPath (Join-Path $StateDir 'lease.json') }
      } elseif ($code -eq 0) {
        $l.old_power_bcd = @((Old-Power $script:held), $script:OldRaw) -ne $null | Select-Object -First 1
        Write-Lease $l
      } elseif ($code -eq 3 -and $script:held) { Write-Lease $script:held }
      else { Remove-Item -LiteralPath (Join-Path $StateDir 'lease.json') }
    }
  }
  Finish $code $word $why
} catch {
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $($_.Exception.Message)"
}
