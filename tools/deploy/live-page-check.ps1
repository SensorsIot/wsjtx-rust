# Harness retrospective item 3 (SensorsIot/harness#38): runs tests/live-page-check.cjs against the
# station installed on this PC, and gives it the one real restart it asks for, after it has
# watched the page for several periods. Receive only: it keys nothing and sets nothing on the radio.
#   live-page-check.ps1 -Repo <repository root> -Shared <git common dir>\harness-parallel
#                       -AgentClient <agent-client.ps1> [-WaitSeconds 300] [-Station <folder>]
# It derives no path from its own location, so it runs from a station package as well: the check
# is <Repo>\tests\live-page-check.cjs (with the repository's node_modules), the radio lease is
# <Shared>\radio\lease.json.
# The restart happens only while /transmit is disarmed, not transmitting and PTT released, /contact
# has no running contact, /automation has no active run, no update runs and nobody holds the radio
# lease; otherwise it waits up to -WaitSeconds and gives up with the station untouched.
# Stop and start as in radio-preflight.ps1: Ctrl+C, then the scheduled task.
# While it restarts it holds the station's update.lock, so station-update.ps1 and radio-preflight.ps1
# refuse to start in that window.
# Exit 0: PASS. 1: RED. 2: ERROR, it could not run or the station did not come back (it says which).
# 3: BUSY, the station was in use and was not restarted. 4: NOT-EXERCISED, nothing was shown wrong
# but a live trigger of #22 or #50 was not on screen (the PAGE CHECK line says which).
param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Shared, [Parameter(Mandatory)][string]$AgentClient,
      [int]$WaitSeconds = 300, [string]$Station, [string]$Check = 'tests/live-page-check.cjs',
      [string]$TaskName = 'WSTX Rust Station HB9BLA')
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

