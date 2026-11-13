# User-level update of the HB9BLA station (no administrator rights; setup-once.ps1 has set the
# scheduled task up once). It carries out the standing deploy policy of
# docs/harness/Project-Specifics.md (Deployment authority); every step is in this file or in
# another pinned mechanism file of the package.
#   <package>\deploy\tools\deploy\station-update\station-update.ps1 -Manifest <package>\manifest.json [-DryRun] [-OkComment <id>]
#   station-update.ps1 -Rollback
#  1. Package: only a package whose gate receipt says the push gate passed for exactly this
#     commit and executable, and whose commit is on GitHub master.
#  2. Pins: it runs only as the package's own copy. Each mechanism file of the package and the
#     launcher in the station folder must equal the pins of the commit (git show of its
#     Project-Specifics.md, never a working folder), and those pins must equal the pins of the
#     running commit. Otherwise, or when either commit has no pins, it refuses before any write
#     and prints the line the operator posts (Deploy OK: ...). It goes on only with -OkComment,
#     the id of the operator's comment whose whole text is exactly that line.
#  3. Idle: inside update.lock, which it then holds until the station has stopped: no live radio
#     lease, one station process, transmit disarmed, PTT released, not transmitting, no contact
#     other than idle, completed or cancelled, no automation run other than stopped. A state that
#     cannot be read is busy. While busy it reads again every 10 s for up to 300 s, then gives up
#     with the station untouched.
#  4. Switch: stages station\<version>, stops the station gracefully (Ctrl+C: the transmit owner
#     releases PTT on it), writes a changed launcher (only with an OK; the old one is saved),
#     switches active.json, starts the task and checks the new version answers; otherwise it
#     switches back, profile and launcher restored. The task itself is never changed.
#  5. Proof: the probe runs inside the lock; then the lock is released and the live page check
#     runs (it takes the lock itself for its restart). Probe not PASS, page check RED or ERROR:
#     the previous version is put back without asking, under the lock again. Page check BUSY or
#     NOT-EXERCISED: no return; the result is recorded.
#  6. Record: posted on each CR issue the install moves to installed (cr_state.py installed),
#     or, after a return, on each issue the installed commits name.
# -Rollback returns to the previous version and never asks. Every step is logged to
# logs\update-<ts>.log in the station folder.
# Exit 0: installed, or the dry run passed. 1: refused, failed or returned. 3: the station stayed
# busy, nothing changed. 5: the deploy mechanism changed, the operator's OK is needed.
param([string]$Manifest, [switch]$DryRun, [switch]$Rollback, [string]$OkComment, [string]$Repo = 'D:\Github\wsjtx-rust')
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$Station=Join-Path $env:LOCALAPPDATA 'WstxRust\station'
$TaskName='WSTX Rust Station HB9BLA'
$RuleName='WSTX-Station-HB9BLA-18081'
$Url='https://192.168.0.37:18081'
$GitHubRepo='SensorsIot/wsjtx-rust'
$Operator='SensorsIot'
$Shared=Join-Path $Repo '.git\harness-parallel'
# The mechanism files in pin order (Project-Specifics.md, Deploy pins).
$MechanismPaths=@('tools/deploy/station-update/station-update.ps1','tools/deploy/station-update/make_package.py','tools/deploy/station-update/launcher.ps1','tools/deploy/agent-client.ps1','tools/deploy/station-probe.ps1','tools/deploy/live-page-check.ps1')
$LauncherPin='tools/deploy/station-update/launcher.ps1'
$BusyWaitSeconds=300; $BusyPollSeconds=10
$activePath=Join-Path $Station 'active.json'
$profileDir=Join-Path $Station 'profiles\ic7300'
$stationLauncher=Join-Path $Station 'launcher.ps1'
function Now { (Get-Date).ToUniversalTime() }
$stamp=(Now).ToString('yyyyMMddTHHmmssZ')
$log=Join-Path $Station "logs\update-$stamp.log"
$saved=Join-Path $Station "logs\update-$stamp-profile"
$savedLauncher=Join-Path $Station "logs\update-$stamp-launcher.ps1"
$script:Lock=$null; $script:Session=$null; $script:launcherWritten=$false
function Step($t){ $line=((Now).ToString('HH:mm:ss'))+' '+$t; Write-Output $line; Add-Content -LiteralPath $log -Value $line }
function Hash($p){ (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() }
function Safe-Child($Root,$Path) {
  if ($Path -match ':' -and -not [IO.Path]::IsPathRooted($Path)) { throw "Refused path $Path." }
  $r=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'; $p=[IO.Path]::GetFullPath($Path)
  if (-not $p.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes $Root." }
  if ($p.Substring($r.Length) -match ':' -or ($p.Split('\') | Where-Object { $_ -match '[. ]$' })) { throw "Refused path $p." }
  $cursor=$p
  while ($cursor) {
    if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Reparse point refused: $cursor" }
    if ($cursor.TrimEnd('\') -eq $r.TrimEnd('\')) { break }; $cursor=Split-Path -Parent $cursor
  }
  return $p
}
function Station-Processes { @(Get-CimInstance Win32_Process -Filter "Name='wstx-rust.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith("$Station\",[StringComparison]::OrdinalIgnoreCase) }) }
function Assert-Setup {
  $args0=[string](Get-ScheduledTask -TaskName $TaskName).Actions[0].Arguments
  if ($args0 -notlike "*-File*$Station\launcher.ps1*") { throw 'setup-once.ps1 has not been run (task does not use launcher.ps1).' }
}
function Firewall-Scope {
  $r=Get-NetFirewallRule -Name $RuleName; $a=$r|Get-NetFirewallAddressFilter; $p=$r|Get-NetFirewallPortFilter
  "$($r.Enabled)|$($r.Direction)|$($r.Action)|$($a.LocalAddress)|$($a.RemoteAddress)|$($p.Protocol)|$($p.LocalPort)"
}
$ExpectedScope='True|Inbound|Allow|192.168.0.37|192.168.0.6|TCP|18081'
function Send-CtrlC([int]$TargetPid,[int]$CtrlEvent=0) {
  # A separate process attaches to the station's console and raises Ctrl+C there; the
  # station's exit guard stops audio and sends the off-only PTT release.
  $code=@"
Add-Type -Namespace W -Name C -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint p); [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(System.IntPtr h, bool a); [DllImport("kernel32.dll")] public static extern bool GenerateConsoleCtrlEvent(uint e, uint g);'
[W.C]::FreeConsole() | Out-Null
if (-not [W.C]::AttachConsole($TargetPid)) { exit 3 }
[W.C]::SetConsoleCtrlHandler([IntPtr]::Zero, `$true) | Out-Null
if (-not [W.C]::GenerateConsoleCtrlEvent($CtrlEvent, 0)) { exit 4 }
Start-Sleep -Milliseconds 500
exit 0
"@
  $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  $p=Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$enc) -WindowStyle Hidden -PassThru -Wait
  return $p.ExitCode
}
function Stop-Station {
  $procs=@(Station-Processes)
  foreach ($q in $procs) {
    $rc=Send-CtrlC $q.ProcessId
    Step "graceful stop (Ctrl+C) sent to PID $($q.ProcessId): helper exit $rc"
  }
  $deadline=(Now).AddSeconds(8)
  while (@(Station-Processes).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  foreach ($q in @(Station-Processes)) { $rc=Send-CtrlC $q.ProcessId 1; Step "Ctrl+C ignored; Ctrl+Break sent to PID $($q.ProcessId): helper exit $rc" }
  $deadline=(Now).AddSeconds(8)
  while (@(Station-Processes).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  $left=@(Station-Processes)
  foreach ($q in $left) { Step "FORCED STOP of PID $($q.ProcessId): PTT release not confirmed (check the radio)"; Stop-Process -Id $q.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($left.Count -gt 0) { Start-Sleep -Seconds 2 }
  if (@(Station-Processes).Count -ne 0) { throw 'station process did not exit' }
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { Step "note: Stop-ScheduledTask: $($_.Exception.Message)" }
  $deadline=(Now).AddSeconds(10)
  while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 300 }
  if ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running') { throw 'task still Running after the station exited; a restart would be ignored' }
}
function Start-Ready($commit) {
  Start-ScheduledTask -TaskName $TaskName
  $exe=Join-Path (Join-Path $Station $commit.Substring(0,9)) 'wstx-rust.exe'
  $deadline=(Now).AddSeconds(60)
  do {
    Start-Sleep -Seconds 2
    try {
      $page=Invoke-WebRequest -UseBasicParsing -Uri "$Url/" -TimeoutSec 5
      $r=Get-Content -LiteralPath "$Station\station-running.json" -Raw | ConvertFrom-Json
      $live=Get-CimInstance Win32_Process -Filter "ProcessId=$($r.process_id)"
      if ($page.StatusCode -eq 200 -and $r.source_commit -eq $commit -and $r.launcher -eq 'active.json' -and $live -and $live.ExecutablePath -eq $exe) { return $r }
    } catch {}
  } while ((Now) -lt $deadline)
  throw "station $($commit.Substring(0,9)) did not become ready within 60 s"
}
function Write-Active($commit,$previous) {
  $obj=[ordered]@{version=$commit.Substring(0,9);source_commit=$commit;previous=$previous;switched_utc=(Now).ToString('o')}
  $tmp="$activePath.tmp"; [IO.File]::WriteAllText($tmp,($obj|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::Replace($tmp,$activePath,[NullString]::Value)
}
function Save-Profile { $null=New-Item -ItemType Directory -Force -Path $saved; Get-ChildItem -LiteralPath $profileDir -File -Filter '*.json' | Copy-Item -Destination $saved; Step "profile json files saved to $saved" }
function Restore-Profile { if (Test-Path -LiteralPath $saved) { Get-ChildItem -LiteralPath $saved -File | Copy-Item -Destination $profileDir -Force; Step 'profile json files restored to their state before the update (changes made by the failed version are undone)' } }
function Restore-Launcher { if ($script:launcherWritten -and (Test-Path -LiteralPath $savedLauncher)) { Copy-Item -LiteralPath $savedLauncher -Destination $stationLauncher -Force; Step 'launcher restored to its state before the update' } }
function Switch-Back($from,$to,[bool]$restoreProfile) {
  try {
    Step "switching back to $($to.Substring(0,9))"
    Stop-Station
    if ($restoreProfile) { Restore-Profile; Restore-Launcher }
    Write-Active $to $null
    $r=Start-Ready $to
    Step "restored: $($to.Substring(0,9)) running, PID $($r.process_id)"
  } catch {
    Step "STATION DOWN: switch-back to $($to.Substring(0,9)) failed: $($_.Exception.Message). active.json=$((Get-Content -LiteralPath $activePath -Raw) -replace '\s+',' ')"
    throw
  }
}
# The pins a commit states (Project-Specifics.md, section Deploy pins, read with git show), in
# their order, or $null when it states none.
function Read-Pins([string]$Commit) {
  $text=@(& git -C $Repo show "${Commit}:docs/harness/Project-Specifics.md")
  if ($LASTEXITCODE -ne 0) { return $null }
  $pins=@(); $in=$false
  foreach ($line in $text) {
    if ($line -match '^#{1,6} ') { $in=($line -match '^#{1,6} Deploy pins\s*$'); continue }
    if ($in -and $line -match '^([0-9a-f]{64})  (\S+)\s*$') { $pins+=[pscustomobject]@{ sha256=$Matches[1]; path=$Matches[2] } }
  }
  if ($pins.Count -eq 0) { return $null }
  return ,$pins
}
function Pins-Text($pins) { (@($pins) | ForEach-Object { "$($_.sha256)  $($_.path)" }) -join "`n" }
# Throws unless comment $Id is by the operator and its whole text is $Line.
function Assert-Ok([string]$Id,[string]$Line) {
  if ($Id -notmatch '^[0-9]{1,20}$') { throw "OK refused: -OkComment $Id is not a comment id." }
  $raw=@(& gh api "repos/$GitHubRepo/issues/comments/$Id")
  if ($LASTEXITCODE -ne 0 -or $raw.Count -eq 0) { throw "OK refused: comment $Id cannot be read from GitHub." }
  try { $c=($raw -join "`n") | ConvertFrom-Json; $author=[string]$c.user.login; $body=[string]$c.body }
  catch { throw "OK refused: comment $Id cannot be read from GitHub." }
  if ($author -ne $Operator) { throw "OK refused: comment $Id is by $author, not by $Operator." }
  if ($body.Trim() -cne $Line) { throw "OK refused: comment $Id is not exactly the line for this commit and these scripts." }
}
function Take-Lock {
  try { $script:Lock=[IO.File]::Open((Join-Path $Station 'logs\update.lock'),'OpenOrCreate','ReadWrite','None'); return $true } catch { return $false }
}
# The three readings of the station's state, one session for the whole wait (a login every
# 10 s runs into the station's login limit).
function Read-State {
  if (-not $script:Session) { $script:Session=Open-AgentSession }
  $t=Agent-Get $script:Session '/transmit'; $c=(Agent-Get $script:Session '/contact').contact; $a=(Agent-Get $script:Session '/automation').run
  return ,@($t,$c,$a)
}
# Why the station is not idle now, or $null. It takes update.lock and keeps it only when idle.
function Station-Busy {
  if (-not (Take-Lock)) { return 'the update lock is held (an update, a radio preflight or a page check is running)' }
  $why=Busy-Reason
  if ($why) { $script:Lock.Dispose(); $script:Lock=$null }
  return $why
}
function Busy-Reason {
  $leaseFile=Join-Path $Shared 'radio\lease.json'
  if (Test-Path -LiteralPath $leaseFile) {
    try { $lease=[IO.File]::ReadAllText($leaseFile) | ConvertFrom-Json; $until=[DateTime]::Parse([string]$lease.expires,[Globalization.CultureInfo]::InvariantCulture,'AdjustToUniversal,AssumeUniversal') }
    catch { return 'the radio lease cannot be read' }
    if ($until -gt (Now)) { return "$($lease.holder) holds the radio lease until $($lease.expires)" }
  }
  $procs=@(Station-Processes)
  if ($procs.Count -ne 1) { return "$($procs.Count) station processes are running" }
  try { $s=Read-State }
  catch {
    $script:Session=$null
    try { $s=Read-State } catch { return "its state cannot be read ($($_.Exception.GetType().Name))" }
  }
  try {
    $transmit=$s[0]; $contact=$s[1]; $run=$s[2]
    if ([string]$transmit.transmit.arm_state -ne 'disarmed') { return "transmit is $($transmit.transmit.arm_state)" }
    if ([string]$transmit.ptt -ne 'released' -or $transmit.transmitting -ne $false) { return "PTT is $($transmit.ptt), transmitting: $($transmit.transmitting)" }
    if ($contact -and [string]$contact.state -notin @('idle','completed','cancelled')) { return "a contact is $($contact.state)" }
    if ($run -and [string]$run.state -ne 'stopped') { return "an automation run is $($run.state)" }
  } catch { return "its state cannot be read ($($_.Exception.GetType().Name))" }
  return $null
}
function Clean([string]$t) { $t -replace '[''"$`]','' }
function Last-Line($lines,[string]$prefix) {
  $m=@($lines | Where-Object { ([string]$_).StartsWith($prefix) })
  if ($m.Count) { return [string]$m[-1] }
  return "no $($prefix.Trim()) line"
}
# The issues the install moves to installed (their state change is cr_state.py's).
function Move-Installed($commit,$previous) {
  Push-Location -LiteralPath $Repo
  try { $out=@(& python (Join-Path $Repo 'harness\core\tools\cr_state.py') installed $commit --since $previous) } finally { Pop-Location }
  return ,$out
}
# The issues the subjects of previous..commit name (this repository's #N only).
function Issues-Named($commit,$previous) {
  $subjects=@(& git -C $Repo log --format=%s "$previous..$commit")
  $n=@(); foreach ($s in $subjects) { foreach ($m in [regex]::Matches([string]$s,'(?<![\w/.-])#([0-9]+)\b')) { $n+=[int]$m.Groups[1].Value } }
  return ,@($n | Sort-Object -Unique)
}

$null=New-Item -ItemType Directory -Force -Path (Join-Path $Station 'logs')
Assert-Setup
$scope=Firewall-Scope
if ($scope -ne $ExpectedScope) { throw "Firewall rule scope is $scope, expected $ExpectedScope." }
$active=Get-Content -LiteralPath $activePath -Raw | ConvertFrom-Json
$current=[string]$active.source_commit
if ($current -notmatch '^[0-9a-f]{40}$') { throw 'active.json has no valid source_commit.' }

if ($Rollback) {
  if (-not (Take-Lock)) { throw 'Another station update is running.' }
  $target=[string]$active.previous
  if ($target -notmatch '^[0-9a-f]{40}$') { throw 'No previous version recorded.' }
  if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $Station $target.Substring(0,9)) 'wstx-rust.exe'))) { throw 'Previous version is not staged.' }
  Step "rollback: $($current.Substring(0,9)) -> $($target.Substring(0,9))"
  Switch-Back $current $target $false
  return
}

if (-not $Manifest) { throw 'Give -Manifest <package manifest.json> or -Rollback.' }
$Manifest=(Resolve-Path -LiteralPath $Manifest).Path
$root=Split-Path -Parent $Manifest
Step "verify package: $Manifest"
$m=Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$commit=[string]$m.source_commit
if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Manifest source_commit is not a full commit id.' }
$ver=$commit.Substring(0,9)
$package=Safe-Child $root (Join-Path $root 'package')
$files=@($m.package_files)
if (-not ($files.path -contains 'wstx-rust.exe')) { throw 'Package has no wstx-rust.exe.' }
foreach ($f in $files) {
  if ($f.sha256 -notmatch '^[a-f0-9]{64}$') { throw "Package file $($f.path) has no SHA256." }
  $src=Safe-Child $package (Join-Path $package $f.path)
  if ((Hash $src) -ne $f.sha256) { throw "Package file $($f.path) does not match the manifest." }
}
$exeHash=Hash (Join-Path $package 'wstx-rust.exe')
if ($m.artifact_sha256 -ne $exeHash) { throw 'Manifest artifact_sha256 is not the packaged executable.' }
$gatePath=Safe-Child $root ([string]$m.gate_receipt_path)
if ([string]$m.gate_receipt_sha256 -notmatch '^[a-f0-9]{64}$' -or (Hash $gatePath) -ne $m.gate_receipt_sha256) { throw 'Gate receipt missing or changed.' }
$g=Get-Content -LiteralPath $gatePath -Raw | ConvertFrom-Json
if ($g.source_commit -ne $commit -or $g.artifact_sha256 -ne $exeHash -or $g.prepush_passed -ne $true -or $g.status -ne 'passed' -or $null -eq $g.gate_receipt) { throw 'Gate receipt does not say the push gate passed for this commit and executable.' }
if ((Hash ([string]$g.gate_receipt.path)) -ne $g.gate_receipt.sha256) { throw 'Push-gate log changed.' }
& git -C $Repo fetch -q origin master
if ($LASTEXITCODE -ne 0) { throw 'git fetch of GitHub master failed.' }
& git -C $Repo merge-base --is-ancestor $commit FETCH_HEAD
if ($LASTEXITCODE -ne 0) { throw "Commit $ver is not on GitHub master." }
Step "package verified: $ver, exe $($exeHash.Substring(0,12)), gate passed, on GitHub master"

# The mechanism: this script, the probe, the page check, the agent client and the launcher all
# come from the package, whose files make_package.py copied from the commit's export.
$deployRoot=Safe-Child $root (Join-Path $root 'deploy')
$self=Join-Path $deployRoot 'tools\deploy\station-update\station-update.ps1'
if ([IO.Path]::GetFullPath($PSCommandPath) -ne [IO.Path]::GetFullPath($self)) { throw "Refused: run the package's own copy $self, not $PSCommandPath." }
$computed=@(foreach ($p in $MechanismPaths) {
  $f=Safe-Child $deployRoot (Join-Path $deployRoot ($p -replace '/','\'))
  if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "The package lacks the mechanism file $p." }
  [pscustomobject]@{ path=$p; sha256=(Hash $f) }
})
$AgentClient=Join-Path $deployRoot 'tools\deploy\agent-client.ps1'
$probeScript=Join-Path $deployRoot 'tools\deploy\station-probe.ps1'
$pageScript=Join-Path $deployRoot 'tools\deploy\live-page-check.ps1'
$packageLauncher=Join-Path $deployRoot 'tools\deploy\station-update\launcher.ps1'
$newPins=Read-Pins $commit
$runPins=Read-Pins $current
$why=@()
if ($null -eq $newPins) { $why+="commit $ver has no deploy pins" }
else {
  if ((@($newPins | ForEach-Object { $_.path }) -join ' ') -ne ($MechanismPaths -join ' ')) { $why+="the pins of $ver do not name the mechanism files in their order" }
  foreach ($c in $computed) {
    $pin=@($newPins | Where-Object { $_.path -eq $c.path })
    if ($pin.Count -ne 1 -or $pin[0].sha256 -ne $c.sha256) { $why+="$($c.path) differs from its pin" }
  }
  $lp=@($newPins | Where-Object { $_.path -eq $LauncherPin })
  if (-not (Test-Path -LiteralPath $stationLauncher) -or $lp.Count -ne 1 -or (Hash $stationLauncher) -ne $lp[0].sha256) { $why+='the launcher in the station folder differs from its pin' }
}
if ($null -eq $runPins) { $why+="the running commit $($current.Substring(0,9)) has no deploy pins" }
elseif ($null -ne $newPins -and (Pins-Text $newPins) -ne (Pins-Text $runPins)) { $why+="the pins of $ver differ from those of the running $($current.Substring(0,9))" }
$okLine="Deploy OK: $commit scripts "+((@($computed | ForEach-Object { $_.sha256 })) -join ' ')
$okId=$null
if ($why.Count) {
  foreach ($w in $why) { Step "deploy mechanism changed: $w" }
  if (-not $OkComment) {
    Step 'Item 5: the deploy mechanism changed, nothing was changed. The operator posts exactly the next line as a comment; then run again with -OkComment <its id>:'
    Write-Output $okLine; Add-Content -LiteralPath $log -Value $okLine
    exit 5
  }
  Assert-Ok $OkComment $okLine
  $okId=$OkComment
  Step "operator OK: comment $okId names this commit and these scripts"
} else { Step "deploy mechanism equals its pins: $($computed.Count) files" }

$target=Safe-Child $Station (Join-Path $Station $ver)
if (Test-Path -LiteralPath $target) {
  foreach ($f in $files) { $d=Safe-Child $target (Join-Path $target $f.path); if (-not (Test-Path -LiteralPath $d) -or (Hash $d) -ne $f.sha256) { throw "Existing $target differs from the package ($($f.path)); move it aside first." } }
}
Step "current: $($current.Substring(0,9)); new: $ver"
if ($DryRun) { Step 'dry run: nothing changed'; return }
if ($current -eq $commit) { Step 'already active'; return }

# Idle, inside update.lock; from here the lock is held until the station has stopped.
. $AgentClient
$waitStart=Now
$busy=Station-Busy
while ($busy -and ((Now)-$waitStart).TotalSeconds -lt $BusyWaitSeconds) { Step "waiting: $busy"; Start-Sleep -Seconds $BusyPollSeconds; $busy=Station-Busy }
if ($busy) { Step "BUSY: the station was not idle for $BusyWaitSeconds s, nothing changed: $busy"; exit 3 }
Step 'station idle; update.lock held'

if (Test-Path -LiteralPath $target) { Step "staged copy already present and identical: $target" }
else {
  $partial="$target.partial"
  if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Recurse -Force }
  foreach ($f in $files) {
    $d=Safe-Child $partial (Join-Path $partial $f.path)
    $null=New-Item -ItemType Directory -Force -Path (Split-Path -Parent $d)
    Copy-Item -LiteralPath (Join-Path $package $f.path) -Destination $d
    if ((Hash $d) -ne $f.sha256) { throw "Copy of $($f.path) is corrupt." }
  }
  Rename-Item -LiteralPath $partial -NewName (Split-Path -Leaf $target)
  Step "staged: $target"
}
$writeLauncher=($null -ne $okId) -and (-not (Test-Path -LiteralPath $stationLauncher) -or (Hash $stationLauncher) -ne (Hash $packageLauncher))

$switched=$false
$stepName='save profile'
try {
  Save-Profile
  if ($writeLauncher) { Copy-Item -LiteralPath $stationLauncher -Destination $savedLauncher; Step "launcher saved to $savedLauncher" }
  $stepName='stop station'; Step $stepName
  Stop-Station
  $switched=$true
  if ($writeLauncher) {
    $stepName='write launcher'; Step $stepName
    $script:launcherWritten=$true
    Copy-Item -LiteralPath $packageLauncher -Destination $stationLauncher -Force
    if ((Hash $stationLauncher) -ne (Hash $packageLauncher)) { throw 'Copy of the launcher is corrupt.' }
  }
  $stepName='switch active.json'; Step $stepName
  Write-Active $commit $current
  $stepName='start new version'; Step $stepName
  $r=Start-Ready $commit
  if ((Firewall-Scope) -ne $ExpectedScope) { throw 'Firewall scope changed.' }
  Step "started: $ver running, PID $($r.process_id); previous $($current.Substring(0,9)) kept for -Rollback"
} catch {
  Step "FAILED at step '$stepName': $($_.Exception.Message)"
  if ($switched) { Switch-Back $commit $current $true }
  else {
    try { if (@(Station-Processes).Count -eq 0) { $r=Start-Ready $current; Step "restarted unchanged $($current.Substring(0,9)), PID $($r.process_id)" } }
    catch { Step "STATION DOWN: restart of $($current.Substring(0,9)) failed: $($_.Exception.Message)"; throw }
  }
  exit 1
}

# Proof: the probe inside the lock, then the page check with the lock released.
$probeLine='not run'; $pageLine='not run'; $returned=$null
$stepName='probe'; Step $stepName
$probeOut=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probeScript -Manifest $Manifest | ForEach-Object { [string]$_ })
$probeRc=$LASTEXITCODE
foreach ($l in $probeOut) { Step "probe: $l" }
$probeLine=Last-Line $probeOut 'PROBE '
if ($probeRc -ne 0) { $returned="probe exit $probeRc" }
else {
  $script:Lock.Dispose(); $script:Lock=$null
  $stepName='live page check'; Step 'update.lock released for the live page check'
  $pageOut=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $pageScript -Repo $Repo -Shared $Shared -AgentClient $AgentClient -Station $Station | ForEach-Object { [string]$_ })
  $pageRc=$LASTEXITCODE
  foreach ($l in $pageOut) { Step "page check: $l" }
  $pageLine=Last-Line $pageOut 'LIVE PAGE CHECK '
  if ($pageRc -notin @(0,3,4)) {
    $returned="page check exit $pageRc"
    $deadline=(Now).AddSeconds($BusyWaitSeconds)
    while (-not (Take-Lock) -and (Now) -lt $deadline) { Step 'waiting for update.lock to return to the previous version'; Start-Sleep -Seconds $BusyPollSeconds }
  }
}
$exit=0
if ($returned) {
  $exit=1
  if (-not $script:Lock) { Step "STATION NOT RETURNED: update.lock stayed held for $BusyWaitSeconds s ($returned); run station-update.ps1 -Rollback"; $returned="$returned, NOT RETURNED: update.lock held" }
  else {
    Step "returning to the previous version: $returned"
    try { Switch-Back $commit $current $true } catch { $returned="$returned, RETURN FAILED: $($_.Exception.Message)" }
  }
}

# The install record, on each CR issue the install moves (or, after a return, names).
$lines=@("Install record: $commit $(if ($returned) { 'returned' } else { 'installed' })",
  "Previous version: $current",
  "Package executable SHA-256: $exeHash",
  'Mechanism files (SHA-256 and path):')
$lines+=@($computed | ForEach-Object { "$($_.sha256) $($_.path)" })
$lines+=@("Probe: $probeLine", "Page check: $pageLine",
  "Operator OK comment: $(if ($okId) { $okId } else { 'none' })",
  "Return to the previous version: $(if ($returned) { "to $current ($returned); each CR of this install goes back to step 2" } else { 'none' })")
$record=Clean ($lines -join "`n")
foreach ($l in ($record -split "`n")) { Step "record: $l" }
if ($returned) { $issues=Issues-Named $commit $current }
else {
  $moved=Move-Installed $commit $current
  foreach ($l in $moved) { Step "cr_state: $l" }
  $issues=@($moved | ForEach-Object { if ([string]$_ -match '^#([0-9]+)(:? already| .* ->) installed$') { [int]$Matches[1] } } | Sort-Object -Unique)
}
if (-not @($issues).Count) { Step 'record not posted: no CR issue found for this install' }
foreach ($n in @($issues)) {
  & gh issue comment $n --repo $GitHubRepo --body $record
  if ($LASTEXITCODE -eq 0) { Step "record posted on #$n" } else { Step "record NOT posted on #$n (gh exit $LASTEXITCODE)" }
}
exit $exit
