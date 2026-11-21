# The station's process, its graceful stop (Ctrl+C), its scheduled task and whether it is in use,
# for the scripts beside this one (radio-preflight.ps1, station-switch.ps1). Dot-source it; the caller
# sets $Station (the station folder), $TaskName (its scheduled task) and $AgentClient (the station
# client, for Station-InUse); it sets $CtrlErrFile for the shared station-process.ps1, which it
# dot-sources. Stop-Station and Start-Station set $script:CtrlCExit and
# $script:StillRuns, which the caller initialises.
function Now { [DateTime]::UtcNow }
# Station-Procs, Send-CtrlC and Settle-Task: the repository's tools/deploy/station-process.ps1,
# three folders above this one. Its Ctrl+C helper writes its error file to the user's temp folder.
. (Join-Path $PSScriptRoot '..\..\..\tools\deploy\station-process.ps1')
$CtrlErrFile = Join-Path ([IO.Path]::GetTempPath()) "wstx-station-ctrl-$([guid]::NewGuid().ToString('N')).txt"
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
  $rc = (Send-CtrlC ([int]$process.ProcessId)).Rc
  $script:CtrlCExit = $rc
  $deadline = (Now).AddSeconds(12)
  while (@(Station-Procs).Count -gt 0 -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  if (@(Station-Procs).Count -gt 0) { throw "the station did not stop on Ctrl+C (helper exit $rc)" }
  Settle-Task
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
