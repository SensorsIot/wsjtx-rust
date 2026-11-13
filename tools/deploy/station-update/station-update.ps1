# User-level station update (no administrator rights; setup-once.ps1 must have been run).
#   station-update.ps1 -Manifest <package manifest.json> [-DryRun]
#   station-update.ps1 -Rollback
# Installs only a package whose gate receipt says the push gate passed for exactly this
# commit and executable, and whose commit is on GitHub master. Stages station\<version>,
# stops the running station gracefully (Ctrl+C: the transmit owner releases PTT on it),
# switches active.json, starts the task and checks the new version answers; otherwise it
# switches back (profile files restored). Every step is logged to logs\update-<ts>.log.
param([string]$Manifest, [switch]$DryRun, [switch]$Rollback)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
$Station=Join-Path $env:LOCALAPPDATA 'WstxRust\station'
$TaskName='WSTX Rust Station HB9BLA'
$RuleName='WSTX-Station-HB9BLA-18081'
$Url='https://192.168.0.37:18081'
$Repo='D:\Github\wsjtx-rust'
$activePath=Join-Path $Station 'active.json'
$profileDir=Join-Path $Station 'profiles\ic7300'
$stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$log=Join-Path $Station "logs\update-$stamp.log"
$saved=Join-Path $Station "logs\update-$stamp-profile"
function Step($t){ $line=([DateTime]::UtcNow.ToString('HH:mm:ss'))+' '+$t; Write-Output $line; Add-Content -LiteralPath $log -Value $line }
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
  $deadline=[DateTime]::UtcNow.AddSeconds(8)
  while (@(Station-Processes).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
  foreach ($q in @(Station-Processes)) { $rc=Send-CtrlC $q.ProcessId 1; Step "Ctrl+C ignored; Ctrl+Break sent to PID $($q.ProcessId): helper exit $rc" }
  $deadline=[DateTime]::UtcNow.AddSeconds(8)
  while (@(Station-Processes).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
  $left=@(Station-Processes)
  foreach ($q in $left) { Step "FORCED STOP of PID $($q.ProcessId): PTT release not confirmed (check the radio)"; Stop-Process -Id $q.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($left.Count -gt 0) { Start-Sleep -Seconds 2 }
  if (@(Station-Processes).Count -ne 0) { throw 'station process did not exit' }
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { Step "note: Stop-ScheduledTask: $($_.Exception.Message)" }
  $deadline=[DateTime]::UtcNow.AddSeconds(10)
  while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
  if ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running') { throw 'task still Running after the station exited; a restart would be ignored' }
}
function Start-Ready($commit) {
  Start-ScheduledTask -TaskName $TaskName
  $exe=Join-Path (Join-Path $Station $commit.Substring(0,9)) 'wstx-rust.exe'
  $deadline=[DateTime]::UtcNow.AddSeconds(60)
  do {
    Start-Sleep -Seconds 2
    try {
      $page=Invoke-WebRequest -UseBasicParsing -Uri "$Url/" -TimeoutSec 5
      $r=Get-Content -LiteralPath "$Station\station-running.json" -Raw | ConvertFrom-Json
      $live=Get-CimInstance Win32_Process -Filter "ProcessId=$($r.process_id)"
      if ($page.StatusCode -eq 200 -and $r.source_commit -eq $commit -and $r.launcher -eq 'active.json' -and $live -and $live.ExecutablePath -eq $exe) { return $r }
    } catch {}
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "station $($commit.Substring(0,9)) did not become ready within 60 s"
}
function Write-Active($commit,$previous) {
  $obj=[ordered]@{version=$commit.Substring(0,9);source_commit=$commit;previous=$previous;switched_utc=[DateTime]::UtcNow.ToString('o')}
  $tmp="$activePath.tmp"; [IO.File]::WriteAllText($tmp,($obj|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  [IO.File]::Replace($tmp,$activePath,[NullString]::Value)
}
function Save-Profile { $null=New-Item -ItemType Directory -Force -Path $saved; Get-ChildItem -LiteralPath $profileDir -File -Filter '*.json' | Copy-Item -Destination $saved; Step "profile json files saved to $saved" }
function Restore-Profile { if (Test-Path -LiteralPath $saved) { Get-ChildItem -LiteralPath $saved -File | Copy-Item -Destination $profileDir -Force; Step 'profile json files restored to their state before the update (changes made by the failed version are undone)' } }
function Switch-Back($from,$to,[bool]$restoreProfile) {
  try {
    Step "switching back to $($to.Substring(0,9))"
    Stop-Station
    if ($restoreProfile) { Restore-Profile }
    Write-Active $to $null
    $r=Start-Ready $to
    Step "restored: $($to.Substring(0,9)) running, PID $($r.process_id)"
  } catch {
    Step "STATION DOWN: switch-back to $($to.Substring(0,9)) failed: $($_.Exception.Message). active.json=$((Get-Content -LiteralPath $activePath -Raw) -replace '\s+',' ')"
    throw
  }
}

$null=New-Item -ItemType Directory -Force -Path (Join-Path $Station 'logs')
try { $lock=[IO.File]::Open((Join-Path $Station 'logs\update.lock'),'OpenOrCreate','ReadWrite','None') } catch { throw 'Another station update is running.' }
Assert-Setup
$scope=Firewall-Scope
if ($scope -ne $ExpectedScope) { throw "Firewall rule scope is $scope, expected $ExpectedScope." }
$active=Get-Content -LiteralPath $activePath -Raw | ConvertFrom-Json
$current=[string]$active.source_commit
if ($current -notmatch '^[0-9a-f]{40}$') { throw 'active.json has no valid source_commit.' }

if ($Rollback) {
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

$target=Safe-Child $Station (Join-Path $Station $ver)
if (Test-Path -LiteralPath $target) {
  foreach ($f in $files) { $d=Safe-Child $target (Join-Path $target $f.path); if (-not (Test-Path -LiteralPath $d) -or (Hash $d) -ne $f.sha256) { throw "Existing $target differs from the package ($($f.path)); move it aside first." } }
  Step "staged copy already present and identical: $target"
} elseif (-not $DryRun) {
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
Step "current: $($current.Substring(0,9)); new: $ver"
if ($DryRun) { Step 'dry run: nothing changed'; return }
if ($current -eq $commit) { Step 'already active'; return }

$switched=$false
$stepName='save profile'
try {
  Save-Profile
  $stepName='stop station'; Step $stepName
  Stop-Station
  $stepName='switch active.json'; Step $stepName
  Write-Active $commit $current; $switched=$true
  $stepName='start new version'; Step $stepName
  $r=Start-Ready $commit
  if ((Firewall-Scope) -ne $ExpectedScope) { throw 'Firewall scope changed.' }
  Step "done: $ver running, PID $($r.process_id); previous $($current.Substring(0,9)) kept for -Rollback"
} catch {
  Step "FAILED at step '$stepName': $($_.Exception.Message)"
  if ($switched) { Switch-Back $commit $current $true }
  else {
    try { if (@(Station-Processes).Count -eq 0) { $r=Start-Ready $current; Step "restarted unchanged $($current.Substring(0,9)), PID $($r.process_id)" } }
    catch { Step "STATION DOWN: restart of $($current.Substring(0,9)) failed: $($_.Exception.Message)"; throw }
  }
  exit 1
}
