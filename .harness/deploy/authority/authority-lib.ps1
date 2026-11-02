# Station deploy authority (#30, #31, #32), switched off until the operator runs
# enable-authority.ps1. Dot-sourced by verify-approval.ps1 and protected-launcher.ps1 from
# the protected root C:\ProgramData\WstxRust\deploy-authority. See
# docs/harness/Project-Specifics.md#deployment-authority.
#
# Each entry script first calls Use-SystemModules, so no module from a folder the agents can
# write (the user's module path comes first in PSModulePath) is ever loaded.

$script:TrustedSids = @(
  'S-1-5-18',                                                     # SYSTEM
  'S-1-5-32-544',                                                 # Administrators
  'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464' # TrustedInstaller
)
$script:Namespace = 'wstx-station-approval'
$script:ApprovalSchema = 'wstx-station-approval/1'
$script:ProtectedRoot = 'C:\ProgramData\WstxRust\deploy-authority'

function Use-SystemModules {
  $env:PSModulePath = [IO.Path]::Combine($PSHOME, 'Modules')
  $global:PSModuleAutoloadingPreference = 'None'
  foreach ($m in @(Get-Module)) {
    if ($m.Path -and -not $m.Path.StartsWith($PSHOME, [StringComparison]::OrdinalIgnoreCase)) { throw "refused: module $($m.Name) loaded from $($m.Path)" }
  }
  foreach ($name in 'Microsoft.PowerShell.Management', 'Microsoft.PowerShell.Utility') {
    Import-Module -Name ([IO.Path]::Combine($PSHOME, 'Modules', $name, "$name.psd1")) -Global
  }
}

