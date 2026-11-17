# Switch the station deploy authority on (#30, #31, #32). Run by the operator only.
# -DryRun changes nothing and needs no elevation; it may run from the checkout as HB9BLA:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .harness\deploy\authority\enable-authority.ps1 -OperatorPublicKey <operator key .pub> -DryRun
# The real run executes with Administrator rights, so nothing the agents can write may take
# part in it: not the checkout, not git, not HB9BLA's environment (HKCU\Environment can load
# a DLL into an elevated PowerShell started as HB9BLA). Hence, in an elevated
# `powershell -NoProfile` of a separate administrator account (not HB9BLA):
#   copy this folder to a new folder only Administrators can write
#   (C:\ProgramData\WstxRust-install-<guid>, created with its final permissions in one
#   step as Project-Specifics.md#deployment-authority shows),
#   compare Get-FileHash of every file with the digests in the review record, then run
#   enable-authority.ps1 from that copy.
#  1. Refuses unless it runs elevated, not as HB9BLA, from a folder the protection check
#     accepts, and unless the task runs station\launcher.ps1 as set up by setup-once.ps1.
#     It prints the digests of the files it installs.
#  2. Creates C:\ProgramData\WstxRust\deploy-authority, owned by Administrators, writable
#     only by SYSTEM and Administrators, readable by HB9BLA; installs the verifier, the
#     protected launcher, policy.json, allowed_signers (the operator's public key) and
#     revoked.txt; refuses unless the root then passes the protection check.
#  3. Refuses unless the operator has already approved the running version (sign its
#     request first, see request-approval.ps1), so enabling cannot take the station down.
#  4. Saves the task definition in the root and points the task at the protected launcher
#     (triggers, principal and settings unchanged; HB9BLA keeps run/end). The running
#     station is not restarted: the next start of the task uses the protected launcher.
# disable-authority.ps1 points the task back at station\launcher.ps1.
param([Parameter(Mandatory = $true)][string]$OperatorPublicKey, [switch]$DryRun)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$here = $PSScriptRoot
. ([IO.Path]::Combine($here, 'authority-lib.ps1'))
Use-SystemModules
Import-Module -Name ([IO.Path]::Combine($PSHOME, 'Modules', 'ScheduledTasks', 'ScheduledTasks.psd1'))
$Root = $script:ProtectedRoot
$Station = 'C:\Users\HB9BLA\AppData\Local\WstxRust\station'
$TaskName = 'WSTX Rust Station HB9BLA'
$Destination = 'HB9BLA-station 192.168.0.37:18081'
$Principal = 'operator@HB9BLA'
$Files = @('authority-lib.ps1', 'verify-approval.ps1', 'protected-launcher.ps1')
function Step($t) { Write-Output (([DateTime]::UtcNow.ToString('HH:mm:ss')) + ' ' + $t) }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $DryRun -and -not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this in an elevated PowerShell (title bar "Administrator:").' }
$userSid = (New-Object Security.Principal.NTAccount('HB9BLA')).Translate([Security.Principal.SecurityIdentifier]).Value
if (-not $DryRun) {
  if ($id.User.Value -eq $userSid) { throw 'Run the real enable from a separate administrator account, not HB9BLA (the agents can write HB9BLA''s environment).' }
  Step "check: $here is protected"
  Assert-ProtectedRoot $here ($Files + @('enable-authority.ps1'))
}
Step 'files to install (compare with the review record):'
foreach ($f in $Files) { Step ("  {0}  {1}" -f (Get-FileHash -LiteralPath (Join-Path $here $f) -Algorithm SHA256).Hash.ToLowerInvariant(), $f) }

$key = (Get-Content -LiteralPath $OperatorPublicKey -Raw).Trim()
if ($key -notmatch '^(ssh-ed25519|sk-ssh-ed25519@openssh\.com|ecdsa-sha2-nistp256|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/=]+( [^\r\n]*)?$') { throw 'OperatorPublicKey is not one OpenSSH ed25519 or ecdsa public key line.' }
$allowed = "$Principal namespaces=`"$($script:Namespace)`" $(($key -split ' ')[0..1] -join ' ')`n"
$policy = [ordered]@{ destination = $Destination; signer_principal = $Principal } | ConvertTo-Json

