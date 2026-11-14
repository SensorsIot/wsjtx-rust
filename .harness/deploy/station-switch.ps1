# Switches the station between the operator profile and the simulator profile SIM-IC7300 for live
# tests on the FT-8 Band Simulator (docs/harness/Project-Specifics.md, Simulator live tests, Switch;
# harness#114). It needs no administrator rights.
#   station-switch.ps1 -To simulator     the tester or the coordinator
#   station-switch.ps1 -To back          the coordinator only: no agent switches the station to ic7300
#   -DryRun prints every step and changes nothing (it still reads the station's state).
# -To simulator refuses unless profiles\SIM-IC7300 exists and names no COM3; backs up
# station\launcher.ps1 once (launcher.ps1.before-simulator; a launcher already switched is not
# backed up again), points its profile line at profiles\SIM-IC7300 and sets WSTX_RADIO_DISCOVERY,
# WSTX_UDP and WSTX_PSKR off (without discovery off, a silent COM4 makes the station adopt the
# real radio on COM3). -To back writes the backup back, or, without one, the repository's pinned
# launcher (what a deploy writes). Both then stop the station gracefully (Ctrl+C, station-control.ps1),
# restart its scheduled task and read the profile back from the station (GET /radio) and from the
# launcher's receipt (station-running.json). -To simulator also hashes the operator profile
# ic7300 (profile.json) and its logbook (contacts.adi) before and after.
# It never writes a profile, never changes a CAT endpoint and keys nothing.
# Exit 0: SWITCH PASS, the station reads the profile asked for. Exit 2: SWITCH ERROR. Exit 3:
# SWITCH BUSY, the station is in use (PTT, a contact, an update) and was not touched.
param([string]$To, [switch]$DryRun, [string]$Station, [string]$AgentClient, [string]$Pin,
      [string]$TaskName = 'WSTX Rust Station HB9BLA', [int]$ReadBackSeconds = 60)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'station-control.ps1')
function Finish($code, $word, $why) { Write-Output "SWITCH $word $why"; exit $code }
function Say($text) { Write-Output "  $text" }
# A step that changes something: done, or only said under -DryRun.
function Act($text, [scriptblock]$Do) {
  if ($DryRun) { Write-Output "would: $text" } else { Write-Output "step: $text"; & $Do }
}

$SimProfile = 'SIM-IC7300'
$EnvLine = "`$env:WSTX_RADIO_DISCOVERY='off';`$env:WSTX_UDP='off';`$env:WSTX_PSKR='off'"
$ProfileLine = "(?m)^\`$stationProfilePath=Join-Path \`$base 'profiles\\([^'\\]+)'"

