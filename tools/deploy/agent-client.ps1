# Station client for the agent: a persistent auth-v1 grant whose private key is a
# non-exportable CNG key in HB9BLA's user key store ("WSTX-Agent-HB9BLA"). Dot-source it:
#   . agent-client.ps1; $c = Open-AgentSession; Agent-Get $c '/transmit'; Agent-Post $c '/route' @{...}
# The grant id is kept in %LOCALAPPDATA%\WstxRust\agent\grant.json (not secret).
$ErrorActionPreference = 'Stop'
$AgentStation = Join-Path $env:LOCALAPPDATA 'WstxRust\station'
$AgentUrl = 'https://192.168.0.37:18081'
$AgentDir = Join-Path $env:LOCALAPPDATA 'WstxRust\agent'
$AgentKeyName = 'WSTX-Agent-HB9BLA'

function ConvertTo-B64UrlA([byte[]]$Bytes) { [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function ConvertFrom-B64UrlA([string]$Text) {
    $t = $Text.Replace('-', '+').Replace('_', '/'); switch ($t.Length % 4) { 2 { $t += '==' } 3 { $t += '=' } 1 { throw 'Invalid base64url.' } }
    [Convert]::FromBase64String($t)
}
function Invoke-AuthV1A($Session, $Operation, $Body) {
    Invoke-WebRequest -UseBasicParsing -Uri "$AgentUrl/authorization/v1/$Operation" -Method Post -Headers @{Origin = $AgentUrl } -Body ($Body | ConvertTo-Json -Compress -Depth 6) -ContentType 'application/json' -WebSession $Session -TimeoutSec 10
}
function Proof-PayloadA($Scope, [string]$GrantId, [byte[]]$Nonce) {
    # Mirrors server authorization::signed_payload (ordinary proof, no operation id).
    $ascii = [Text.Encoding]::ASCII; $out = New-Object IO.MemoryStream
    $domain = $ascii.GetBytes('WSTX-AUTH-PROOF'); $out.Write($domain, 0, $domain.Length); $out.WriteByte(1)
    $fields = @($ascii.GetBytes($AgentUrl), $ascii.GetBytes([string]$Scope.profile_id), $ascii.GetBytes([string]$Scope.radio_id), $ascii.GetBytes(([uint64]$Scope.safety_revision).ToString([Globalization.CultureInfo]::InvariantCulture)), $ascii.GetBytes($GrantId), $Nonce)
    foreach ($f in $fields) {
        $len = [BitConverter]::GetBytes([uint32]$f.Length); if ([BitConverter]::IsLittleEndian) { [Array]::Reverse($len) }
        $out.Write($len, 0, 4); $out.Write($f, 0, $f.Length)
    }
    , $out.ToArray()
}
function Get-AgentKey {
    if ([Security.Cryptography.CngKey]::Exists($AgentKeyName)) { $k = [Security.Cryptography.CngKey]::Open($AgentKeyName) }
    else {
        $p = New-Object Security.Cryptography.CngKeyCreationParameters
        $p.ExportPolicy = [Security.Cryptography.CngExportPolicies]::None
        $p.KeyUsage = [Security.Cryptography.CngKeyUsages]::Signing
        $k = [Security.Cryptography.CngKey]::Create([Security.Cryptography.CngAlgorithm]::ECDsaP256, $AgentKeyName, $p)
    }
    New-Object Security.Cryptography.ECDsaCng $k
}
function Open-AgentSession {
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
    $token = [IO.File]::ReadAllText("$AgentStation\secrets\access-token.txt").Trim()
    try {
        $login = Invoke-WebRequest -UseBasicParsing -Uri "$AgentUrl/session" -Method Post -Headers @{Origin = $AgentUrl } -Body $token -ContentType 'text/plain' -WebSession $session -TimeoutSec 10
    } finally { $token = $null }
    if ($login.StatusCode -ne 204) { throw 'Station login failed.' }
    $scope = ((Invoke-AuthV1A $session 'bootstrap-scope' @{version = 1 }).Content | ConvertFrom-Json).current_scope
    if ($null -eq $scope) { throw 'Station has no current scope.' }
    $key = Get-AgentKey
    try {
        $q = $key.ExportParameters($false).Q
        $publicKey = ConvertTo-B64UrlA ([byte[]](@(4) + $q.X + $q.Y))
        $grantFile = Join-Path $AgentDir 'grant.json'
        $grantId = $null
        if (Test-Path -LiteralPath $grantFile) {
            $saved = Get-Content -LiteralPath $grantFile -Raw | ConvertFrom-Json
            if ($saved.public_key -eq $publicKey -and $saved.profile_id -eq $scope.profile_id -and $saved.radio_id -eq $scope.radio_id) { $grantId = $saved.grant_id }
        }
        $challenge = $null
        if ($grantId) {
            try { $challenge = (Invoke-AuthV1A $session 'challenge' ([ordered]@{version = 1; grant_id = $grantId })).Content | ConvertFrom-Json } catch { $challenge = $null }
        }
        if ($null -eq $challenge) {
            $raw = New-Object byte[] 32; $rng = [Security.Cryptography.RandomNumberGenerator]::Create(); $rng.GetBytes($raw); $rng.Dispose()
            $grantId = ConvertTo-B64UrlA $raw
            $op = [guid]::NewGuid().ToString('D').ToLowerInvariant()
            $receipt = (Invoke-AuthV1A $session 'enroll' ([ordered]@{version = 1; operation_id = $op; scope = $scope; grant_id = $grantId; public_key = $publicKey })).Content | ConvertFrom-Json
            if ($receipt.outcome -ne 'committed' -or $receipt.grant_id -ne $grantId) { throw 'Enrollment not committed.' }
            $null = New-Item -ItemType Directory -Force -Path $AgentDir
            [ordered]@{grant_id = $grantId; public_key = $publicKey; profile_id = $scope.profile_id; radio_id = $scope.radio_id; enrolled_utc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $grantFile -Encoding UTF8
            $challenge = (Invoke-AuthV1A $session 'challenge' ([ordered]@{version = 1; grant_id = $grantId })).Content | ConvertFrom-Json
        }
        if ($challenge.grant_id -ne $grantId -or $challenge.public_key -ne $publicKey) { throw 'Challenge mismatch.' }
        $nonce = ConvertFrom-B64UrlA $challenge.nonce
        $sig = $key.SignData((Proof-PayloadA $challenge.scope $grantId $nonce), [Security.Cryptography.HashAlgorithmName]::SHA256)
        $proof = Invoke-AuthV1A $session 'proof' ([ordered]@{version = 1; grant_id = $grantId; nonce = $challenge.nonce; signature = (ConvertTo-B64UrlA $sig) })
        if ($proof.StatusCode -ne 204) { throw 'Proof refused.' }
        [pscustomobject]@{ Session = $session; Scope = $challenge.scope; GrantId = $grantId }
    } finally { $key.Dispose() }
}
function Agent-Get($c, [string]$Route) { (Invoke-WebRequest -UseBasicParsing -Uri "$AgentUrl$Route" -WebSession $c.Session -TimeoutSec 10).Content | ConvertFrom-Json }
function Agent-Post($c, [string]$Route, $Body) {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "$AgentUrl$Route" -Method Post -Headers @{Origin = $AgentUrl } -Body ($Body | ConvertTo-Json -Compress -Depth 8) -ContentType 'application/json' -WebSession $c.Session -TimeoutSec 15
        [pscustomobject]@{ Status = $r.StatusCode; Body = $(if ($r.Content) { $r.Content | ConvertFrom-Json } else { $null }) }
    } catch [Net.WebException] {
        $resp = $_.Exception.Response; $text = ''
        if ($resp) { $text = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }
        [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $(try { $text | ConvertFrom-Json } catch { $text }) }
    }
}