Step 'check: scheduled task'
$xml = Export-ScheduledTask -TaskName $TaskName
[xml]$doc = $xml
$ns = New-Object Xml.XmlNamespaceManager($doc.NameTable); $ns.AddNamespace('t', $doc.DocumentElement.NamespaceURI)
$exec = @($doc.SelectNodes('//t:Actions/t:Exec', $ns))
if ($exec.Count -ne 1) { throw 'Task does not have exactly one action.' }
$argsNode = $exec[0].SelectSingleNode('t:Arguments', $ns)
if ($argsNode.InnerText -ne "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Station\launcher.ps1`"") { throw "Task arguments are '$($argsNode.InnerText)', not the setup-once.ps1 launcher." }
$argsNode.InnerText = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Root\protected-launcher.ps1`""

Step 'check: the operator approved the running version'
$active = Get-Content -LiteralPath (Join-Path $Station 'active.json') -Raw | ConvertFrom-Json
$s = Open-Pinned (Join-Path (Join-Path $Station $active.version) 'wstx-rust.exe')
try { $digest = Get-StreamSha256 $s } finally { $s.Dispose() }
$check = if ($DryRun) { Join-Path ([IO.Path]::GetTempPath()) ('authority-dryrun-' + [Guid]::NewGuid()) } else { $Root }

if ($DryRun) {
  $null = New-Item -ItemType Directory -Path $check
  try {
    [IO.File]::WriteAllText((Join-Path $check 'policy.json'), $policy); [IO.File]::WriteAllText((Join-Path $check 'allowed_signers'), $allowed)
    $null = Test-StationApproval $check $Station $active.source_commit $digest
  } finally { Remove-Item -LiteralPath $check -Recurse -Force }
  Step "dry run: $($active.version) is approved; nothing changed"
  Step ('new task arguments: ' + $argsNode.InnerText)
  return
}

Step "install: $Root"
$parent = Split-Path -Parent $Root
foreach ($d in $parent, $Root) {
  # A folder that already exists must already be protected (an earlier enable); one an
  # agent created first would let it replace what is installed inside.
  if (Test-Path -LiteralPath $d) { Assert-Protected $d; continue }
  $null = New-Item -ItemType Directory -Path $d
  $sec = New-Object Security.AccessControl.DirectorySecurity
  $sec.SetSecurityDescriptorSddlForm("O:BAG:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;$userSid)")
  [IO.Directory]::SetAccessControl($d, $sec)
}
# New files inherit the folder's permissions; existing ones are from an earlier enable and
# are checked below like the new ones.
foreach ($f in $Files) { Copy-Item -LiteralPath (Join-Path $here $f) -Destination (Join-Path $Root $f) -Force }
[IO.File]::WriteAllText((Join-Path $Root 'policy.json'), $policy)
[IO.File]::WriteAllText((Join-Path $Root 'allowed_signers'), $allowed)
if (-not (Test-Path -LiteralPath (Join-Path $Root 'revoked.txt'))) { [IO.File]::WriteAllText((Join-Path $Root 'revoked.txt'), '') }
Assert-ProtectedRoot $Root ($Files + @('policy.json', 'allowed_signers', 'revoked.txt'))
Step 'installed and protected'
$null = Test-StationApproval $Root $Station $active.source_commit $digest
Step "approved: running version $($active.version)"

Step 'point the task at the protected launcher'
[IO.File]::WriteAllText((Join-Path $Root 'task-before-enable.xml'), $xml)
$null = Register-ScheduledTask -TaskName $TaskName -Xml $doc.OuterXml -Force
$svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect()
$task = $svc.GetFolder('\').GetTask($TaskName)
$sd = $task.GetSecurityDescriptor(4)
if ($sd -notmatch [regex]::Escape("(A;;GRGX;;;$userSid)")) { $task.SetSecurityDescriptor($sd + "(A;;GRGX;;;$userSid)", 0) }
Step 'enabled: the next start of the task runs the protected launcher; the running station is unchanged'
Step 'station-update.ps1 needs the authority amendment (Project-Specifics.md#deployment-authority) before the next install'
