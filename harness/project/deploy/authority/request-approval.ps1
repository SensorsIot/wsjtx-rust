# Prepare the operator's approval of one station package (#31). Run by the agent; it decides
# nothing. It hashes the package's wstx-rust.exe itself and writes <commit>.approval.json
# next to the manifest, naming that commit, that digest and the destination. The operator
# reads it (and the gate receipt it points at) and signs it with a key the agents never see:
#   ssh-keygen -Y sign -f <operator key> -n wstx-station-approval <commit>.approval.json
# The agent then copies both files to %LOCALAPPDATA%\WstxRust\station\approvals\.
#   request-approval.ps1 -Manifest <package manifest.json>
param([Parameter(Mandatory = $true)][string]$Manifest, [string]$Destination = 'HB9BLA-station 192.168.0.37:18081')
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest
$Manifest = (Resolve-Path -LiteralPath $Manifest).Path
$dir = Split-Path -Parent $Manifest
$m = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$commit = [string]$m.source_commit
if ($commit -notmatch '^[0-9a-f]{40}$') { throw 'Manifest source_commit is not a full commit id.' }
$policy = 'C:\ProgramData\WstxRust\deploy-authority\policy.json'
if (Test-Path -LiteralPath $policy) { $Destination = [string](Get-Content -LiteralPath $policy -Raw | ConvertFrom-Json).destination }
$digest = (Get-FileHash -LiteralPath (Join-Path $dir 'package\wstx-rust.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
if ($digest -ne [string]$m.artifact_sha256) { throw "The packaged executable ($digest) is not the manifest's artifact; rebuild the package." }
$approval = [ordered]@{ schema = 'wstx-station-approval/1'; commit = $commit; artifact_sha256 = $digest; destination = $Destination; requested_utc = [DateTime]::UtcNow.ToString('o') }
$out = Join-Path $dir "$commit.approval.json"
[IO.File]::WriteAllText($out, ($approval | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
$gates = Get-Content -LiteralPath ([string]$m.gate_receipt_path) -Raw | ConvertFrom-Json
Write-Output "approval request: $out"
Write-Output "  commit       $commit"
Write-Output "  artifact     $digest"
Write-Output "  destination  $Destination"
Write-Output "  gate record  status=$($gates.status) prepush_passed=$($gates.prepush_passed) receipt=$($gates.gate_receipt.path)"
Write-Output "Operator: check these, then sign on your own machine:"
Write-Output "  ssh-keygen -Y sign -f <your key> -n wstx-station-approval `"$commit.approval.json`""
Write-Output "Agent: copy $commit.approval.json and its .sig to $env:LOCALAPPDATA\WstxRust\station\approvals\"
