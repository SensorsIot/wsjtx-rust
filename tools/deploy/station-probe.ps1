# Independent post-install probe of the HB9BLA station (#33). Read-only: it never stops,
# starts or changes the station.
#   station-probe.ps1 -Manifest <package manifest.json>
#   station-probe.ps1 -Commit <40 hex> -ArtifactSha256 <64 hex>
# It does not trust the launcher receipt or the install script. It asks the system which
# process listens on the station port, hashes that process's executable itself and compares
# commit directory and digest with the expected candidate (with -Manifest: the digest of the
# package's own wstx-rust.exe, recomputed here, not the manifest's field). It then requires
# HTTP 200 over TLS verified by Windows from the station URL, and finally that the launcher
# receipt agrees with what it observed. The same response's x-wstx-source-commit header is
# the commit the service itself reports (#33); it must equal the candidate. A build from
# before #33 sends no header; then the running image's digest stays the version identity.
# Exit 0: PROBE PASS. Exit 1: PROBE FAIL <reason> (run station-update.ps1 -Rollback).
# Exit 2: the probe could not run (bad arguments).
param([string]$Manifest, [string]$Commit, [string]$ArtifactSha256,
      [string]$Url = 'https://192.168.0.37:18081', [int]$Port = 18081, [string]$Station)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

function Hash($p) {
  $s = [IO.File]::Open($p, 'Open', 'Read', 'Read')
  try { $h = [Security.Cryptography.SHA256]::Create(); -join ($h.ComputeHash($s) | ForEach-Object { $_.ToString('x2') }) }
  finally { $s.Dispose() }
}
function Fail($why) { Write-Output "PROBE FAIL $why"; exit 1 }

try {
  if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
  if ($Manifest) {
    if ($Commit -or $ArtifactSha256) { Write-Output 'PROBE ERROR give -Manifest or -Commit/-ArtifactSha256, not both'; exit 2 }
    # A wrong -Manifest is a usage error (exit 2), never a failed probe that asks for a rollback.
    try {
      $m = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Manifest).Path) | ConvertFrom-Json
      $Commit = [string]$m.source_commit
      $ArtifactSha256 = Hash (Join-Path (Join-Path (Split-Path -Parent (Resolve-Path -LiteralPath $Manifest).Path) 'package') 'wstx-rust.exe')
    } catch { Write-Output "PROBE ERROR cannot read the package at $Manifest ($($_.Exception.GetType().Name))"; exit 2 }
  }
  if ($Commit -notmatch '^[0-9a-f]{40}$' -or $ArtifactSha256 -notmatch '^[0-9a-f]{64}$') { Write-Output 'PROBE ERROR need a 40-hex commit and a 64-hex artifact SHA-256'; exit 2 }
  $expectExe = [IO.Path]::GetFullPath((Join-Path (Join-Path $Station $Commit.Substring(0, 9)) 'wstx-rust.exe'))
  Write-Output "expect: $($Commit.Substring(0,9)) exe $($ArtifactSha256.Substring(0,12)) at $expectExe"

  $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
  $pids = @($listeners | ForEach-Object { [int]$_.OwningProcess } | Sort-Object -Unique)
  if ($pids.Count -ne 1) { Fail "port $Port has $($pids.Count) listening processes, expected 1" }
  $listenPid = $pids[0]
  $proc = @(Get-CimInstance Win32_Process -Filter "ProcessId=$listenPid")
  if ($proc.Count -ne 1 -or -not $proc[0].ExecutablePath) { Fail "listener PID $listenPid has no executable path" }
  $image = [IO.Path]::GetFullPath([string]$proc[0].ExecutablePath)
  if ($image -ne $expectExe) { Fail "listener PID $listenPid runs $image, expected $expectExe" }
  $digest = Hash $image
  if ($digest -ne $ArtifactSha256) { Fail "listener image digest $($digest.Substring(0,12)) is not the candidate's $($ArtifactSha256.Substring(0,12))" }
  Write-Output "listener: PID $listenPid, $image, digest matches"

  [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
  try { $page = Invoke-WebRequest -UseBasicParsing -Uri "$Url/" -TimeoutSec 10 } catch { Fail "health: $Url/ did not answer over trusted TLS ($($_.Exception.GetType().Name))" }
  if ([int]$page.StatusCode -ne 200) { Fail "health: $Url/ answered $($page.StatusCode)" }
  Write-Output "health: $Url/ 200 over trusted TLS"
  $reported = @($page.Headers['x-wstx-source-commit'] | Where-Object { $null -ne $_ })
  if (-not $reported.Count) {
    Write-Output 'service: reports no commit (a build from before #33); the image digest is the identity'
  } elseif ($reported.Count -ne 1 -or [string]$reported[0] -cne $Commit) {
    Fail "service reports commit $(($reported | ForEach-Object { [string]$_ }) -join ','), expected $Commit"
  } else {
    Write-Output "service: reports commit $($Commit.Substring(0,9))"
  }

  $receiptPath = Join-Path $Station 'station-running.json'
  if (-not (Test-Path -LiteralPath $receiptPath)) { Fail 'launcher receipt missing' }
  $r = [IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
  if ([string]$r.source_commit -ne $Commit -or [int]$r.process_id -ne $listenPid -or [string]$r.artifact_sha256 -ne $ArtifactSha256) {
    Fail "launcher receipt disagrees with the observation (receipt: $([string]$r.source_commit) PID $($r.process_id); observed PID $listenPid)"
  }
  Write-Output "receipt: agrees"
  Write-Output "PROBE PASS $($Commit.Substring(0,9)) PID $listenPid"
  exit 0
} catch {
  Write-Output "PROBE FAIL unexpected $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber)"
  exit 1
}
