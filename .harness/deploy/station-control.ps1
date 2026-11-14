# The station's process, its graceful stop (Ctrl+C), its scheduled task and whether it is in use,
# for the scripts beside this one (radio-preflight.ps1, station-switch.ps1). Dot-source it; the caller
# sets $Station (the station folder), $TaskName (its scheduled task) and $AgentClient (the station
# client, for Station-InUse). Stop-Station and Start-Station set $script:CtrlCExit and
# $script:StillRuns, which the caller initialises.
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
