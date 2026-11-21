# Switches the station between the operator profile and the simulator profile SIM-IC7300 for live
# tests on the FT-8 Band Simulator
# (harness/project/docs/specifics/deployment-authority.md, Simulator live tests, Switch). It needs no administrator rights.
#   station-switch.ps1 -To simulator     the tester or the coordinator
#   station-switch.ps1 -To back          the tester as its run's last step, or the coordinator
#   -DryRun prints every step and changes nothing (it still reads the station's state).
# -To simulator, in this order:
#   1. refuses unless profiles\SIM-IC7300 exists and names no COM3; hashes the operator profile
#      ic7300 (profile.json, contacts.adi); a station in use exits 3. The build check: the
#      running build's source commit (the x-wstx-source-commit header of GET / and
#      station-running.json, as station-probe.ps1 reads them) must be one 40-hex commit this
#      checkout holds whose server/src/radioControl/radio_setup.rs names radio-discovery.json;
#      otherwise nothing is switched (an older build would discover a radio on a silent COM4).
#   2. backs up station\launcher.ps1 once (launcher.ps1.before-simulator; a launcher already
#      switched is not backed up again);
#   3. stops the station gracefully (Ctrl+C, station-control.ps1);
#   4. writes the isolation settings into profiles\SIM-IC7300 only, each read back: pskr.json
#      enabled false, radio-discovery.json at_start false, and udp.json without targets unless
#      every target is on 127.0.0.1 and none on the operator logger's port 2237;
#   5. points the launcher's profile line at profiles\SIM-IC7300 and removes every line naming one
#      of the removed switch variables (WSTX_ followed by PSKR, UDP or RADIO_DISCOVERY);
#   6. starts the station's scheduled task;
#   7. reads back GET /radio, the receipt (station-running.json), no COM3, GET /pskr enabled false,
#      radio-discovery.json, the launcher and the operator hashes. A difference stops the station.
# A failed write or read-back in 4 or 5 leaves the station stopped and the launcher unchanged.
# -To back writes the backup back, or, without one, the repository's pinned launcher (what a
# deploy writes), restarts the station and reads its profile back; it writes no profile.
# It never writes in profiles\ic7300, never changes a CAT endpoint and keys nothing.
# Exit 0: SWITCH PASS, the station reads the profile asked for. Exit 2: SWITCH ERROR. Exit 3:
# SWITCH BUSY, the station is in use (PTT, a contact, an update) and was not touched.
param([string]$To, [switch]$DryRun, [string]$Station, [string]$AgentClient, [string]$Pin,
      [string]$Repo, [string]$Url = 'https://192.168.0.37:18081',
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
# A launcher line naming one of the removed switch variables, which the station does not read.
$RemovedSwitch = '(?m)^[^\r\n]*\bWSTX_(?:PSKR|UDP|RADIO_DISCOVERY)\b[^\r\n]*(?:\r?\n|$)'
$LoggerPort = 2237
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
# The parsed JSON of a file of the simulator profile, or $null when absent or unreadable.
function Sim-Json([string]$name) {
  $path = Join-Path $Station "profiles\$SimProfile\$name"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { $null }
}
function Has($o, [string]$key) { $null -ne $o -and $null -ne $o.PSObject.Properties[$key] }
# $null when every UDP target of the simulator profile is on 127.0.0.1 and none on the
# operator logger's port; else why its targets are emptied. It only reads udp.json.
function Udp-Loopback {
  $path = Join-Path $Station "profiles\$SimProfile\udp.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return 'the simulator profile has no udp.json' }
  try { $udp = [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { return "udp.json cannot be read: $($_.Exception.Message)" }
  $targets = @(if (Has $udp 'targets') { $udp.targets })
  if ($targets.Count -eq 0) { return 'udp.json has no target' }
  foreach ($t in $targets) {
    $address = if (Has $t 'address') { [string]$t.address } else { '' }
    $m = [regex]::Match($address, '^127\.0\.0\.1:(\d{1,5})$')
    if (-not $m.Success) { return "the target '$address' is not on 127.0.0.1" }
    if ([int]$m.Groups[1].Value -eq $LoggerPort) { return "the target $address is on the operator logger's port $LoggerPort" }
  }
  $null
}
function Simulator-Launcher([string]$text) {
  $text = [regex]::Replace($text, $ProfileLine, { param($m) $m.Value.Replace("profiles\$($m.Groups[1].Value)'", "profiles\$SimProfile'") })
  [regex]::Replace($text, $RemovedSwitch, '')
}
# The isolation settings of the simulator profile, each in its full form: name -> text, in the
# order they are written. udp.json is left out when Udp-Loopback keeps it.
function Isolation-Files([string]$id, $udpWhy) {
  $q = ConvertTo-Json $id
  $saved = Sim-Json 'pskr.json'
  $use = $true
  if ((Has $saved 'schema_version') -and $saved.schema_version -eq 2 -and (Has $saved 'profile_id') -and [string]$saved.profile_id -ceq $id -and (Has $saved 'use') -and $saved.use -is [bool]) { $use = $saved.use }
  $files = [ordered]@{}
  $files['pskr.json'] = '{"schema_version":2,"profile_id":' + $q + ',"enabled":false,"use":' + $(if ($use) { 'true' } else { 'false' }) + '}'
  $files['radio-discovery.json'] = '{"schema_version":1,"profile_id":' + $q + ',"at_start":false}'
  if ($udpWhy) {
    $udp = Sim-Json 'udp.json'
    $revision = 0
    if ((Has $udp 'revision') -and ($udp.revision -is [int] -or $udp.revision -is [long]) -and $udp.revision -ge 0) { $revision = $udp.revision + 1 }
    $files['udp.json'] = '{"schema_version":1,"profile_id":' + $q + ',"revision":' + $revision + ',"targets":[]}'
  }
  $files
}
# Writes $text as UTF-8 without BOM and reads it back; $null, or why it failed.
function Write-Checked([string]$path, [string]$text) {
  try { [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false)) } catch { return "the write failed: $($_.Exception.Message)" }
  try { $back = Get-Content -LiteralPath $path -Raw -Encoding UTF8 } catch { return "it cannot be read back: $($_.Exception.Message)" }
  if ([string]$back -cne $text) { return 'it does not read back as written' }
  $null
}
# Exit code of git in the checkout; any failure to run it is not 0.
function Git-Rc([string[]]$gitArgs) {
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & git -C $Repo @gitArgs 2>&1 | Out-Null; [int]$LASTEXITCODE } catch { 1 } finally { $ErrorActionPreference = $eap }
}
# The build check: the running build's commit, or why the switch refuses it.
function Build-Check {
  $result = [pscustomobject]@{ commit = 'unknown'; why = $null }
  if (@(Station-Procs).Count -eq 0) { $result.why = 'no station is running'; return $result }
  [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
  try { $page = Invoke-WebRequest -UseBasicParsing -Uri "$Url/" -TimeoutSec 10 } catch { $result.why = "GET $Url/ did not answer ($($_.Exception.GetType().Name))"; return $result }
  $reported = @($page.Headers['x-wstx-source-commit'] | Where-Object { $null -ne $_ })
  if ($reported.Count -ne 1) { $result.why = "GET / reports $($reported.Count) source commits, not one"; return $result }
  $header = [string]$reported[0]
  if ($header -cnotmatch '^[0-9a-f]{40}$') { $result.why = "GET / reports the source commit '$header', not 40 hex digits"; return $result }
  $result.commit = $header
  try { $receipt = [IO.File]::ReadAllText((Join-Path $Station 'station-running.json')) | ConvertFrom-Json } catch { $result.why = "station-running.json cannot be read: $($_.Exception.Message)"; return $result }
  $kept = if (Has $receipt 'source_commit') { [string]$receipt.source_commit } else { '' }
  if ($kept -cne $header) { $result.why = "station-running.json names the source commit '$kept', GET / $header"; return $result }
  if ((Git-Rc @('cat-file', '-e', "${header}^{commit}")) -ne 0) { $result.why = "the checkout $Repo does not hold $header"; return $result }
  if ((Git-Rc @('grep', '-q', 'radio-discovery.json', $header, '--', 'server/src/radioControl/radio_setup.rs')) -ne 0) { $result.why = "its server/src/radioControl/radio_setup.rs names no radio-discovery.json"; return $result }
  $result
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
function Stop-Half {
  $procs = @(Station-Procs)
  if ($procs.Count -eq 1) { Act "stop the station gracefully (Ctrl+C to process $($procs[0].ProcessId)), then its task '$TaskName'" { Stop-Station $procs[0] } }
  else { Say 'the station is not running' }
}
function Start-Half { Act "start the task '$TaskName' and wait for the station" { Start-Station } }
# The station's own report: GET /radio's profile_id, GET /pskr's enabled and the launcher's
# receipt for the running process.
function Read-Back($expected) {
  $deadline = (Now).AddSeconds($ReadBackSeconds); $last = 'no answer'
  . $AgentClient
  for (;;) {
    try {
      $procs = @(Station-Procs)
      if ($procs.Count -ne 1) { throw "$($procs.Count) station processes" }
      $receipt = [IO.File]::ReadAllText((Join-Path $Station 'station-running.json')) | ConvertFrom-Json
      if ([int]$receipt.process_id -ne [int]$procs[0].ProcessId) { throw "the receipt names process $($receipt.process_id), the station runs as $($procs[0].ProcessId)" }
      $session = Open-AgentSession
      $radio = Agent-Get $session '/radio'
      $pskr = if ($To -eq 'simulator') { Agent-Get $session '/pskr' } else { $null }
      return [pscustomobject]@{ receipt = [string]$receipt.profile; profile_id = [string]$radio.profile_id; state = [string]$radio.state; device = [string]$radio.device_id; pid = $procs[0].ProcessId
        pskr = $(if ($pskr -and (Has $pskr 'enabled')) { $pskr.enabled } else { 'not read' }) }
    } catch { $last = $_.Exception.Message }
    if ((Now) -ge $deadline) { throw "no read-back within $ReadBackSeconds s: $last" }
    Start-Sleep -Seconds 2
  }
}

try {
  if ($To -notin @('simulator', 'back')) { Finish 2 'ERROR' "need -To simulator or -To back, not '$To'" }
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  # The repository root is three folders above tools/test/powershell/.
  if (-not $Repo) { $Repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')) }
  if (-not $AgentClient) { $AgentClient = [IO.Path]::GetFullPath((Join-Path $Repo 'tools\deploy\agent-client.ps1')) }
  if (-not $Pin) { $Pin = [IO.Path]::GetFullPath((Join-Path $Repo 'tools\deploy\station-update\launcher.ps1')) }
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
    $udpWhy = Udp-Loopback
    if ($udpWhy) { Say "UDP targets emptied: $udpWhy" }
    else { Say 'UDP kept: every target of the simulator profile is on 127.0.0.1, none on the logger port' }
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

  if ($To -eq 'back') {
    if ($new -ne $current) {
      Act "write $what as the launcher" {
        [IO.File]::WriteAllText($launcher, $new, [Text.UTF8Encoding]::new($false))
        if ([IO.File]::ReadAllText($launcher) -ne $new) { throw 'the launcher does not read back as written' }
      }
    } else { Say 'the launcher is already as wanted; not written' }
    try { Stop-Half; Start-Half }
    catch {
      $msg = $_.Exception.Message
      if ($script:StillRuns) { Finish 2 'ERROR' "THE STATION: $msg" }
      Finish 2 'ERROR' "THE STATION IS DOWN or was not restarted: $msg"
    }
    if ($DryRun) {
      Write-Output "would: read back the station's profile (GET /radio and station-running.json), expecting $expected ($expectedId)"
      Finish 0 'DRY-RUN' "-To ${To}: every step above was printed, nothing was changed"
    }
    $read = Read-Back $expected
    Say "read back: GET /radio profile_id $($read.profile_id), state $($read.state), device $($read.device)"
    Say "read back: station-running.json profile $($read.receipt) (process $($read.pid))"
    $problems = @()
    if ($read.profile_id -ne $expectedId) { $problems += "the station runs profile $($read.profile_id), not $expected ($expectedId)" }
    if (-not $read.receipt.EndsWith("profiles\$expected", [StringComparison]::OrdinalIgnoreCase)) { $problems += "the receipt names $($read.receipt), not profiles\$expected" }
    if ($problems) { Finish 2 'ERROR' ($problems -join '; ') }
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup; Say 'the backup is removed' }
    Finish 0 'PASS' "the station runs profiles\$expected ($expectedId); radio $($read.state)"
  }

  # -To simulator. 1. The build check, before anything is changed.
  $build = Build-Check
  if ($build.why) {
    Say "build check: $($build.why)"
    Finish 2 'ERROR' "the running build $($build.commit) does not read radio-discovery.json: nothing switched"
  }
  Say "build check: the running build $($build.commit) reads radio-discovery.json"
  # 2. The backup.
  if ($now -eq $SimProfile) { Say "the launcher already starts $SimProfile; the backup is not taken again" }
  else { Act "back up the launcher to $backup" { Copy-Item -LiteralPath $launcher -Destination $backup -Force } }
  # 3. The stop.
  try { Stop-Half } catch { Finish 2 'ERROR' "THE STATION: $($_.Exception.Message)" }
  # 4. The isolation settings, in profiles\SIM-IC7300 only.
  $simDir = Join-Path $Station "profiles\$SimProfile"
  $files = Isolation-Files $sim.id $udpWhy
  foreach ($name in $files.Keys) {
    $text = $files[$name]
    if ($DryRun) { Write-Output "would: write profiles\$SimProfile\$name $text"; continue }
    Write-Output "step: write profiles\$SimProfile\$name $text"
    $why = Write-Checked (Join-Path $simDir $name) $text
    if ($why) { Finish 2 'ERROR' "THE STATION IS STOPPED: ${name}: $why" }
  }
  if (-not $files.Contains('udp.json')) { Say 'profiles\SIM-IC7300\udp.json is kept' }
  # 5. The launcher; a failed read-back writes the old text back.
  if ($new -ne $current) {
    if ($DryRun) { Write-Output "would: point the launcher at profiles\$SimProfile, without the removed switch variables" }
    else {
      Write-Output "step: point the launcher at profiles\$SimProfile, without the removed switch variables"
      $why = Write-Checked $launcher $new
      if ($why) {
        $restored = Write-Checked $launcher $current
        if ($restored -and [IO.File]::ReadAllText($launcher) -cne $current) { $why += "; its old text could not be written back: $restored" }
        Finish 2 'ERROR' "THE STATION IS STOPPED: launcher.ps1: $why"
      }
    }
  } else { Say 'the launcher is already as wanted; not written' }
  # 6. The start.
  try { Start-Half }
  catch {
    $msg = $_.Exception.Message
    if ($script:StillRuns) { Finish 2 'ERROR' "THE STATION: $msg" }
    Finish 2 'ERROR' "THE STATION IS DOWN or was not restarted: $msg"
  }
  if ($DryRun) {
    Write-Output "would: read back the station's profile (GET /radio, GET /pskr and station-running.json), expecting $expected ($expectedId)"
    Write-Output 'would: hash the ic7300 profile and logbook again and compare'
    Finish 0 'DRY-RUN' "-To ${To}: every step above was printed, nothing was changed"
  }
  # 7. The read-back; a difference stops the station.
  $problems = @()
  try {
    $read = Read-Back $expected
    Say "read back: GET /radio profile_id $($read.profile_id), state $($read.state), device $($read.device)"
    Say "read back: station-running.json profile $($read.receipt) (process $($read.pid))"
    Say "read back: GET /pskr enabled $($read.pskr)"
    if ($read.profile_id -ne $expectedId) { $problems += "the station runs profile $($read.profile_id), not $expected ($expectedId)" }
    if (-not $read.receipt.EndsWith("profiles\$expected", [StringComparison]::OrdinalIgnoreCase)) { $problems += "the receipt names $($read.receipt), not profiles\$expected" }
    if ($read.device -match '(?i)COM3\b') { $problems += "the station holds $($read.device), the real radio's port" }
    if ($read.pskr -isnot [bool] -or $read.pskr) { $problems += "GET /pskr shows enabled $($read.pskr), not false" }
  } catch { $problems += $_.Exception.Message }
  $discovery = Join-Path $simDir 'radio-discovery.json'
  $onDisk = if (Test-Path -LiteralPath $discovery -PathType Leaf) { [IO.File]::ReadAllText($discovery) } else { 'absent' }
  if ($onDisk -cne $files['radio-discovery.json']) { $problems += "radio-discovery.json reads $onDisk, not as written" }
  $named = [regex]::Matches([IO.File]::ReadAllText($launcher), $RemovedSwitch).Count
  Say "read back: the launcher has $named lines naming a removed switch variable"
  if ($named) { $problems += "the launcher has $named lines naming a removed switch variable" }
  $after = Operator-Hashes
  foreach ($k in $after.Keys) {
    Say "after: $k sha256 $($after[$k])"
    if ($after[$k] -ne $before[$k]) { $problems += "$k changed: $($before[$k]) -> $($after[$k])" }
  }
  if ($problems) {
    $differences = $problems -join '; '
    try { foreach ($p in @(Station-Procs)) { Write-Output "step: stop the station after the read-back (process $($p.ProcessId))"; Stop-Station $p } }
    catch { Finish 2 'ERROR' "THE STATION: $differences; it was not stopped: $($_.Exception.Message)" }
    Finish 2 'ERROR' "THE STATION IS STOPPED: $differences"
  }
  Finish 0 'PASS' "the station runs profiles\$expected ($expectedId); radio $($read.state)"
} catch {
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $($_.Exception.Message)"
}
