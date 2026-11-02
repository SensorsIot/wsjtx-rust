# Pre-install check of the station deploy authority (#31, #32); switched off until the
# operator runs enable-authority.ps1, which installs this file in the protected root.
#   C:\ProgramData\WstxRust\deploy-authority\verify-approval.ps1 -Manifest <package manifest.json>
# Run before station-update.ps1 changes anything: it hashes the package's wstx-rust.exe
# itself (never trusting a digest written beside it) and requires the operator's signed
# approval of exactly that commit, digest and the protected policy's destination.
# Exit 0: APPROVED. Exit 1: REFUSED <reason> (also for missing evidence and any error).
param([string]$Manifest)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
try {
  . ([IO.Path]::Combine($PSScriptRoot, 'authority-lib.ps1'))
  Use-SystemModules
  if (-not $PSScriptRoot.Equals($script:ProtectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "refused: run from $($script:ProtectedRoot), not $PSScriptRoot" }
  Assert-ProtectedRoot $PSScriptRoot @('authority-lib.ps1', 'verify-approval.ps1', 'protected-launcher.ps1', 'policy.json', 'allowed_signers', 'revoked.txt')
  if (-not $Manifest) { throw 'refused: give -Manifest <package manifest.json>' }
  $m = [IO.File]::ReadAllText($Manifest) | ConvertFrom-Json
  $commit = [string]$m.source_commit
  $exe = [IO.Path]::Combine([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Manifest)), 'package', 'wstx-rust.exe')
  $s = Open-Pinned $exe
  try { $digest = Get-StreamSha256 $s } finally { $s.Dispose() }
  $station = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'WstxRust', 'station')
  $a = Test-StationApproval $PSScriptRoot $station $commit $digest
  [Console]::Out.WriteLine("APPROVED $($commit.Substring(0,9)) exe $($digest.Substring(0,12)) for $($a.destination)")
  exit 0
} catch {
  $msg = [string]$_.Exception.Message
  if (-not $msg.StartsWith('refused: ')) { $msg = "refused: unexpected $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber)" }
  [Console]::Out.WriteLine('REFUSED ' + $msg.Substring(9))
  exit 1
}
