# The station's process list, its Ctrl+C helper and the settling of its scheduled task, in one
# place for station-update.ps1, live-page-check.ps1 and the test bench (station-control.ps1).
# Dot-source it. The functions read these variables of the caller and no other:
#   $Station      the station folder
#   $TaskName     its scheduled task
#   $CtrlErrFile  the file the Ctrl+C helper writes the Windows error of a failed call to
# Functions: Station-Procs, Send-CtrlC, Settle-Task. They read the time only through the
# caller's Now and wait only through Start-Sleep.

# The station's processes: wstx-rust.exe started from below $Station\ (case-insensitive).
function Station-Procs {
  @(Get-CimInstance Win32_Process -Filter "Name='wstx-rust.exe'" | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith("$Station\", [StringComparison]::OrdinalIgnoreCase) })
}
function Send-CtrlC([int]$TargetPid, [int]$CtrlEvent = 0) {
  # A separate process attaches to the station's console and raises Ctrl+C (event 0) or
  # Ctrl+Break (event 1) there; GenerateConsoleCtrlEvent reaches the attached console's whole
  # group. Exit 3: AttachConsole failed; exit 4: GenerateConsoleCtrlEvent failed; the helper
  # then writes the Windows error (GetLastError) of that call to $CtrlErrFile.
  # Returns @{ Rc; Delivered; Error }.
  $errFile = $CtrlErrFile
  if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force }
  $errQ = $errFile -replace "'", "''"
  $code = @"
Add-Type -Namespace W -Name C -MemberDefinition '[DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll", SetLastError=true)] static extern bool AttachConsole(uint p); [DllImport("kernel32.dll")] public static extern bool SetConsoleCtrlHandler(System.IntPtr h, bool a); [DllImport("kernel32.dll", SetLastError=true)] static extern bool GenerateConsoleCtrlEvent(uint e, uint g); public static int Attach(uint p) { return AttachConsole(p) ? -1 : System.Runtime.InteropServices.Marshal.GetLastWin32Error(); } public static int Raise(uint e) { return GenerateConsoleCtrlEvent(e, 0) ? -1 : System.Runtime.InteropServices.Marshal.GetLastWin32Error(); }'
`$f='$errQ'
[W.C]::FreeConsole() | Out-Null
`$e=[W.C]::Attach($TargetPid)
if (`$e -ge 0) { [IO.File]::WriteAllText(`$f, [string]`$e); exit 3 }
[W.C]::SetConsoleCtrlHandler([IntPtr]::Zero, `$true) | Out-Null
`$e=[W.C]::Raise($CtrlEvent)
if (`$e -ge 0) { [IO.File]::WriteAllText(`$f, [string]`$e); exit 4 }
Start-Sleep -Milliseconds 500
exit 0
"@
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
  $p = Start-Process -FilePath powershell.exe -ArgumentList @('-NoProfile', '-NonInteractive', '-EncodedCommand', $enc) -WindowStyle Hidden -PassThru -Wait
  $rc = [int]$p.ExitCode
  $n = $null
  if (Test-Path -LiteralPath $errFile) {
    $t = ([IO.File]::ReadAllText($errFile)).Trim()
    if ($t -match '^[0-9]+$') { $n = $t }
    Remove-Item -LiteralPath $errFile -Force
  }
  $call = $null; if ($rc -eq 3) { $call = 'AttachConsole' } elseif ($rc -eq 4) { $call = 'GenerateConsoleCtrlEvent' }
  $err = ''
  if ($rc -ne 0) { $err = $(if ($call) { "$call error " } else { 'error ' }) + $(if ($call -and $n) { $n } else { 'unknown' }) }
  return [pscustomobject]@{ Rc = $rc; Delivered = ($rc -eq 0); Error = $err }
}
# The task's launcher outlives the process for a moment; the next start must not race it. A
# failed Stop-ScheduledTask is a note on the output, and the wait follows; it refuses nothing.
function Settle-Task {
  try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction Stop } catch { Write-Output "note: Stop-ScheduledTask: $($_.Exception.Message)" }
  $deadline = (Now).AddSeconds(10)
  while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running' -and (Now) -lt $deadline) { Start-Sleep -Milliseconds 200 }
  Start-Sleep -Milliseconds 800
}
