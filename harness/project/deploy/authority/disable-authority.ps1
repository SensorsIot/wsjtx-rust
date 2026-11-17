# Switch the station deploy authority off again (#30, #31, #32). Run by the operator only,
# like enable-authority.ps1: in an elevated `powershell -NoProfile` of a separate
# administrator account, from the protected copy whose digests match the review record:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\ProgramData\WstxRust-install-<guid>\disable-authority.ps1 [-DryRun]
# Points the task "WSTX Rust Station HB9BLA" back at station\launcher.ps1 (the setup-once.ps1
# state) and keeps HB9BLA's run/end right. The protected root stays as it is, so enabling
# again keeps the policy and revocations. The running station is not restarted.
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
. ([IO.Path]::Combine($PSScriptRoot, 'authority-lib.ps1'))
Use-SystemModules
Import-Module -Name ([IO.Path]::Combine($PSHOME, 'Modules', 'ScheduledTasks', 'ScheduledTasks.psd1'))
$Station = 'C:\Users\HB9BLA\AppData\Local\WstxRust\station'
$TaskName = 'WSTX Rust Station HB9BLA'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $DryRun -and -not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this in an elevated PowerShell (title bar "Administrator:").' }
$userSid = (New-Object Security.Principal.NTAccount('HB9BLA')).Translate([Security.Principal.SecurityIdentifier]).Value
if (-not $DryRun) {
  if ($id.User.Value -eq $userSid) { throw 'Run from a separate administrator account, not HB9BLA (the agents can write HB9BLA''s environment).' }
  Assert-ProtectedRoot $PSScriptRoot @('authority-lib.ps1', 'disable-authority.ps1')
}
[xml]$doc = Export-ScheduledTask -TaskName $TaskName
$ns = New-Object Xml.XmlNamespaceManager($doc.NameTable); $ns.AddNamespace('t', $doc.DocumentElement.NamespaceURI)
$exec = @($doc.SelectNodes('//t:Actions/t:Exec', $ns))
if ($exec.Count -ne 1) { throw 'Task does not have exactly one action.' }
$argsNode = $exec[0].SelectSingleNode('t:Arguments', $ns)
$protected = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($script:ProtectedRoot)\protected-launcher.ps1`""
if ($argsNode.InnerText -ne $protected) { throw "Task arguments are '$($argsNode.InnerText)', not the protected launcher; nothing to disable." }
$argsNode.InnerText = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Station\launcher.ps1`""
if ($DryRun) { Write-Output ('dry run: new task arguments: ' + $argsNode.InnerText); return }
$null = Register-ScheduledTask -TaskName $TaskName -Xml $doc.OuterXml -Force
$svc = New-Object -ComObject 'Schedule.Service'; $svc.Connect()
$task = $svc.GetFolder('\').GetTask($TaskName)
$sd = $task.GetSecurityDescriptor(4)
if ($sd -notmatch [regex]::Escape("(A;;GRGX;;;$userSid)")) { $task.SetSecurityDescriptor($sd + "(A;;GRGX;;;$userSid)", 0) }
Write-Output 'disabled: the next start of the task runs station\launcher.ps1; revert the station-update.ps1 authority amendment'
