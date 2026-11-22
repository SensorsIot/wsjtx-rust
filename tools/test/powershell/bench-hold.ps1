# The radio locks of a candidate bench (candidate-bench.ps1 starts it hidden; nobody else runs it).
# For every device of the Windows Ports class (COM ports) that Windows knows, present or not, but the
# one named (COM<KeepPort>) (the simulator's CAT port), it holds in the candidate's own station data
# (-LockRoot, the LOCALAPPDATA the candidate runs with) the ownership lock the server takes before it
# opens a port, in radio detection's probe and in the CAT open (windows.rs claim_identity):
#   WstxRust\radio-ownership\<hex of the device instance id>\owner.lock
# opened shared and locked over its whole range, as the server's File::try_lock asks for, so the
# server's try_lock gets WouldBlock: the port is in use and never opened. It rescans the devices every
# -PollMilliseconds and locks each newly known device at once (a radio switched on, a new adapter).
# It writes <Record>.holding (the locked paths) once the first scan's locks are held, and ends,
# releasing them, when the record is gone or names a candidate process that has ended. A first
# scan that fails, finds no device or cannot lock one ends it before .holding (exit 2): it never
# reports ready with less locked than Windows knows. A later scan that fails, or a device that cannot
# be locked then, keeps every lock held and is tried again at the next poll.
#   bench-hold.ps1 -Record <bench.json> -LockRoot <candidate LOCALAPPDATA> [-KeepPort 4] [-Devices <file>]
# -Devices: a JSON file [{"name": "... (COM3)", "id": "<instance id>"}] read at every scan in place of
# Get-PnpDevice -Class Ports (the tests' device source).
param([Parameter(Mandatory)][string]$Record, [Parameter(Mandatory)][string]$LockRoot,
      [int]$KeepPort = 4, [string]$Devices, [int]$PollMilliseconds = 1000)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

# The server's folder name for an identity: its upper-case bytes in hex, 120 characters a folder.
function Identity-Path([string]$root, [string]$identity) {
  $hex = -join ([Text.Encoding]::ASCII.GetBytes($identity.ToUpperInvariant()) | ForEach-Object { $_.ToString('x2') })
  $path = $root
  for ($i = 0; $i -lt $hex.Length; $i += 120) { $path = Join-Path $path $hex.Substring($i, [Math]::Min(120, $hex.Length - $i)) }
  $path
}
function Field($o, $name) { if ($o -and $o.PSObject.Properties[$name]) { [string]$o.$name } else { '' } }
# Every Ports-class device Windows knows, present or not: (name, instance id); a failed query throws.
function Known-Devices {
  if ($Devices) {
    $list = [IO.File]::ReadAllText($Devices) | ConvertFrom-Json   # Windows PowerShell writes an array as one object
    foreach ($d in $list) { [pscustomobject]@{name = (Field $d 'name'); id = (Field $d 'id')} }
    return
  }
  foreach ($d in @(Get-PnpDevice -Class Ports -ErrorAction Stop)) {
    [pscustomobject]@{name = (Field $d 'FriendlyName'); id = (Field $d 'InstanceId')}
  }
}
$held = @{}
$base = Join-Path (Join-Path $LockRoot 'WstxRust') 'radio-ownership'
$keep = "(COM$KeepPort)"
# Locks every known device not yet held (a device without a name is locked too: it is no COM4).
# Returns (devices known, locked now, devices that could not be locked); a failed query throws.
function Hold-New {
  $known = @(Known-Devices | Where-Object { $_.id })
  $added = 0; $failed = 0
  foreach ($d in $known) {
    if ($d.name.Contains($keep)) { continue }
    $file = Join-Path (Identity-Path $base $d.id) 'owner.lock'
    if ($held.ContainsKey($file)) { continue }
    try {
      [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
      $stream = [IO.FileStream]::new($file, 'OpenOrCreate', 'ReadWrite', 'ReadWrite, Delete')
      try { $stream.Lock(0, [long]::MaxValue) } catch { $stream.Dispose(); throw }
      $held[$file] = $stream
      $added++
    } catch { $failed++ }
  }
  , @($known.Count, $added, $failed)
}
function Report { [IO.File]::WriteAllText("$Record.holding", (ConvertTo-Json -InputObject @($held.Keys | Sort-Object)), [Text.UTF8Encoding]::new($false)) }

# The first scan: ready only with every known device but COM4 locked.
try { $first = Hold-New } catch { Write-Output "BENCH-HOLD ERROR the device query failed: $($_.Exception.Message)"; exit 2 }
if ($first[0] -eq 0) { Write-Output 'BENCH-HOLD ERROR no COM port device is known: nothing to hold, not ready'; exit 2 }
if ($first[2] -gt 0) {
  foreach ($stream in $held.Values) { $stream.Dispose() }
  Write-Output "BENCH-HOLD ERROR $($first[2]) device(s) could not be locked: not ready"; exit 2
}
Report
for (;;) {
  if (-not (Test-Path -LiteralPath $Record -PathType Leaf)) { break }
  $r = $null
  try { $r = [IO.File]::ReadAllText($Record) | ConvertFrom-Json } catch { }
  if ($r -and $r.PSObject.Properties['pid'] -and $r.pid -and -not (Get-Process -Id ([int]$r.pid) -ErrorAction SilentlyContinue)) { break }
  # A scan that fails keeps every lock held; the next poll tries again.
  try { $scan = Hold-New; if ($scan[1] -gt 0) { Report } } catch { }
  Start-Sleep -Milliseconds $PollMilliseconds
}
foreach ($stream in $held.Values) { $stream.Dispose() }
Remove-Item -LiteralPath "$Record.holding" -Force -ErrorAction SilentlyContinue