function Sha($path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'absent' }
  (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
}
function Operator-Hashes {
  $dir = Join-Path $Station 'profiles\ic7300'
  [ordered]@{ 'ic7300\profile.json' = (Sha (Join-Path $dir 'profile.json')); 'ic7300\contacts.adi' = (Sha (Join-Path $dir 'contacts.adi')) }
}
# The profile folder name the launcher text starts the station with; refuses a launcher it cannot read.
function Launcher-Profile([string]$text, [string]$what) {
  $found = [regex]::Matches($text, $ProfileLine)
  if ($found.Count -ne 1) { throw "$what has $($found.Count) profile lines (`$stationProfilePath=Join-Path `$base 'profiles\<name>'), not one" }
  $found[0].Groups[1].Value
}
function Profile-Id([string]$name) {
  $path = Join-Path $Station "profiles\$name\profile.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "the profile $name has no profile.json ($path)" }
  $p = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  $endpoint = if ($p.PSObject.Properties['control'] -and $p.control -and $p.control.PSObject.Properties['endpoint']) { [string]$p.control.endpoint } else { '' }
  [pscustomobject]@{ id = [string]$p.profile_id; endpoint = $endpoint }
}
function Simulator-Launcher([string]$text) {
  $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $text = [regex]::Replace($text, $ProfileLine, { param($m) $m.Value.Replace("profiles\$($m.Groups[1].Value)'", "profiles\$SimProfile'") })
  if (-not $text.Contains($EnvLine)) {
    $at = [regex]::Match($text, $ProfileLine).Index
    $text = $text.Substring(0, $at) + $EnvLine + $nl + $text.Substring($at)
  }
  $text
}
# Why the station cannot be stopped now, or $null.
function Busy {
  $updating = $false
  $lock = Join-Path $Station 'logs\update.lock'
  if (Test-Path -LiteralPath $lock -PathType Leaf) {
    try { ([IO.File]::Open($lock, 'Open', 'ReadWrite', 'None')).Dispose() }
    catch [IO.IOException] { $updating = $true }
  }
  $procs = @(Station-Procs)
  if ($updating) { 'an update is running' }
  elseif ($procs.Count -gt 1) { "$($procs.Count) station processes are running" }
  elseif ($procs.Count -eq 1) { Station-InUse }
}
function Restart {
  $procs = @(Station-Procs)
  if ($procs.Count -eq 1) { Act "stop the station gracefully (Ctrl+C to process $($procs[0].ProcessId)), then its task '$TaskName'" { Stop-Station $procs[0] } }
  else { Say 'the station is not running' }
  Act "start the task '$TaskName' and wait for the station" { Start-Station }
}
# The station's own report: GET /radio's profile_id and the launcher's receipt for the running process.
function Read-Back($expected) {
  $deadline = (Now).AddSeconds($ReadBackSeconds); $last = 'no answer'
  . $AgentClient
  for (;;) {
    try {
      $procs = @(Station-Procs)
      if ($procs.Count -ne 1) { throw "$($procs.Count) station processes" }
      $receipt = [IO.File]::ReadAllText((Join-Path $Station 'station-running.json')) | ConvertFrom-Json
      if ([int]$receipt.process_id -ne [int]$procs[0].ProcessId) { throw "the receipt names process $($receipt.process_id), the station runs as $($procs[0].ProcessId)" }
      $radio = Agent-Get (Open-AgentSession) '/radio'
      return [pscustomobject]@{ receipt = [string]$receipt.profile; profile_id = [string]$radio.profile_id; state = [string]$radio.state; device = [string]$radio.device_id; pid = $procs[0].ProcessId }
    } catch { $last = $_.Exception.Message }
    if ((Now) -ge $deadline) { throw "no read-back within $ReadBackSeconds s: $last" }
    Start-Sleep -Seconds 2
  }
}