function Now { [DateTime]::UtcNow }
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
# The task's launcher outlives the process for a moment; the next start must not race it.
function Settle-Task {
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { Write-Output "note: Stop-ScheduledTask: $($_.Exception.Message)" }
  $deadline = (Now).AddSeconds(10)
  while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 800
}
# Why the station cannot be restarted now, or $null. An unreadable state counts as in use.
# It takes the update lock and keeps it while the station is free ($script:Lock), so that no
# update or preflight starts between this check and the new boot.
function Station-InUse {
  try { $script:Lock = [IO.File]::Open((Join-Path $Station 'logs\update.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
  catch [IO.IOException] { return 'an update is running' }
  $why = Station-Busy
  if ($why) { $script:Lock.Dispose(); $script:Lock = $null }
  $why
}
function Station-Busy {
  $leaseFile = Join-Path $RadioDir 'lease.json'
  if (Test-Path -LiteralPath $leaseFile) {
    $lease = [IO.File]::ReadAllText($leaseFile) | ConvertFrom-Json
    if ([DateTime]::Parse($lease.expires, [Globalization.CultureInfo]::InvariantCulture, 'AdjustToUniversal,AssumeUniversal') -gt (Now)) { return "$($lease.holder) holds the radio lease until $($lease.expires)" }
  }
  $procs = @(Station-Procs)
  if ($procs.Count -ne 1) { return "$($procs.Count) station processes are running" }
  # One session for the whole wait: a login every 10 s runs into the station's login limit.
  $read = {
    if (-not $script:Session) { $script:Session = Open-AgentSession }
    @((Agent-Get $script:Session '/transmit'), (Agent-Get $script:Session '/contact').contact, (Agent-Get $script:Session '/automation').run)
  }
  try { $transmit, $contact, $run = & $read }
  catch {
    $script:Session = $null
    try { $transmit, $contact, $run = & $read } catch { return "its state cannot be read ($($_.Exception.GetType().Name))" }
  }
  if ([string]$transmit.transmit.arm_state -ne 'disarmed') { return "transmit is $($transmit.transmit.arm_state)" }
  if ([string]$transmit.ptt -ne 'released' -or $transmit.transmitting) { return "PTT is $($transmit.ptt), transmitting: $($transmit.transmitting)" }
  if ($contact -and [string]$contact.state -notin @('idle', 'completed', 'cancelled')) { return "a contact is $($contact.state)" }
  if ($run -and [string]$run.state -ne 'stopped') { return "an automation run is $($run.state)" }
  $null
}
function Restart-Station {
  $process = @(Station-Procs)[0]
  $rc = Send-CtrlC ([int]$process.ProcessId)
  $deadline = (Now).AddSeconds(32)
  while (@(Station-Procs).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -gt 0) { throw "THE STATION still runs, state unknown, check it: 32 s after Ctrl+C (helper exit $rc), not restarted" }
  Settle-Task
  Start-ScheduledTask -TaskName $TaskName
  $deadline = (Now).AddSeconds(40)
  while (@(Station-Procs).Count -eq 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -eq 0) { throw 'THE STATION IS DOWN: it did not come back within 40 s' }
}
function Session-Line($session) {
  $cookies = @($session.Session.Cookies.GetCookies($AgentUrl) | Where-Object { $_.Name -like 'wstx_session_*' } | ForEach-Object { @{ name = $_.Name; value = $_.Value } })
  @{ cookies = $cookies } | ConvertTo-Json -Compress -Depth 3
}

$node = $null; $control = $null; $script:Session = $null; $script:Lock = $null; $code = 2; $word = 'ERROR'; $why = 'the check did not finish'
try {
  # Only this script and the check: the station starts from its task, outside this priority.
  [Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  $Repo = [IO.Path]::GetFullPath($Repo)
  $RadioDir = Join-Path $Shared 'radio'
  if (-not [IO.Path]::IsPathRooted($Check)) { $Check = Join-Path $Repo $Check }
  . $AgentClient
  $control = Join-Path ([IO.Path]::GetTempPath()) "wstx-page-check-$([guid]::NewGuid().ToString('N'))"
  [void][IO.Directory]::CreateDirectory($control)

  $start = New-Object Diagnostics.ProcessStartInfo
  $start.FileName = (Get-Command node).Source
  $start.Arguments = '"' + $Check + '"'
  $start.WorkingDirectory = $Repo
  $start.UseShellExecute = $false
  $start.RedirectStandardInput = $true
  $start.EnvironmentVariables['WSTX_LIVE_PAGE_ORIGIN'] = $AgentUrl
  $start.EnvironmentVariables['WSTX_LIVE_PAGE_CONTROL'] = $control
  $start.EnvironmentVariables['WSTX_LIVE_PAGE_WAIT_SECONDS'] = [string]$WaitSeconds
  $node = [Diagnostics.Process]::Start($start)
  $node.StandardInput.WriteLine((Session-Line (Open-AgentSession))); $node.StandardInput.Flush()

  $restartDone = $false
  while (-not $node.HasExited) {
    if (-not $restartDone -and (Test-Path -LiteralPath (Join-Path $control 'restart'))) {
      $restartDone = $true
      $deadline = (Now).AddSeconds($WaitSeconds); $busy = Station-InUse
      while ($busy -and (Now) -lt $deadline -and -not $node.HasExited) { Write-Output "waiting: $busy"; Start-Sleep -Seconds 10; $busy = Station-InUse }
      if ($node.HasExited) { break }
      if ($busy) { $node.StandardInput.WriteLine((@{ abort = $busy } | ConvertTo-Json -Compress)); $node.StandardInput.Flush(); continue }
      $node.StandardInput.WriteLine('{"stopping":true}'); $node.StandardInput.Flush()
      Write-Output "restarting the station, $((Now).ToString('HH:mm:ss')) UTC"
      Restart-Station
      $deadline = (Now).AddSeconds(90); $session = $null
      while (-not $session) {
        try { $session = Open-AgentSession } catch { if ((Now) -ge $deadline) { throw "THE STATION does not answer 90 s after its start: $($_.Exception.Message)" }; Start-Sleep -Seconds 1 }
      }
      Write-Output "station back, $((Now).ToString('HH:mm:ss')) UTC"
      $script:Lock.Dispose(); $script:Lock = $null
      $node.StandardInput.WriteLine((Session-Line $session)); $node.StandardInput.Flush()
    }
    Start-Sleep -Milliseconds 200
  }
  $node.WaitForExit()
  $code = $node.ExitCode
  $word = @{ 0 = 'PASS'; 1 = 'RED'; 3 = 'BUSY'; 4 = 'NOT-EXERCISED' }[$code]; $why = 'see the PAGE CHECK line'
  if (-not $word) { $word = 'ERROR'; $code = 2; $why = "the check exited with $($node.ExitCode)" }
} catch {
  $why = "$($_.Exception.GetType().Name): $($_.Exception.Message)"
} finally {
  if ($node -and -not $node.HasExited) { $node.Kill() }
  if ($script:Lock) { $script:Lock.Dispose() }
  if ($control -and (Test-Path -LiteralPath $control)) { Remove-Item -LiteralPath $control -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "LIVE PAGE CHECK $word $why"
exit $code
