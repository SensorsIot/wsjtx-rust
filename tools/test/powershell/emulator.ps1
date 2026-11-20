# Starts and stops the IC-7300 emulator (the IC-7300 simulator project, simulator.py) on COM5 at
# 115200 baud for a simulator live test (harness/project/docs/Project-Specifics.md, Simulator live
# tests). It needs no administrator rights. Exactly one of:
#   emulator.ps1 -Start     refuses when a process already runs the emulator on COM5 (simulator.py
#                           --serial COM5 in its command line) or the record names a live process;
#                           else starts it, writes the record and waits until a new run folder of
#                           the emulator (artifacts\<run>\events.jsonl) starts the serial transport
#                           on COM5
#   emulator.ps1 -Stop      ends the recorded process and its descendants, only while the recorded
#                           pid still runs the recorded command since the recorded creation time;
#                           never another process
#   emulator.ps1 -Status    whether the recorded emulator runs, and any other emulator on COM5
#   -DryRun (with -Start or -Stop) prints every step and changes nothing (it still reads the processes).
# -Emulator is the emulator's project folder (its .venv\Scripts\python.exe and simulator.py).
# The record (pid, creation time, command, run) is <git common dir>/harness-parallel/radio/
# emulator.json, beside the radio lease (lease.json), so every worktree of the repository sees it.
# Exit 0: EMULATOR STARTED <pid>, STOPPED <pid>, NONE (nothing recorded to stop), RUNNING or
# NOT-RUNNING (-Status), DRY-RUN. Exit 2: EMULATOR ERROR, refused or failed; a start that fails
# ends what it started and removes the record.
[CmdletBinding(PositionalBinding = $false)]
param([switch]$Start, [switch]$Stop, [switch]$Status, [switch]$DryRun,
      [string]$Emulator = 'D:\Github\IC-7300 simulator', [string]$StateDir, [int]$ReadySeconds = 30,
      [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

function Finish($code, $word, $why) { Write-Output "EMULATOR $word $why"; exit $code }
function Say($text) { Write-Output "  $text" }
function Now { [DateTime]::UtcNow }
$Port = 'COM5'; $Baud = 115200
$OnPort = "(?i)simulator\.py[`"']?\s+(.*\s)?--serial[\s=]+[`"']?$Port(?!\d)"

# Every process whose command line runs the emulator on COM5.
function Emulator-Procs {
  @(Get-CimInstance -ClassName Win32_Process -Filter "CommandLine like '%simulator.py%'" | Where-Object { $_.CommandLine -match $OnPort })
}
function Proc([int]$id) { Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$id" }
function Stamp($time) { if ($time -is [DateTime]) { $time.ToUniversalTime().ToString('o') } else { [string]$time } }
# The process $id while it is the one created at $created: a reused pid is never taken for it.
function Same([int]$id, $created) { $p = Proc $id; if ($p -and (Stamp $p.CreationDate) -eq (Stamp $created)) { $p } }
# The recorded process while it still runs the recorded command.
function Live($record) {
  if (-not $record) { return $null }
  $p = Same $record.pid $record.created
  if ($p -and $p.CommandLine -eq $record.command) { $p }
}
# The process and its descendants (the venv's python.exe is a launcher that runs the interpreter
# as its child); a child created before its parent is an orphan of a reused pid, not ours.
function Tree($p) {
  @($p) + @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId=$($p.ProcessId)" |
            Where-Object { $_.CreationDate -ge $p.CreationDate } | ForEach-Object { Tree $_ })
}
function Record-Path { Join-Path $StateDir 'emulator.json' }
function Read-Record {
  $path = Record-Path
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  [IO.File]::ReadAllText($path) | ConvertFrom-Json
}
function Write-Record($record) { [IO.File]::WriteAllText((Record-Path), ($record | ConvertTo-Json -Compress)) }
# One -Start or -Stop at a time, also across worktrees; the lock ends with the process.
function Take-Lock {
  [void][IO.Directory]::CreateDirectory($StateDir)
  try { $script:Lock = [IO.File]::Open((Join-Path $StateDir 'emulator.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
  catch [IO.IOException] { Finish 2 'ERROR' 'another emulator.ps1 -Start or -Stop is running: nothing done' }
}
function Others($ours) {
  $mine = @($ours | ForEach-Object { $_.ProcessId })
  foreach ($p in Emulator-Procs) { if ($p.ProcessId -notin $mine) { Say "another process runs the emulator on $Port, not touched: $($p.ProcessId) $($p.CommandLine)" } }
}
# Ends exactly the tree of the process $p and waits until none of it is left.
function End-Tree($p) {
  $tree = @(Tree $p)
  Say "ending processes $(($tree | ForEach-Object { $_.ProcessId }) -join ', ')"
  $kill = @('/F') + @($tree | ForEach-Object { '/PID'; [string]$_.ProcessId })
  $out = taskkill @kill
  $code = $LASTEXITCODE
  $deadline = (Now).AddSeconds(5)
  for (;;) {
    $left = @($tree | Where-Object { Same $_.ProcessId $_.CreationDate })
    if (-not $left) { return }
    if ((Now) -ge $deadline) { throw "processes $(($left | ForEach-Object { $_.ProcessId }) -join ', ') still run after taskkill (exit $code`: $out)" }
    Start-Sleep -Milliseconds 200
  }
}
# The run folder the started emulator made: a folder of artifacts\ that was not there before,
# whose events.jsonl starts the serial transport on COM5; $null while there is none yet.
function Ready-Run($artifacts, $before) {
  if (-not (Test-Path -LiteralPath $artifacts -PathType Container)) { return $null }
  foreach ($dir in @(Get-ChildItem -LiteralPath $artifacts -Directory | Where-Object { $_.Name -notin $before })) {
    $events = Join-Path $dir.FullName 'events.jsonl'
    if (-not (Test-Path -LiteralPath $events -PathType Leaf)) { continue }
    foreach ($line in [IO.File]::ReadAllLines($events)) {
      try { $e = $line | ConvertFrom-Json } catch { continue }   # a line still being written
      if (-not $e -or -not $e.PSObject.Properties['kind']) { continue }
      if ($e.kind -eq 'transport_error') { throw "the emulator could not open $Port`: $($e.error)" }
      if ($e.kind -eq 'transport_start' -and $e.transport.endpoint -eq $Port) { return $dir.Name }
    }
  }
  $null
}

try {
  $given = @($PSBoundParameters.Keys | Where-Object { $_ -ne 'Rest' } | ForEach-Object { "-$_" }) + @($Rest | Where-Object { $_ })
  $modes = @(@('Start', 'Stop', 'Status') | Where-Object { $PSBoundParameters.ContainsKey($_) })
  $unknown = @($PSBoundParameters.Keys | Where-Object { $_ -notin @('Start', 'Stop', 'Status', 'DryRun', 'Emulator', 'StateDir', 'ReadySeconds', 'Rest') }) + @($Rest | Where-Object { $_ })
  if ($unknown -or $modes.Count -ne 1 -or -not $PSBoundParameters[$modes[0]] -or ($DryRun -and $Status)) {
    Finish 2 'ERROR' "need exactly one of -Start, -Stop, -Status (-DryRun only with -Start or -Stop), not '$($given -join ' ')'"
  }
  if (-not $StateDir) { $StateDir = Join-Path (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\radio' }
  if ($DryRun) { Write-Output "DRY RUN: nothing is changed (record $(Record-Path))" }
  $record = Read-Record
  $live = Live $record

  if ($Status) {
    Say "record $(Record-Path)"
    Others @(if ($live) { Tree $live })
    if ($live) { Finish 0 'RUNNING' "$($record.pid) since $($record.created), run $($record.run): $($record.command)" }
    if ($record) { Finish 0 'NOT-RUNNING' "the record names process $($record.pid), which is gone or runs another program now" }
    Finish 0 'NOT-RUNNING' "no record at $(Record-Path)"
  }

  if ($Stop) {
    if (-not $DryRun) { Take-Lock; $record = Read-Record; $live = Live $record }
    if (-not $record) { Others @(); Finish 0 'NONE' "no record at $(Record-Path): nothing stopped" }
    if (-not $live) {
      Others @()
      if ($DryRun) { Write-Output "would: remove the record of process $($record.pid), which is gone or runs another program now"; Finish 0 'DRY-RUN' '-Stop: every step above was printed, nothing was changed' }
      Remove-Item -LiteralPath (Record-Path)
      Finish 0 'NONE' "the recorded process $($record.pid) is gone or runs another program now: nothing stopped, the record is removed"
    }
    Others @(Tree $live)
    if ($DryRun) {
      Write-Output "would: end process $($record.pid) and its descendants (taskkill /F) and wait until none of them runs"
      Write-Output "would: remove the record $(Record-Path)"
      Finish 0 'DRY-RUN' '-Stop: every step above was printed, nothing was changed'
    }
    End-Tree $live
    Remove-Item -LiteralPath (Record-Path)
    Finish 0 'STOPPED' $record.pid
  }

  # -Start
  $python = Join-Path $Emulator '.venv\Scripts\python.exe'
  $simulator = Join-Path $Emulator 'simulator.py'
  foreach ($file in @($python, $simulator)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Finish 2 'ERROR' "no $file`: nothing started" } }
  $command = "`"$python`" `"$simulator`" --serial $Port --baud $Baud"
  if (-not $DryRun) { Take-Lock; $record = Read-Record; $live = Live $record }
  if ($live) { Finish 2 'ERROR' "the recorded emulator still runs (process $($record.pid) since $($record.created)): nothing started; stop it with -Stop" }
  $running = @(Emulator-Procs)
  if ($running) { Finish 2 'ERROR' "a process already runs the emulator on $Port ($(($running | ForEach-Object { "$($_.ProcessId) $($_.CommandLine)" }) -join '; ')): nothing started" }
  if ($record) { Say "the record of process $($record.pid) names no live emulator and is replaced" }
  if ($DryRun) {
    Write-Output "would: start $command in $Emulator, hidden, its own console as stdin"
    Write-Output "would: write the record $(Record-Path) (pid, creation time, command)"
    Write-Output "would: wait up to $ReadySeconds s until a new run folder under $Emulator\artifacts starts the serial transport on $Port"
    Finish 0 'DRY-RUN' '-Start: every step above was printed, nothing was changed'
  }
  $artifacts = Join-Path $Emulator 'artifacts'
  $before = @(if (Test-Path -LiteralPath $artifacts -PathType Container) { Get-ChildItem -LiteralPath $artifacts -Directory | ForEach-Object { $_.Name } })
  # Win32_Process.Create: the WMI service creates the process, so it belongs to neither the
  # caller's console nor its job and outlives the agent's shell and tool call. A console program
  # started so gets its own console (hidden here); that console's input is its stdin, which never
  # reaches end of file, so the MCP stdio server keeps running until its tree is ended.
  $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
  Say "starting $command"
  $made = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $command; CurrentDirectory = $Emulator; ProcessStartupInformation = $startup }
  if ($made.ReturnValue -ne 0) { Finish 2 'ERROR' "Win32_Process.Create returned $($made.ReturnValue): nothing started" }
  $id = [int]$made.ProcessId
  $p = Proc $id
  if (-not $p -or $p.CommandLine -ne $command) { Finish 2 'ERROR' "process $id exited at once" }
  $record = [pscustomobject][ordered]@{ pid = $id; created = (Stamp $p.CreationDate); command = $command; run = $null }
  Write-Record $record
  $why = $null
  try {
    $deadline = (Now).AddSeconds($ReadySeconds)
    for (;;) {
      $run = Ready-Run $artifacts $before
      if ($run) { break }
      if (-not (Live $record)) { throw "process $id exited before it started the transport on $Port" }
      if ((Now) -ge $deadline) { throw "no new run folder started the transport on $Port within $ReadySeconds s" }
      Start-Sleep -Milliseconds 250
    }
  } catch { $why = $_.Exception.Message }
  if ($why) {
    $left = Live $record
    if ($left) { End-Tree $left }
    Remove-Item -LiteralPath (Record-Path)
    Finish 2 'ERROR' "$why; what was started is ended and the record removed"
  }
  $record.run = $run
  Write-Record $record
  Finish 0 'STARTED' "$id on $Port at $Baud baud, run $run"
} catch {
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $($_.Exception.Message)"
}