try {
  if ($To -notin @('simulator', 'back')) { Finish 2 'ERROR' "need -To simulator or -To back, not '$To'" }
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  if (-not $AgentClient) { $AgentClient = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\tools\deploy\agent-client.ps1')) }
  if (-not $Pin) { $Pin = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\tools\deploy\station-update\launcher.ps1')) }
  $script:CtrlCExit = 'not run'; $script:StillRuns = $false
  $launcher = Join-Path $Station 'launcher.ps1'
  $backup = Join-Path $Station 'launcher.ps1.before-simulator'
  if ($DryRun) { Write-Output "DRY RUN: nothing is changed (station $Station)" }
  if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { Finish 2 'ERROR' "no launcher at $launcher" }
  $current = [IO.File]::ReadAllText($launcher)
  $now = Launcher-Profile $current 'the station launcher'
  Say "the launcher starts profiles\$now"

  if ($To -eq 'simulator') {
    if (-not (Test-Path -LiteralPath (Join-Path $Station "profiles\$SimProfile") -PathType Container)) { Finish 2 'ERROR' "the profile profiles\$SimProfile does not exist: nothing switched" }
    $sim = Profile-Id $SimProfile
    Say "profiles\$SimProfile is $($sim.id), CAT $($sim.endpoint)"
    if ($sim.endpoint -match '(?i)COM3\b') { Finish 2 'ERROR' "profiles\$SimProfile names COM3, the real radio's port: nothing switched" }
    $before = Operator-Hashes
    foreach ($k in $before.Keys) { Say "before: $k sha256 $($before[$k])" }
    $new = Simulator-Launcher $current
    $expected = $SimProfile; $expectedId = $sim.id
  } else {
    if (Test-Path -LiteralPath $backup -PathType Leaf) { $source = $backup; $what = "the backup $backup" }
    else { $source = $Pin; $what = "the repository's pinned launcher $Pin (no backup)" }
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { Finish 2 'ERROR' "neither a backup nor the pin $Pin exists" }
    $new = [IO.File]::ReadAllText($source)
    $expected = Launcher-Profile $new $what
    if ($expected -eq $SimProfile) { Finish 2 'ERROR' "$what starts profiles\$SimProfile, not the operator profile" }
    $expectedId = (Profile-Id $expected).id
    Say "back to profiles\$expected ($expectedId) from $what"
  }

  $busy = Busy
  if ($busy) { Finish 3 'BUSY' "the station is in use and was not touched: $busy" }

  if ($To -eq 'simulator') {
    if ($now -eq $SimProfile) { Say "the launcher already starts $SimProfile; the backup is not taken again" }
    else { Act "back up the launcher to $backup" { Copy-Item -LiteralPath $launcher -Destination $backup -Force } }
  }
  if ($new -ne $current) {
    $step = if ($To -eq 'simulator') { "point the launcher at profiles\$SimProfile and set WSTX_RADIO_DISCOVERY, WSTX_UDP, WSTX_PSKR off" } else { "write $what as the launcher" }
    Act $step {
      [IO.File]::WriteAllText($launcher, $new, [Text.UTF8Encoding]::new($false))
      if ([IO.File]::ReadAllText($launcher) -ne $new) { throw 'the launcher does not read back as written' }
    }
  } else { Say 'the launcher is already as wanted; not written' }

  try { Restart }
  catch {
    $msg = $_.Exception.Message
    if ($script:StillRuns) { Finish 2 'ERROR' "THE STATION: $msg" }
    Finish 2 'ERROR' "THE STATION IS DOWN or was not restarted: $msg"
  }
  if ($DryRun) {
    Write-Output "would: read back the station's profile (GET /radio and station-running.json), expecting $expected ($expectedId)"
    if ($To -eq 'simulator') { Write-Output 'would: hash the ic7300 profile and logbook again and compare' }
    Finish 0 'DRY-RUN' "-To ${To}: every step above was printed, nothing was changed"
  }

  $read = Read-Back $expected
  Say "read back: GET /radio profile_id $($read.profile_id), state $($read.state), device $($read.device)"
  Say "read back: station-running.json profile $($read.receipt) (process $($read.pid))"
  $text = [IO.File]::ReadAllText($launcher)
  $envOff = $text.Contains($EnvLine)
  Say "read back: the launcher sets WSTX_RADIO_DISCOVERY, WSTX_UDP, WSTX_PSKR off: $envOff"
  $problems = @()
  if ($read.profile_id -ne $expectedId) { $problems += "the station runs profile $($read.profile_id), not $expected ($expectedId)" }
  if (-not $read.receipt.EndsWith("profiles\$expected", [StringComparison]::OrdinalIgnoreCase)) { $problems += "the receipt names $($read.receipt), not profiles\$expected" }
  if ($read.device -match '(?i)COM3\b' -and $To -eq 'simulator') { $problems += "the station holds $($read.device), the real radio's port" }
  if ($To -eq 'simulator') {
    if (-not $envOff) { $problems += 'the launcher does not set discovery, UDP and PSK Reporter off' }
    $after = Operator-Hashes
    foreach ($k in $after.Keys) {
      Say "after: $k sha256 $($after[$k])"
      if ($after[$k] -ne $before[$k]) { $problems += "$k changed: $($before[$k]) -> $($after[$k])" }
    }
  }
  if ($problems) { Finish 2 'ERROR' ($problems -join '; ') }
  if ($To -eq 'back' -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup; Say 'the backup is removed' }
  Finish 0 'PASS' "the station runs profiles\$expected ($expectedId); radio $($read.state)"
} catch {
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $($_.Exception.Message)"
}