# A file or directory is protected when SYSTEM, Administrators or TrustedInstaller own it and
# no other account may change it. For an ancestor only replacing or re-permissioning it
# matters (creating siblings does not), so the ancestor mask is narrower.
$script:LeafWriteMask = 0x2 -bor 0x4 -bor 0x10 -bor 0x40 -bor 0x100 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000 -bor 0x40000000
$script:AncestorWriteMask = 0x40 -bor 0x10000 -bor 0x40000 -bor 0x80000 -bor 0x10000000
function Assert-Protected([string]$Path, [string[]]$Trusted = $script:TrustedSids, [switch]$Ancestor) {
  $isDir = [IO.Directory]::Exists($Path)
  if (-not $isDir -and -not [IO.File]::Exists($Path)) { throw "refused: $Path is missing" }
  if ([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) { throw "refused: $Path is a reparse point" }
  $acl = if ($isDir) { [IO.Directory]::GetAccessControl($Path) } else { [IO.File]::GetAccessControl($Path) }
  $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
  if ($Trusted -notcontains $owner) { throw "refused: $Path is owned by $owner" }
  $mask = if ($Ancestor) { $script:AncestorWriteMask } else { $script:LeafWriteMask }
  foreach ($ace in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
    if ($ace.AccessControlType -ne 'Allow') { continue }
    if ($ace.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
    if ($Trusted -contains $ace.IdentityReference.Value) { continue }
    if ($ace.IdentityReference.Value -eq 'S-1-3-4') { continue }  # OWNER RIGHTS: the owner, checked above
    if (([int]$ace.FileSystemRights) -band $mask) { throw "refused: $($ace.IdentityReference.Value) may change $Path" }
  }
}

# The protected root, its ancestors, the files the authority uses, PowerShell and ssh-keygen.
function Assert-ProtectedRoot([string]$Root, [string[]]$Files, [string[]]$Trusted = $script:TrustedSids) {
  Assert-Protected $Root $Trusted
  $parent = [IO.Directory]::GetParent($Root)
  while ($parent) { Assert-Protected $parent.FullName $Trusted -Ancestor; $parent = $parent.Parent }
  foreach ($f in $Files) { Assert-Protected ([IO.Path]::Combine($Root, $f)) $Trusted }
  Assert-Protected ([IO.Path]::Combine($PSHOME, 'powershell.exe')) $Trusted
  Assert-Protected (Get-SshKeygen) $Trusted
}

function Get-SshKeygen { [IO.Path]::Combine([Environment]::GetFolderPath('System'), 'OpenSSH', 'ssh-keygen.exe') }

# Open a file so that nobody can change, rename or delete it while the handle is open.
function Open-Pinned([string]$Path) { [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read) }

function Get-StreamSha256([IO.Stream]$Stream) {
  $Stream.Position = 0
  $h = [Security.Cryptography.SHA256]::Create()
  try { ([BitConverter]::ToString($h.ComputeHash($Stream))).Replace('-', '').ToLowerInvariant() } finally { $h.Dispose() }
}

function Read-Policy([string]$Root) {
  $p = [IO.File]::ReadAllText([IO.Path]::Combine($Root, 'policy.json')) | ConvertFrom-Json
  if ([string]$p.destination -notmatch '^[A-Za-z0-9 .:_-]{1,80}$') { throw 'refused: policy destination is malformed' }
  if ([string]$p.signer_principal -notmatch '^[A-Za-z0-9@._-]{1,64}$') { throw 'refused: policy signer_principal is malformed' }
  $p
}

# ssh-keygen -Y verify of the message file, which the caller holds pinned, so the bytes it
# parses are the bytes verified. Windows OpenSSH does not read a .NET pipe reliably, so
# cmd.exe (System32) redirects the file to its standard input. The environment is empty
# except SystemRoot and PROGRAMDATA (ssh-keygen needs both), taken from the system, not from
# the caller, so nothing an agent sets in the environment can redirect it.
function Test-Signature([string]$MessagePath, [string]$SignaturePath, [string]$AllowedSigners, [string]$Principal) {
  foreach ($q in $MessagePath, $SignaturePath, $AllowedSigners) { if ($q -match "[`"%&|<>^!`r`n]") { throw "refused: unusable path $q" } }
  $psi = [Diagnostics.ProcessStartInfo]::new([IO.Path]::Combine([Environment]::GetFolderPath('System'), 'cmd.exe'))
  $psi.Arguments = "/d /c `"`"$(Get-SshKeygen)`" -Y verify -f `"$AllowedSigners`" -I $Principal -n $($script:Namespace) -s `"$SignaturePath`" < `"$MessagePath`"`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables.Clear()
  $psi.EnvironmentVariables['SystemRoot'] = [Environment]::GetFolderPath('Windows')
  $psi.EnvironmentVariables['PROGRAMDATA'] = [Environment]::GetFolderPath('CommonApplicationData')
  $p = [Diagnostics.Process]::Start($psi)
  try {
    $out = $p.StandardOutput.ReadToEndAsync(); $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(30000)) { $p.Kill(); throw 'refused: signature check timed out' }
    $text = $out.Result + $err.Result
    return ($p.ExitCode -eq 0 -and $text.Contains("Good `"$($script:Namespace)`" signature for $Principal "))
  } finally { $p.Dispose() }
}

# The operator's approval of one candidate: station\approvals\<commit>.approval.json and its
# .sig, signed with the operator's key whose public half is in the protected allowed_signers.
# It must name exactly this commit, this artifact digest (computed by the caller from the
# bytes about to be installed or run) and the policy's destination, and the digest must not
# be in the protected revoked.txt. Returns the approval; throws "refused: ..." otherwise.
function Test-StationApproval([string]$Root, [string]$Station, [string]$Commit, [string]$ArtifactSha256) {
  if ($Commit -notmatch '^[0-9a-f]{40}$') { throw 'refused: commit is not a full commit id' }
  if ($ArtifactSha256 -notmatch '^[0-9a-f]{64}$') { throw 'refused: artifact digest is malformed' }
  $policy = Read-Policy $Root
  $approvalPath = [IO.Path]::Combine($Station, 'approvals', "$Commit.approval.json")
  $sigPath = "$approvalPath.sig"
  if (-not [IO.File]::Exists($approvalPath) -or -not [IO.File]::Exists($sigPath)) { throw "refused: no operator approval for $($Commit.Substring(0,9)) ($approvalPath and .sig)" }
  $pin = Open-Pinned $approvalPath
  try {
    $buffer = New-Object byte[] $pin.Length
    if ($pin.Read($buffer, 0, $buffer.Length) -ne $buffer.Length) { throw 'refused: approval could not be read whole' }
    if (-not (Test-Signature $approvalPath $sigPath ([IO.Path]::Combine($Root, 'allowed_signers')) $policy.signer_principal)) {
      throw "refused: approval signature is not the operator's ($($policy.signer_principal))"
    }
  } finally { $pin.Dispose() }
  $a = [Text.Encoding]::UTF8.GetString($buffer).TrimStart([char]0xFEFF) | ConvertFrom-Json
  $keys = @($a.PSObject.Properties.Name | Sort-Object)
  if (($keys -join ',') -ne 'artifact_sha256,commit,destination,requested_utc,schema') { throw "refused: approval fields are $($keys -join ',')" }
  if ($a.schema -ne $script:ApprovalSchema) { throw 'refused: approval schema' }
  if ($a.commit -cne $Commit) { throw "refused: approval names commit $($a.commit), not $Commit" }
  if ($a.artifact_sha256 -cne $ArtifactSha256) { throw "refused: approval names artifact $($a.artifact_sha256), not $ArtifactSha256" }
  if ($a.destination -cne $policy.destination) { throw "refused: approval names destination '$($a.destination)', not '$($policy.destination)'" }
  $revoked = [IO.Path]::Combine($Root, 'revoked.txt')
  if ([IO.File]::Exists($revoked) -and (@([IO.File]::ReadAllLines($revoked) | ForEach-Object { $_.Trim().ToLowerInvariant() }) -contains $ArtifactSha256)) {
    throw "refused: artifact $($ArtifactSha256.Substring(0,12)) is revoked"
  }
  $a
}

# Start the approved executable as station\launcher.ps1 does (the caller keeps it pinned),
# write the launcher receipt and wait; returns the station's exit code.
function Start-ApprovedStation([string]$Base, [string]$Commit, [string]$Exe, [string]$Digest, [string]$Stamp) {
  $secrets = Join-Path $Base 'secrets'
  $env:WSTX_TLS_CERT = Join-Path $secrets 'server.pem'; $env:WSTX_TLS_KEY = Join-Path $secrets 'server.key.pem'
  $env:WSTX_TOKEN = ([IO.File]::ReadAllText((Join-Path $secrets 'access-token.txt'))).Trim()
  $stationProfilePath = Join-Path $Base 'profiles\ic7300'
  $child = Start-Process -FilePath $Exe -ArgumentList @('--profile', ('"' + $stationProfilePath + '"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Base ('logs\' + $Stamp + '.stdout.log')) -RedirectStandardError (Join-Path $Base ('logs\' + $Stamp + '.stderr.log'))
  $null = $child.Handle  # keeps the exit code readable after the process ends
  $receipt = [ordered]@{source_commit = $Commit; artifact_sha256 = $Digest; executable = $Exe; profile = $stationProfilePath; process_id = $child.Id; started_utc = $child.StartTime.ToUniversalTime().ToString('o'); url = 'https://192.168.0.37:18081'; scheduled_task = 'WSTX Rust Station HB9BLA'; authentication = 'TLS and per-profile HttpOnly session cookie'; firewall_client = '192.168.0.6'; launcher = 'active.json'; approval = 'operator-signed, verified by the protected launcher'}
  [IO.File]::WriteAllText((Join-Path $Base 'station-running.json'), ($receipt | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  $child.WaitForExit()
  $child.ExitCode
}
