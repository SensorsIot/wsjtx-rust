# Starts and stops the candidate bench of one issue for the function test of a live test on the
# simulator (harness/project/docs/specifics/deployment-authority.md, Candidate bench): the
# candidate's own build from the issue's worktree, on a free 127.0.0.1 port, with a scratch copy of
# the simulator profile SIM-IC7300 and its own station data, never the installed station. The bench
# owns the IC-7300 emulator (emulator.ps1, COM5; the candidate's CAT is COM4) for its life. Exactly one of:
#   candidate-bench.ps1 -Start -Issue <n>   one -Start at a time (a lock under -Live) and one bench at a
#                           time (COM4 and the audio cables have one user); refuses while the installed
#                           station runs the simulator profile, when the issue has no worktree of its
#                           own, or when the simulator profile names another CAT port than COM4 or COM3
#                           anywhere. Then: builds the worktree (cargo build --release --locked, into
#                           <BuildRoot>\issue-<n>-bench); copies the profile to <Live>\<n>\bench\profile
#                           with the bind 127.0.0.1:<port>, PSK Reporter off, no UDP target and no radio
#                           discovery at start; starts bench-hold.ps1, which holds in the candidate's own
#                           station data the ownership lock of every COM port Windows knows, present or
#                           not, but COM4, and locks each new one within a second (the server takes that
#                           lock before radio detection's probe and the CAT open, so the candidate finds
#                           COM3 and every other port in use and never opens it); starts the emulator;
#                           starts the build hidden
#                           with LOCALAPPDATA <Live>\<n>\bench\appdata; waits for its listening line.
#   candidate-bench.ps1 -Stop -Issue <n>    ends the recorded candidate (only while the recorded pid runs
#                           the bench's build since the recorded creation time), the emulator and the holder
#   candidate-bench.ps1 -Status -Issue <n>  whether the recorded bench runs, with its URL
# The record is <Live>\<n>\bench\bench.json. The page of a running bench is read with
# tools/test/node/bench-page.cjs (a headless browser on its 127.0.0.1 address only).
# Exit 0: BENCH STARTED <url> <commit>, STOPPED <pid>, NONE (nothing recorded to stop), RUNNING <url>
# or NOT-RUNNING. Exit 2: BENCH ERROR, refused or failed; a start that fails ends what it started.
[CmdletBinding(PositionalBinding = $false)]
param([switch]$Start, [switch]$Stop, [switch]$Status, [int]$Issue,
      [string]$Repo = 'D:\Github\wsjtx-rust', [string]$Live = 'D:\wstx-tmp\live', [string]$BuildRoot = 'D:\wstx-build',
      [string]$Station = (Join-Path $env:LOCALAPPDATA 'WstxRust\station'), [int]$ReadySeconds = 60,
      [string]$EmulatorScript = (Join-Path $PSScriptRoot 'emulator.ps1'), [string]$HoldScript = (Join-Path $PSScriptRoot 'bench-hold.ps1'),
      [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

function Finish($code, $word, $why) { Write-Output "BENCH $word $why"; exit $code }
function Say($text) { Write-Output "  $text" }
function Stamp($time) { if ($time -is [DateTime]) { $time.ToUniversalTime().ToString('o') } else { [string]$time } }
function Proc([int]$id) { Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$id" }
function Field($o, $name) { if ($o -and $o.PSObject.Properties[$name]) { $o.$name } }
function Bench-Dir([int]$n) { Join-Path (Join-Path $Live ([string]$n)) 'bench' }
function Record-Path([int]$n) { Join-Path (Bench-Dir $n) 'bench.json' }
function Bench-Exe([int]$n) { Join-Path $BuildRoot "issue-$n-bench\release\wstx-rust.exe" }
function Read-Record([int]$n) {
  $path = Record-Path $n
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try { [IO.File]::ReadAllText($path) | ConvertFrom-Json } catch { $null }
}
function Write-Json($path, $value) {
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
  [IO.File]::WriteAllText($path, ($value | ConvertTo-Json -Depth 20), [Text.UTF8Encoding]::new($false))
}
# The record's candidate while it is the bench's own build of issue $n, created at the recorded
# time: the record lies in the tester's run folder, so its pid alone is never trusted.
function Candidate($record, [int]$n) {
  $id = Field $record 'pid'
  if (-not $id) { return $null }
  $p = Proc $id
  if ($p -and (Stamp $p.CreationDate) -eq (Stamp (Field $record 'created')) -and
      [string](Field $p 'ExecutablePath') -eq (Bench-Exe $n)) { $p }
}
# The record's holder while it runs bench-hold.ps1 since the recorded time.
function Holder($record) {
  $id = Field $record 'holder'
  if (-not $id) { return $null }
  $p = Proc $id
  if ($p -and (Stamp $p.CreationDate) -eq (Stamp (Field $record 'holder_created')) -and
      [string](Field $p 'CommandLine') -like '*bench-hold.ps1*') { $p }
}
function End-Pid([int]$id) {
  $out = taskkill /F /T /PID ([string]$id)
  if ($LASTEXITCODE -ne 0) { throw "taskkill of $id failed (exit $LASTEXITCODE): $out" }
}
# Ends what a bench started: the candidate, the emulator (as the bench's), the holder, the record.
function Tear-Down($record, [int]$n) {
  $c = Candidate $record $n
  if ($c) { End-Pid $c.ProcessId; if (Candidate $record $n) { throw "the candidate $($c.ProcessId) still runs after taskkill" } }
  if (Field $record 'emulator') { $o = & $EmulatorScript -Stop -Bench; if ($LASTEXITCODE -ne 0) { throw "emulator.ps1 -Stop -Bench: $o" } }
  $h = Holder $record
  Remove-Item -LiteralPath (Record-Path $n) -Force -ErrorAction SilentlyContinue
  if ($h) { End-Pid $h.ProcessId }
}

try {
  if ($Rest) { Finish 2 'ERROR' "unknown arguments: $($Rest -join ' ')" }
  if (@(@($Start, $Stop, $Status) | Where-Object { $_ }).Count -ne 1) { Finish 2 'ERROR' 'exactly one of -Start, -Stop or -Status' }
  if ($Issue -le 0) { Finish 2 'ERROR' "-Issue must be an issue number, not $Issue" }

  if ($Status) {
    $record = Read-Record $Issue
    if (Candidate $record $Issue) { Finish 0 'RUNNING' "$($record.url) $($record.commit) (pid $($record.pid))" }
    Finish 0 'NOT-RUNNING' "#$Issue"
  }
  if ($Stop) {
    $record = Read-Record $Issue
    if (-not $record) { Finish 0 'NONE' "no bench of #$Issue is recorded" }
    Tear-Down $record $Issue
    Finish 0 'STOPPED' "$(Field $record 'pid')"
  }

  # -Start: one at a time, also across testers (the lock ends with this process).
  [void][IO.Directory]::CreateDirectory($Live)
  try { $script:Lock = [IO.File]::Open((Join-Path $Live 'candidate-bench.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
  catch [IO.IOException] { Finish 2 'ERROR' 'another candidate-bench.ps1 -Start is running: nothing done' }
  # One bench at a time: the emulator's COM4 and the band simulator's audio cables have one user.
  # A record of a start that did not finish (no candidate yet) is stale: no -Start runs beside this one.
  foreach ($dir in Get-ChildItem -LiteralPath $Live -Directory) {
    $n = 0
    if (-not [int]::TryParse($dir.Name, [ref]$n)) { continue }
    $other = Read-Record $n
    if (Candidate $other $n) { Finish 2 'ERROR' "the bench of #$n runs (pid $($other.pid), $($other.url)): stop it first, nothing done" }
    if ($other) { Say "the record of #$n names no running bench and is ended"; Tear-Down $other $n }
  }
  # The installed station on the simulator profile holds COM4 and the cables itself.
  $running = Join-Path $Station 'station-running.json'
  if (Test-Path -LiteralPath $running -PathType Leaf) {
    $installed = [IO.File]::ReadAllText($running) | ConvertFrom-Json
    if ([string](Field $installed 'profile') -match '(?i)[\\/]SIM-IC7300[\\/]?$') {
      Finish 2 'ERROR' 'the installed station runs the simulator profile SIM-IC7300: switch it back first (station-switch.ps1 -To back), nothing done'
    }
  }
  # The issue's worktree of its current generation, from the workspace records.
  $state = Join-Path $Repo '.git\harness-parallel\state.json'
  $row = $null
  if (Test-Path -LiteralPath $state -PathType Leaf) {
    $issues = Field ([IO.File]::ReadAllText($state) | ConvertFrom-Json) 'issues'
    if ($issues -and ($issues.PSObject.Properties.Name -contains [string]$Issue)) { $row = $issues.([string]$Issue) }
  }
  if (-not $row) { Finish 2 'ERROR' "#$Issue has no workspace record in $state, nothing done" }
  $worktree = [string](Field $row 'path')
  $worktrees = [IO.Path]::GetFullPath((Join-Path $Repo '.git\harness-parallel\worktrees'))
  if (-not $worktree -or -not ([IO.Path]::GetFullPath($worktree)).StartsWith($worktrees + '\', [StringComparison]::OrdinalIgnoreCase) -or
      (Split-Path -Leaf $worktree) -notmatch "^issue-$Issue(-g\d+)?$" -or -not (Test-Path -LiteralPath $worktree -PathType Container)) {
    Finish 2 'ERROR' "#$Issue's worktree $worktree is not its own issue worktree under $worktrees, nothing done"
  }
  # The simulator profile: CAT on COM4 only, never the real radio's COM3.
  $source = Join-Path $Station 'profiles\SIM-IC7300'
  if (-not (Test-Path -LiteralPath (Join-Path $source 'profile.json') -PathType Leaf)) { Finish 2 'ERROR' "no simulator profile at $source, nothing done" }
  foreach ($file in Get-ChildItem -LiteralPath $source -File -Filter '*.json') {
    if ([IO.File]::ReadAllText($file.FullName) -match '(?i)\bCOM3\b') { Finish 2 'ERROR' "$($file.Name) of the simulator profile names COM3, the real radio: nothing done" }
  }
  $profileDoc = [IO.File]::ReadAllText((Join-Path $source 'profile.json')) | ConvertFrom-Json
  $cat = [string](Field (Field $profileDoc 'control') 'endpoint')
  if ($cat -notmatch '(?i)^icom7300://COM4\?') { Finish 2 'ERROR' "the simulator profile's CAT endpoint is '$cat', not COM4: nothing done" }

  $commit = [string](git -C $worktree rev-parse HEAD)
  if ($LASTEXITCODE -ne 0 -or $commit.Trim() -notmatch '^[0-9a-f]{40}$') { Finish 2 'ERROR' "the worktree's HEAD cannot be read, nothing done" }
  $commit = $commit.Trim()
  $bench = Bench-Dir $Issue
  $record = [ordered]@{issue = $Issue; state = 'starting'; commit = $commit; worktree = $worktree}
  Write-Json (Record-Path $Issue) $record
  Say "candidate $commit of #$Issue in $worktree"
  # The build: the worktree's own, in a folder of its own.
  $target = Join-Path $BuildRoot "issue-$Issue-bench"
  $env:CARGO_TARGET_DIR = $target
  $built = cargo build --release --locked --manifest-path (Join-Path $worktree 'Cargo.toml') 2>&1
  if ($LASTEXITCODE -ne 0) { throw "cargo build failed: $(@($built)[-1])" }
  $exe = Bench-Exe $Issue
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "the build left no $exe" }

  # A free port on 127.0.0.1, released for the candidate to bind (a port taken meanwhile ends the
  # start with the candidate's own error).
  $held = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $held.Start()
  $port = ([Net.IPEndPoint]$held.LocalEndpoint).Port; $held.Stop()
  $url = "http://127.0.0.1:$port"
  foreach ($sub in 'profile', 'appdata') {
    $dir = Join-Path $bench $sub
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    [void][IO.Directory]::CreateDirectory($dir)
  }
  $scratch = Join-Path $bench 'profile'; $appdata = Join-Path $bench 'appdata'
  foreach ($file in Get-ChildItem -LiteralPath $source -File) { Copy-Item -LiteralPath $file.FullName -Destination $scratch }
  $id = [string]$profileDoc.profile_id
  $profileDoc.endpoint = [pscustomobject]@{bind = "127.0.0.1:$port"; origin = $url}
  Write-Json (Join-Path $scratch 'profile.json') $profileDoc
  Write-Json (Join-Path $scratch 'pskr.json') ([ordered]@{schema_version = 2; profile_id = $id; enabled = $false; use = $true})
  Write-Json (Join-Path $scratch 'udp.json') ([ordered]@{schema_version = 1; profile_id = $id; revision = 0; targets = @()})
  Write-Json (Join-Path $scratch 'radio-discovery.json') ([ordered]@{schema_version = 1; profile_id = $id; at_start = $false})

  # Every COM port Windows knows but the simulator's COM4: its ownership lock is held in the
  # candidate's station data for the bench's life, new ones within a second (bench-hold.ps1).
  Remove-Item -LiteralPath "$(Record-Path $Issue).holding" -Force -ErrorAction SilentlyContinue
  $hold = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $HoldScript + '"'), '-Record', ('"' + (Record-Path $Issue) + '"'),
    '-LockRoot', ('"' + $appdata + '"'), '-KeepPort', '4')
  $hp = Proc $hold.Id
  if (-not $hp) { throw 'the radio lock holder exited at once' }
  $record.holder = $hold.Id; $record.holder_created = Stamp $hp.CreationDate
  Write-Json (Record-Path $Issue) $record
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  while (-not (Test-Path -LiteralPath "$(Record-Path $Issue).holding" -PathType Leaf)) {
    if (-not (Holder ([pscustomobject]$record)) -or [DateTime]::UtcNow -ge $deadline) { throw 'the radio lock holder did not hold the locks' }
    Start-Sleep -Milliseconds 200
  }
  Say 'the ownership lock of every COM port but COM4 is held for the candidate'
  $emu = & $EmulatorScript -Start
  if ($LASTEXITCODE -ne 0) { throw "emulator.ps1 -Start: $emu" }
  $record.emulator = $true
  Write-Json (Record-Path $Issue) $record

  # The candidate's environment: no inherited WSTX_ setting, its own station data, no public time server.
  foreach ($name in @(Get-ChildItem Env: | Where-Object { $_.Name -like 'WSTX_*' } | ForEach-Object { $_.Name })) { Remove-Item "Env:$name" }
  $env:LOCALAPPDATA = $appdata
  $env:WSTX_SNTP_SERVERS = ''
  $out = Join-Path $bench 'candidate.stdout.log'; $err = Join-Path $bench 'candidate.stderr.log'
  $child = Start-Process -FilePath $exe -ArgumentList @('--profile', ('"' + $scratch + '"')) -WindowStyle Hidden -PassThru `
                         -RedirectStandardOutput $out -RedirectStandardError $err
  $record.pid = $child.Id
  $p = Proc $child.Id
  if (-not $p) { Write-Json (Record-Path $Issue) $record; throw 'the candidate exited at once' }
  $record.created = Stamp $p.CreationDate; $record.url = $url; $record.exe = $exe; $record.profile = $scratch; $record.state = 'running'
  Write-Json (Record-Path $Issue) $record
  $deadline = [DateTime]::UtcNow.AddSeconds($ReadySeconds)
  for (;;) {
    $text = if (Test-Path -LiteralPath $out) { [IO.File]::ReadAllText($out) } else { '' }
    if ($text -match [regex]::Escape("WSTX listening $url")) { Finish 0 'STARTED' "$url $commit (pid $($child.Id))" }
    if (-not (Candidate ([pscustomobject]$record) $Issue)) { throw "the candidate exited (see $err)" }
    if ([DateTime]::UtcNow -ge $deadline) { throw "the candidate did not listen on $url within $ReadySeconds s (see $err)" }
    Start-Sleep -Milliseconds 500
  }
} catch {
  $why = $_.Exception.Message
  if ($Start -and $Issue -gt 0) {
    # A start that fails ends what it started: the candidate this run started by its own pid (the
    # record may not name it yet), while that process runs the bench's build.
    if ((Get-Variable -Name child -ValueOnly -ErrorAction SilentlyContinue) -and $child.Id) {
      $cp = Proc $child.Id
      # A candidate already gone needs no taskkill (whose error output would end this catch block).
      if ($cp -and [string](Field $cp 'ExecutablePath') -eq (Bench-Exe $Issue)) {
        try { End-Pid $child.Id } catch { $why += "; ending the candidate: $($_.Exception.Message)" }
      }
    }
    $partial = Read-Record $Issue
    try { if ($partial) { Tear-Down $partial $Issue } } catch { $why += "; ending it: $($_.Exception.Message)" }
    Finish 2 'ERROR' "the bench did not start: $why"
  }
  Finish 2 'ERROR' "$($_.Exception.GetType().Name): $why"
}
