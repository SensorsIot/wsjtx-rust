# Protected station launcher (#30, #31, #32); switched off until the operator runs
# enable-authority.ps1, which installs it in C:\ProgramData\WstxRust\deploy-authority and
# points the scheduled task "WSTX Rust Station HB9BLA" at it instead of station\launcher.ps1.
# It does what station\launcher.ps1 does, but first refuses to start any executable that the
# operator has not approved for this destination: it opens station\<version>\wstx-rust.exe so
# that it cannot be changed, hashes those bytes and checks the signed approval of exactly
# that commit and digest. The handle stays open while the station runs. A refusal starts
# nothing, writes logs\launcher-refused-<time>.log and exits 1, so station-update.ps1 sees
# the version not become ready and switches back.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$base = [IO.Path]::Combine([Environment]::GetFolderPath('LocalApplicationData'), 'WstxRust', 'station')
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-ffff')
$pinned = $null
try {
  . ([IO.Path]::Combine($PSScriptRoot, 'authority-lib.ps1'))
  Use-SystemModules
  if (-not $PSScriptRoot.Equals($script:ProtectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw "refused: run from $($script:ProtectedRoot), not $PSScriptRoot" }
  Assert-ProtectedRoot $PSScriptRoot @('authority-lib.ps1', 'verify-approval.ps1', 'protected-launcher.ps1', 'policy.json', 'allowed_signers', 'revoked.txt')
  $active = [IO.File]::ReadAllText([IO.Path]::Combine($base, 'active.json')) | ConvertFrom-Json
  if ($active.version -notmatch '^[0-9a-f]{9}$' -or $active.source_commit -notmatch '^[0-9a-f]{40}$' -or -not $active.source_commit.StartsWith($active.version)) { throw 'refused: active.json is malformed' }
  $exe = [IO.Path]::Combine($base, $active.version, 'wstx-rust.exe')
  if ([IO.File]::GetAttributes([IO.Path]::Combine($base, $active.version)) -band [IO.FileAttributes]::ReparsePoint) { throw 'refused: version directory is a reparse point' }
  $pinned = Open-Pinned $exe
  $digest = Get-StreamSha256 $pinned
  $null = Test-StationApproval $PSScriptRoot $base $active.source_commit $digest
} catch {
  $msg = [string]$_.Exception.Message
  if (-not $msg.StartsWith('refused: ')) { $msg = "refused: unexpected $($_.Exception.GetType().Name) at line $($_.InvocationInfo.ScriptLineNumber)" }
  try { [IO.File]::WriteAllText([IO.Path]::Combine($base, 'logs', "launcher-refused-$stamp.log"), $msg) } catch {}
  [Console]::Out.WriteLine('REFUSED ' + $msg.Substring(9))
  if ($pinned) { $pinned.Dispose() }
  exit 1
}

# From here as station\launcher.ps1, with the executable still pinned.
try { $code = Start-ApprovedStation $base $active.source_commit $exe $digest $stamp } finally { $pinned.Dispose() }
exit $code
