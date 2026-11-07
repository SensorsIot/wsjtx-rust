# Radio preflight before any agent Tx (harness retrospective 2026-11-06; wsjtx-rust#44 comment
# 6683921947: 8 Tx periods and 2 Set level runs went out at about 10 W under a 1 W authorization).
#   radio-preflight.ps1 -Holder <run name> [-Minutes 30]    take the lease, read RF power, judge it
#   radio-preflight.ps1 -Status                             who holds the lease
#   radio-preflight.ps1 -Release -Holder <run name>         give the lease back
# An agent runs it before it keys and keys only on exit 0, while its lease is live. It writes
# nothing to the radio. Exit 0: PREFLIGHT PASS. Exit 1: PREFLIGHT REFUSED, RF power above the
# authorization (.harness/deploy/radio-authorization.json), with no override: only the operator
# changes that file. Exit 2: PREFLIGHT ERROR, it could
# not read, so nothing is shown safe. Exit 3: PREFLIGHT BUSY, another live writer holds the
# lease, or the station is in use: the station was not stopped.
#
# The running station holds the COM port exclusively and offers no RF power read, so a station
# that is running is stopped gracefully (Ctrl+C), read and started again, always. It is left
# alone while PTT is keyed or a contact runs: such a contact may be the operator's. The old value
# is printed and recorded in <git common dir>/harness-parallel/radio/preflight.jsonl beside the
# lease (lease.json), so every worktree of the repository sees them.
param([string]$Holder, [int]$Minutes = 30, [switch]$Status, [switch]$Release,
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
  # A stop that outlasted Stop-Station's deadline is still under way: Ctrl+C has gone out, and a
  # start now would be ignored by the running task and leave the station down when it exits.
  if (@(Station-Procs).Count -gt 0) {
    $deadline = (Now).AddSeconds(20)
    while (@(Station-Procs).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    if (@(Station-Procs).Count -gt 0) { throw 'it still runs 32 s after Ctrl+C and was not restarted: treat it as down' }
    Settle-Task
  }
  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Now).AddSeconds(40)
  while (@(Station-Procs).Count -eq 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -eq 0) { throw 'the station did not come back within 40 s' }
}
# The CI-V read of 14 0A: the two BCD bytes of FE FE E0 94 14 0A hh ll FD, in the radio's reply
# as wsjtx-rust#44 captured it (`14 0A 00 26`). DTR and RTS stay off: they can key this radio.
function Read-RfPower($config) {
  $port = New-Object System.IO.Ports.SerialPort $config.port, ([int]$config.baud), 'None', 8, 'One'
  $port.DtrEnable = $false; $port.RtsEnable = $false; $port.ReadTimeout = 300; $port.WriteTimeout = 500
  try {
    $port.Open()
    $frame = [byte[]](0xFE, 0xFE, 0x94, 0xE0, 0x14, 0x0A, 0xFD)
    $port.DiscardInBuffer(); $port.Write($frame, 0, $frame.Length)
    $seen = New-Object System.Collections.Generic.List[string]; $deadline = (Now).AddMilliseconds(800)
    while ((Now) -lt $deadline) {
      while ($port.BytesToRead -gt 0) { $seen.Add(([byte]$port.ReadByte()).ToString('X2')) }
      if (($seen -join ' ') -match 'FE FE E0 94 14 0A ([0-9]{2}) ([0-9]{2}) FD') { return [int]($Matches[1] + $Matches[2]) }
      Start-Sleep -Milliseconds 20
    }
    throw "no RF power reply from $($config.port) (read: $($seen -join ' '))"
  } finally { if ($port.IsOpen) { $port.Close() } }
}

try {
  if (-not $StateDir) { $StateDir = Join-Path (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\radio' }
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  if (-not $AgentClient) { $AgentClient = Join-Path (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\resources\station-update\agent-client.ps1' }
  [void][IO.Directory]::CreateDirectory($StateDir)
  if ($Status) {
    $lease = With-LeaseLock { Read-Lease }
    if ($lease) { Write-Output "lease: held by $($lease.holder) until $($lease.expires)" } else { Write-Output 'lease: free' }
    exit 0
  }
  if (-not $Holder -or $Minutes -lt 1 -or $Minutes -gt 240) { Finish 2 'ERROR' 'need -Holder and -Minutes from 1 to 240' }
  if ($Release) {
    $released = With-LeaseLock { $l = Read-Lease; if ($l -and $l.holder -ne $Holder) { $false } else { Remove-Item -LiteralPath (Join-Path $StateDir 'lease.json') -ErrorAction SilentlyContinue; $true } }
    if ($released) { Write-Output "lease: released by $Holder"; exit 0 }
    Finish 3 'BUSY' "the lease is not $Holder's"
  }
  $config = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'radio-authorization.json')) | ConvertFrom-Json
  $limit = [int]$config.rf_power_max_bcd

  # Before the station is touched: a second live writer stops here, and learns whose run it is.
  $held = $null
  $taken = With-LeaseLock {
    $l = Read-Lease
    if ($l -and $l.holder -ne $Holder) { return $l }
    $script:held = $l
    Write-Lease ([pscustomobject]@{ holder = $Holder; acquired = (Iso (Now)); expires = (Iso (Now).AddMinutes($Minutes)) })
    $null
  }
  if ($taken) { Finish 3 'BUSY' "another live writer holds the lease: $($taken.holder) until $($taken.expires); a contact on the station may be theirs" }

  $code = 2; $word = 'ERROR'; $why = ''; $raw = $null; $stopped = $false
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
      $raw = Read-RfPower $config
    }
  } catch { $why = "cannot read RF power: $($_.Exception.Message)" }
  try { if ($stopped) { Start-Station } }
  catch { $code = 2; $word = 'ERROR'; $raw = $null; $why = "$why; THE STATION IS DOWN: $($_.Exception.Message)" }

  if ($null -ne $raw) {
    $shown = '{0:D4} ({1:F1} %)' -f $raw, ($raw * 100.0 / 255)
    if ($raw -gt $limit) {
      $code = 1; $word = 'REFUSED'; $why = "RF power reads $shown, above the authorized $('{0:D4}' -f $limit) ($($config.authorized_watts) W). Do not key. Raise it with the operator; this tool writes nothing."
    } else {
      $code = 0; $word = 'PASS'; $why = "RF power reads $shown, authorized up to $('{0:D4}' -f $limit) ($($config.authorized_watts) W). Lease: $Holder for $Minutes min."
    }
  }
  Record ([ordered]@{ time = (Iso (Now)); holder = $Holder; rf_power_bcd = $raw; limit_bcd = $limit; verdict = $word; station_stopped = $stopped; why = $why })
  # Nobody keys on a result but exit 0, so only that takes or renews the lease. BUSY says nothing
  # about the power: a lease this holder already had, for its own contact, stays as it was.
  if ($code -ne 0) {
    With-LeaseLock {
      $l = Read-Lease
      if ($l -and $l.holder -eq $Holder) {
        if ($code -eq 3 -and $script:held) { Write-Lease $script:held } else { Remove-Item -LiteralPath (Join-Path $StateDir 'lease.json') }
      }
    }
  }
  Finish $code $word $why
} catch {
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $($_.Exception.Message)"
}
