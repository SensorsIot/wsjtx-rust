# QSO test driver
# (harness/project/docs/specifics/deployment-authority.md, QSO tests): one QSO test on the
# simulator profile SIM-IC7300 that answers a CQ under the operator's bounds, and its verdict.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/test/powershell/qso-test.ps1 -Holder <run> -Issue <n> -Item <k>
# Order: the profile guard (GET /transmit profile_id is SIM-IC7300's, its CAT port and baud
# from control.endpoint, never COM3); the deployed revision (the one x-wstx-source-commit of
# GET /, 40 lowercase hex, else refused); the attempts of the item on that revision and radio
# (at most 3); the Tx watchdog (6 or below); radio-preflight.ps1 at 0128 with read-back
# (-Minutes 90 on that port) and GET /radio ready within 60 s; /ws with the subprotocol
# wstx.v1 and the subscription spectrum.off, confirmed within 5 s (a failure there is not
# tested, before Tune); the SWR key (the radio.tx_level pushes during 3 s of Tune); the preflight
# at 0255; phase 1 (a target from the decode data, Hold Tx Freq on and a clear tx_hz, at most 4
# calls to one station and 10 transmissions, a first call within 30 minutes); phase 2 (the QSO
# to the 73 under the station's rules, the backstop 30 minutes from the first call). At every
# end the stop order: Auto off; abort the contact it started unless it is at rogers, signoff or
# completed (that one ends on its own, and the driver waits); Halt only while PTT is keyed;
# Hold Tx Freq, rx_hz and tx_hz set back; the power restored with read-back. It never switches
# the profile and never sets the Tx watchdog. Every command carries SIM-IC7300's profile_id, so
# a station running another profile refuses it (wrong_profile), which ends the run. A call or
# transmission limit lets the send that reaches it end before the abort, before the next own
# period.
# The verdict (passed, failed or not_tested, with what was observed) is appended to
# qso-tests.jsonl beside preflight.jsonl, with the revision and the radio. Exit 0 passed, 1
# failed, 3 not tested, 2 refused before anything was touched (arguments, profile, endpoint, no
# deployed revision), 4 a 4th attempt on the item, revision and radio, refused: the operator
# decides.
# Seams: the driver's clock, push reader and revision read (Qso-Now, Qso-Sleep,
# Qso-OpenPushes, Qso-ReceivePushes, Qso-ClosePushes, Qso-Revision) are defined before the
# station client is dot-sourced, so a scripted client (-AgentClient) may replace any of them;
# -Preflight names the preflight script.
param([string]$Holder, [string]$Issue, [string]$Item, [string]$Station, [string]$StateDir,
      [string]$AgentClient, [string]$Preflight)
$ErrorActionPreference = 'Stop'; Set-StrictMode -Version Latest

$SimProfile = 'SIM-IC7300'
$KeyPower = '0128'; $QsoPower = '0255'; $LeaseMinutes = 90
$TuneMs = 3000; $ReadyMs = 60000; $NoCallMs = 1800000; $BackstopMs = 1800000
$PerStation = 4; $TotalCalls = 10; $TxCallsMax = 6; $Attempts = 3
$RetryMs = 10000; $RetryMaxMs = 1800000; $PollMs = 1000; $EndWaitMs = 600000; $LogWaitMs = 30000
$Order = @{ idle = 0; calling = 1; replying = 2; report = 3; roger_report = 4; rogers = 5; signoff = 6; completed = 7 }
$AtOrAfter73 = @('rogers', 'signoff', 'completed')
$Ended = @('completed', 'cancelled', 'idle')

function Say($t) { [Console]::Out.WriteLine("  $t") }
# The value at a dotted path of a JSON object, $null where any part is missing (an array is
# returned enumerated: callers that need one wrap the call in @()).
function P($o, [string]$Path) {
  foreach ($k in $Path.Split('.')) {
    if ($null -eq $o) { return $null }
    if ($o -is [Collections.IDictionary]) { $o = $o[$k] }
    elseif ($o.PSObject.Properties[$k]) { $o = $o.PSObject.Properties[$k].Value }
    else { return $null }
  }
  $o
}

# --- Seams: the clock and the radio.tx_level pushes of the station's /ws ---
function Qso-Now { [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
function Qso-Sleep([long]$Ms) { if ($Ms -gt 0) { Start-Sleep -Milliseconds $Ms } }
$script:Ws = $null; $script:WsTask = $null; $script:WsBuf = $null; $script:WsText = $null; $script:WsKept = $null
$WsConnectMs = 10000; $WsSubscribeMs = 5000; $WsSubscriptionId = 1
# The cause of a failed task: each exception below the AggregateException, type and message,
# down to the innermost.
function Ws-Cause($e) {
  $parts = New-Object Collections.ArrayList
  while ($null -ne $e) {
    if ($e -isnot [AggregateException]) { [void]$parts.Add("$($e.GetType().Name): $($e.Message)") }
    $e = $e.InnerException
  }
  if (-not $parts.Count) { return 'no cause given' }
  $parts -join ' <- '
}
# One whole text message from /ws within $Ms, or $null when none arrived in time. A close or a
# broken connection throws, its reason starting with $What.
function Ws-Read([string]$What, [int]$Ms) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  for (;;) {
    if ($null -eq $script:WsTask) { $script:WsTask = $script:Ws.ReceiveAsync([ArraySegment[byte]]::new($script:WsBuf), [Threading.CancellationToken]::None) }
    $left = [int][Math]::Max(0, $Ms - $watch.ElapsedMilliseconds)
    if ([Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($script:WsTask), $left) -lt 0) { return $null }
    $task = $script:WsTask; $script:WsTask = $null
    if ($task.IsFaulted -or $task.IsCanceled) { throw "${What}: the connection broke ($(Ws-Cause $task.Exception))" }
    $r = $task.Result
    if ($r.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) { throw "${What}: the station closed the connection (close $($r.CloseStatus) '$($r.CloseStatusDescription)')" }
    $script:WsText.Write($script:WsBuf, 0, $r.Count)
    if (-not $r.EndOfMessage) { continue }
    $text = [Text.Encoding]::UTF8.GetString($script:WsText.ToArray()); $script:WsText.SetLength(0)
    return $text
  }
}
function Ws-Push($m) { if ($m -and (P $m 'type') -eq 'radio.tx_level') { [pscustomobject]@{ at = (Qso-Now); data = (P $m 'data') } } }
# Opens /ws as the station's browser does (the subprotocol wstx.v1, the session cookies, the
# Origin of the station URL) and subscribes with spectrum.off (no spectrum, the state events):
# it returns once spectrum.subscription with its integer id and profile off has arrived. Every
# failure throws a reason that starts "the /ws connection" or "the /ws subscription" and names
# the innermost cause or the station's error code.
function Qso-OpenPushes($c) {
  $ws = New-Object System.Net.WebSockets.ClientWebSocket
  $script:Ws = $ws; $script:WsBuf = New-Object byte[] 65536; $script:WsText = New-Object IO.MemoryStream; $script:WsTask = $null
  $script:WsKept = New-Object Collections.ArrayList
  $ws.Options.AddSubProtocol('wstx.v1')
  if ($c.Session) { $ws.Options.Cookies = $c.Session.Cookies }
  $ws.Options.SetRequestHeader('Origin', $AgentUrl)
  $uri = [Uri](($AgentUrl -replace '^http', 'ws') + '/ws')
  $connect = $ws.ConnectAsync($uri, [Threading.CancellationToken]::None)
  if ([Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($connect), $WsConnectMs) -lt 0) { throw "the /ws connection: the upgrade of $uri was not answered within $($WsConnectMs / 1000) s" }
  if ($connect.IsFaulted -or $connect.IsCanceled) { throw "the /ws connection to $uri failed ($(Ws-Cause $connect.Exception))" }
  if ($ws.SubProtocol -ne 'wstx.v1') { throw "the /ws connection: the upgrade answered the subprotocol '$($ws.SubProtocol)', not wstx.v1" }
  $hello = [Text.Encoding]::UTF8.GetBytes('{"v":1,"type":"spectrum.off","id":' + $WsSubscriptionId + '}')
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $send = $ws.SendAsync([ArraySegment[byte]]::new($hello), [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None)
  if ([Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]@($send), $WsSubscribeMs) -lt 0) { throw "the /ws subscription was not sent within $($WsSubscribeMs / 1000) s" }
  if ($send.IsFaulted -or $send.IsCanceled) { throw "the /ws subscription could not be sent ($(Ws-Cause $send.Exception))" }
  for (;;) {
    $text = Ws-Read 'the /ws subscription' ([int][Math]::Max(0, $WsSubscribeMs - $watch.ElapsedMilliseconds))
    if ($null -eq $text) { throw "the /ws subscription: no spectrum.subscription within $($WsSubscribeMs / 1000) s of the send" }
    $m = try { $text | ConvertFrom-Json } catch { $null }
    if (-not $m) { continue }
    $type = P $m 'type'; $id = P $m 'id'
    if ($type -eq 'error' -and ($null -eq $id -or "$id" -eq "$WsSubscriptionId")) { throw "the /ws subscription was refused: error $(P $m 'data.code')" }
    if ($type -eq 'spectrum.subscription' -and "$id" -eq "$WsSubscriptionId") {
      if ((P $m 'data.profile') -ne 'off') { throw "the /ws subscription: profile $(P $m 'data.profile'), not off" }
      Say "the /ws subscription is confirmed (spectrum.subscription $id, profile off)"
      return
    }
    $push = Ws-Push $m
    if ($push) { [void]$script:WsKept.Add($push) }
  }
}
# The radio.tx_level pushes received until the time $Until (ms), each with its receive time.
function Qso-ReceivePushes([long]$Until) {
  $out = New-Object Collections.ArrayList
  if ($script:WsKept) { foreach ($p in $script:WsKept) { [void]$out.Add($p) }; $script:WsKept.Clear() }
  for (;;) {
    $left = $Until - (Qso-Now)
    if ($left -le 0) { break }
    $text = Ws-Read 'the /ws connection' ([int][Math]::Min($left, 1000))
    if ($null -eq $text) { continue }
    $m = try { $text | ConvertFrom-Json } catch { $null }
    $push = Ws-Push $m
    if ($push) { [void]$out.Add($push) }
  }
  $out.ToArray()
}
function Qso-ClosePushes { if ($script:Ws) { try { $script:Ws.Abort(); $script:Ws.Dispose() } catch { Say "note: /ws close: $($_.Exception.Message)" }; $script:Ws = $null } }
# The x-wstx-source-commit values of GET / of the station (Agent-Get returns only a JSON body).
function Qso-Revision($c) {
  $page = Invoke-WebRequest -UseBasicParsing -Uri "$AgentUrl/" -WebSession $c.Session -TimeoutSec 10
  $v = $page.Headers['x-wstx-source-commit']
  if ($null -eq $v) { return }
  # Windows PowerShell joins a repeated header with commas.
  foreach ($x in @($v)) { foreach ($part in ([string]$x).Split(',')) { $part.Trim() } }
}

# --- Run state ---
$script:C = $null; $script:SimId = $null; $script:Own = $null; $script:Port = $null; $script:Baud = $null
$script:Wrong = New-Object Collections.ArrayList; $script:NotTested = New-Object Collections.ArrayList
$script:Notes = New-Object Collections.ArrayList; $script:AskOperator = New-Object Collections.ArrayList
$script:Ending = $false; $script:Backstop = $false; $script:Passed = $false; $script:Done = $false
$script:Touched = $false; $script:PowerUsed = $false; $script:ProfileLost = $false; $script:TuneOn = $false
$script:Before = $null; $script:After = $null; $script:TxCalls = $null
$script:Seen = New-Object 'Collections.Generic.HashSet[long]'; $script:TxCount = 0; $script:CallsTo = @{}; $script:Sent = New-Object Collections.ArrayList
$script:Prev = $null; $script:StartSince = $false; $script:CauseAtStart = $null; $script:AbortSent = $false; $script:HaltSent = $false
$script:Phase = 'setup'; $script:T255 = $null; $script:FirstCall = $null; $script:ReplyAt = $null
$script:Target = $null; $script:Skip = @{}; $script:ContactId = $null; $script:LastState = $null; $script:LastText = $null; $script:Fwd = New-Object Collections.ArrayList
$script:HoldSet = $false; $script:ExpectTx = $null; $script:PrevBusy = $null; $script:BusySeen = $false
$script:Rows = New-Object Collections.ArrayList; $script:JobKey = $null; $script:Cursor = 0; $script:Ident = $null; $script:Mode = 'ft8'
$script:Cause = $null; $script:Failure = $null; $script:Refusal = $null; $script:Swr = $null; $script:Po = @()

function Not-Tested([string]$Why) {
  [void]$script:NotTested.Add($Why); Say "not tested: $Why"
  if (-not $script:Ending) { throw 'QSO-END' }
}
function Wrong([string]$Why) {
  [void]$script:Wrong.Add($Why); Say "WRONG ACTION $Why"
  if (-not $script:Ending) { throw 'QSO-END' }
}
function Note([string]$Text) { [void]$script:Notes.Add($Text); Say $Text }
function Period-Ms { if ($script:Mode -eq 'ft4') { 7500 } else { 15000 } }
function Width-Hz { if ($script:Mode -eq 'ft4') { 90 } else { 50 } }
function Parity([long]$Start) { if ([Math]::Floor($Start / (Period-Ms)) % 2 -eq 0) { 'even' } else { 'odd' } }
function First-Token([string]$Text) { (($Text.Trim() -split '\s+') + @(''))[0] }

# --- Station commands ---
function Get-Transmit {
  $t = Agent-Get $script:C '/transmit'
  if ((P $t 'profile_id') -ne $script:SimId -and -not $script:ProfileLost) {
    $script:ProfileLost = $true
    Not-Tested "the station runs profile $(P $t 'profile_id'), not $SimProfile ($($script:SimId)): agents key only the simulator"
  }
  $t
}
# Every command carries SIM-IC7300's profile_id from its profile.json, never one read from the
# station: a station running another profile refuses it itself (wrong_profile), which ends the
# run as the profile guard does.
function Post-Command([string]$Route, [string]$Action, $Body) {
  $r = Agent-Post $script:C $Route $Body
  $ok = [int]$r.Status -ge 200 -and [int]$r.Status -lt 300 -and (P $r 'Body.accepted') -ne $false
  if ($ok) { Say "command ${Action}: accepted"; return $true }
  $code = P $r 'Body.error.code'
  Say "command ${Action}: refused ($($r.Status) $code)"
  if ($code -eq 'wrong_profile' -and -not $script:ProfileLost) {
    $script:ProfileLost = $true
    Not-Tested "the station refused $Action with wrong_profile: it runs another profile than $SimProfile ($($script:SimId)); agents key only the simulator"
  }
  $false
}
function Contact-Command([string]$Action, [hashtable]$Params) {
  $k = Agent-Get $script:C '/contact'
  $body = [ordered]@{ v = 1; profile_id = $script:SimId; boot_id = (P $k 'boot_id'); command_id = [guid]::NewGuid().ToString(); contact_revision = (P $k 'contact_revision'); action = $Action }
  foreach ($key in $Params.Keys) { $body[$key] = $Params[$key] }
  $script:Touched = $true
  Post-Command '/contact/command' $Action $body
}
function Transmit-Envelope {
  $t = Agent-Get $script:C '/transmit'
  [ordered]@{ v = 1; profile_id = $script:SimId; boot_id = (P $t 'boot_id'); command_id = [guid]::NewGuid().ToString() }
}

# --- The radio preflight ---
function Run-Preflight([hashtable]$A) {
  $A['StateDir'] = $StateDir; $A['Station'] = $Station; $A['AgentClient'] = $AgentClient
  $shown = ($A.Keys | Where-Object { $_ -notin @('StateDir', 'Station', 'AgentClient') } | Sort-Object | ForEach-Object { "-$_ $($A[$_])" }) -join ' '
  $global:LASTEXITCODE = 0
  try { $out = (& $Preflight @A 2>&1 | Out-String).Trim(); $code = $LASTEXITCODE }
  catch { $out = $_.Exception.Message; $code = 2 }
  Say "preflight ${shown}: exit $code $out"
  return @($code, $out)
}
function Wait-Ready([string]$After) {
  $deadline = (Qso-Now) + $ReadyMs
  for (;;) {
    try { if ((P (Agent-Get $script:C '/radio') 'state') -eq 'ready') { Say "GET /radio ready after the preflight $After"; return $true } }
    catch { try { $script:C = Open-AgentSession } catch { Say "note: the station session: $($_.Exception.Message)" } }
    if ((Qso-Now) -ge $deadline) { return $false }
    Qso-Sleep 1000
  }
}
function Power([string]$Bcd) {
  $script:PowerUsed = $true
  $code, $out = Run-Preflight @{ Holder = $Holder; PowerBcd = $Bcd; Minutes = $LeaseMinutes; Port = $script:Port; Baud = $script:Baud }
  if ($code -ne 0) { Not-Tested "the preflight at $Bcd did not pass (exit $code): $out" }
  if (-not (Wait-Ready $Bcd)) { Not-Tested "GET /radio did not read ready within 60 s after the preflight at $Bcd" }
}
function First-Pass-Record {
  $path = Join-Path $StateDir 'preflight.jsonl'
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  foreach ($line in [IO.File]::ReadAllLines($path)) {
    if (-not $line.Trim()) { continue }
    $r = $line | ConvertFrom-Json
    if ((P $r 'holder') -eq $Holder -and (P $r 'verdict') -eq 'PASS' -and (P $r 'restore') -eq $false) { return $r }
  }
  $null
}
# Retries a BUSY preflight every 10 s; returns its exit code.
function Preflight-Retried([hashtable]$A) {
  $deadline = (Qso-Now) + $RetryMaxMs
  for (;;) {
    $code, $out = Run-Preflight $A.Clone()
    if ($code -ne 3 -or (Qso-Now) -ge $deadline) { return $code }
    Qso-Sleep $RetryMs
  }
}
function Restore-Power {
  $code, $status = Run-Preflight @{ Status = $true }
  if ($status -match "held by $([regex]::Escape($Holder)) until") {
    $code = Preflight-Retried @{ Restore = $true; Holder = $Holder }
    if ($code -eq 0) { [void](Wait-Ready 'restore'); return }
    $code, $status = Run-Preflight @{ Status = $true }
    if ($status -match "held by $([regex]::Escape($Holder)) until") { Note "THE POWER IS NOT RESTORED: -Restore exit $code under a live lease; ask the operator"; [void]$script:AskOperator.Add('power not restored'); return }
  }
  # No live lease: the value found is the first PASS record of this holder that is no restore.
  $first = First-Pass-Record
  if (-not $first) { Note "THE POWER IS NOT RESTORED: no live lease and no PASS record of $Holder in preflight.jsonl; ask the operator"; [void]$script:AskOperator.Add('power not restored'); return }
  $old = '{0:D4}' -f [int](P $first 'rf_power_old_bcd')
  $set = @{ Holder = $Holder; PowerBcd = $old; Minutes = 1 }
  if (P $first 'port') { $set['Port'] = [string](P $first 'port'); $set['Baud'] = [string](P $first 'baud') }
  Note "no live lease: restoring $old, the value found by the first PASS record of $Holder"
  $code = Preflight-Retried $set
  if ($code -ne 0) { Note "THE POWER IS NOT RESTORED: setting $old exited $code; ask the operator"; [void]$script:AskOperator.Add('power not restored') }
  [void](Run-Preflight @{ Release = $true; Holder = $Holder })
  [void](Wait-Ready 'restore')
}

# --- The SWR key ---
function Swr-Key {
  # A /ws that does not open or subscribe ends the run before Tune: not a missing reading, and
  # nothing for the operator.
  $why = $null
  try { Qso-OpenPushes $script:C } catch { $why = [string]$_.Exception.Message }
  if ($null -ne $why) {
    Qso-ClosePushes
    if ($why -notlike 'the /ws*') { $why = "the /ws connection: $why" }
    Not-Tested $why
  }
  $early = @(); $during = @(); $on = $null; $off = $null
  try {
    $early = @(Qso-ReceivePushes ((Qso-Now) + 1000))
    $k = Agent-Get $script:C '/contact'
    $script:TuneOn = $true
    $ok = Contact-Command 'tune' @{ enabled = $true; safety_revision = (P $k 'transmit.safety_revision') }
    $on = Qso-Now
    if (-not $ok) { $script:TuneOn = $false; Not-Tested 'Tune was refused: no SWR reading' }
    $during = @(Qso-ReceivePushes ($on + $TuneMs))
    $off = Qso-Now
  } finally {
    # A Tune refused with wrong_profile was never on, and another profile takes no command.
    if ($script:TuneOn -and -not $script:ProfileLost) { [void](Contact-Command 'tune' @{ enabled = $false }) }
    $script:TuneOn = $false
    Qso-ClosePushes
  }
  $t = Get-Transmit
  $p = P $t 'transmit.last_period_utc'
  if ($null -ne $p) { [void]$script:Seen.Add([long]$p) }
  $script:Prev = $t
  $fresh = @($during | Where-Object { $_.at -ge $on -and $_.at -le $off -and $null -ne (P $_.data 'meters') -and $null -ne (P $_.data 'meters.po_pct') -and $null -ne (P $_.data 'meters.swr_x10') })
  $fault = @(@($early) + @($during) | Where-Object { @(P $_.data 'warnings') -contains 'swr_fault' }).Count -gt 0
  $script:Po = @($fresh | ForEach-Object { [int](P $_.data 'meters.po_pct') })
  if ($fresh.Count) { $script:Swr = ($fresh | ForEach-Object { [int](P $_.data 'meters.swr_x10') } | Measure-Object -Maximum).Maximum }
  Say "SWR key: $($fresh.Count) fresh readings, Po % $($script:Po -join ' '), highest swr_x10 $($script:Swr), swr_fault $fault"
  $why = @()
  if ($fault) { $why += 'swr_fault' }
  if ($fresh.Count -eq 0) { $why += "no fresh reading ($(@($early).Count) pushes before Tune on, $(@($during).Count) during it, none with meters, po_pct and swr_x10)" }
  elseif (@($script:Po | Where-Object { $_ -ge 1 }).Count -eq 0) { $why += "po_pct 0 in every reading" }
  if ($null -ne $script:Swr -and $script:Swr -ge 30) { $why += "swr_x10 $($script:Swr), SWR 3.0 or more" }
  if ($why) {
    [void]$script:AskOperator.Add("SWR key at ${KeyPower}: $($why -join '; ')")
    Not-Tested "SWR key at ${KeyPower}: $($why -join '; '); no $QsoPower write; ask the operator"
  }
}

# --- The decode data ---
function Period-Of($record) {
  $s = P $record 'period_start_utc'
  if ($null -eq $s) { return $null }
  if ($s -is [DateTime]) { return ([DateTimeOffset]$s.ToUniversalTime()).ToUnixTimeMilliseconds() }
  [DateTimeOffset]::Parse([string]$s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeMilliseconds()
}
function Read-Records {
  $rv = Agent-Get $script:C '/receive'
  $src = P $rv 'source.id'; $job = P $rv 'job.id'; $gen = P $rv 'generation'
  if (-not $src -or -not $job) { return }
  if ((P $rv 'job.mode') -in @('ft8', 'ft4')) { $script:Mode = P $rv 'job.mode' }
  $key = "$src/$job/$gen"
  if ($key -ne $script:JobKey) {
    $script:JobKey = $key; $script:Rows.Clear(); $script:Cursor = [long](P $rv 'job.first_sequence')
    $script:Ident = @{ source_id = $src; job_id = $job; generation = $gen }
  }
  $next = [long](P $rv 'job.next_sequence')
  while ($script:Cursor -lt $next) {
    try { $page = Agent-Get $script:C "/receive/results?source_id=$src&job_id=$job&generation=$gen&cursor=$($script:Cursor)&limit=16" }
    catch { $script:Cursor = [long](P $rv 'job.first_sequence'); Say "note: results: $($_.Exception.Message)"; return }
    foreach ($r in @(P $page 'records')) {
      if ((P $r 'status') -ne 'decoded') { continue }
      [void]$script:Rows.Add([pscustomobject]@{
          from = $(if ((P $r 'fields.from.kind') -eq 'call') { [string](P $r 'fields.from.text') } else { $null })
          to = [string](P $r 'fields.to.text'); to_kind = [string](P $r 'fields.to.kind'); type = [string](P $r 'fields.type')
          period = (Period-Of $r); sequence = [long](P $r 'sequence'); hz = [double](P $r 'frequency_hz')
          worked = (P $r 'worked_status'); text = [string](P $r 'text') })
    }
    $n = [long](P $page 'next')
    if ($n -le $script:Cursor) { break }
    $script:Cursor = $n
  }
  # Only the last 10 minutes are judged (the drop rule looks 75 s back in FT8).
  $since = (Qso-Now) - 600000
  if ($script:Rows.Count -and $script:Rows[0].period -lt $since) {
    $kept = @($script:Rows | Where-Object { $_.period -ge $since }); $script:Rows.Clear(); foreach ($r in $kept) { [void]$script:Rows.Add($r) }
  }
}
function General-Cq($row) { $row.type -eq 'standard' -and $row.to_kind -eq 'token' -and $row.to -ceq 'CQ' -and $row.from }
function Rows-Of([string]$Call) { @($script:Rows | Where-Object { $_.from -eq $Call } | Sort-Object period, sequence) }
function Newest-Of([string]$Call) { $r = @(Rows-Of $Call); if ($r.Count) { $r[-1] } }
# A period counts as decoded once a row of it or of a later period is published.
function Decoded([long]$Period) { @($script:Rows | Where-Object { $_.period -ge $Period }).Count -gt 0 }
# Other stations that sent to his call in the two most recent decoded periods that each follow
# one of his CQs; -1 while fewer than two such periods are decoded.
function Pileup([string]$Call) {
  $len = Period-Ms
  $follow = @(Rows-Of $Call | Where-Object { General-Cq $_ } | ForEach-Object { $_.period + $len } | Sort-Object -Unique -Descending | Where-Object { Decoded $_ } | Select-Object -First 2)
  if ($follow.Count -lt 2) { return -1 }
  @($script:Rows | Where-Object { $_.period -in $follow -and $_.to -eq $Call -and $_.from -and $_.from -ne $Call } | ForEach-Object { $_.from } | Sort-Object -Unique).Count
}
# Why he is no target now, or $null; 'drop' marks the drop rule, 'wait' too few periods.
function Target-Refusal([string]$Call, [long]$Now) {
  $newest = Newest-Of $Call
  if (-not $newest -or -not (General-Cq $newest)) { return 'drop: his newest message is no longer a general CQ' }
  if ($Now - $newest.period -ge 4 * (Period-Ms) + (Period-Ms)) { return 'drop: no CQ again within two of his cycles' }
  if ($newest.worked -notin @('not_worked', 'worked_other_band_or_mode')) { return "worked_status $($newest.worked)" }
  $pile = Pileup $Call
  if ($pile -lt 0) { return 'wait: fewer than two decoded periods after his CQs' }
  if ($pile -ge 2) { return "pile-up: $pile other callers" }
  $null
}
function Choose-Target([long]$Now) {
  $best = $null
  foreach ($call in @($script:Rows | Where-Object { $_.from } | ForEach-Object { $_.from } | Sort-Object -Unique)) {
    if ($call -eq $script:Own -or $script:Skip.ContainsKey($call)) { continue }
    $newest = Newest-Of $call
    if (-not (General-Cq $newest)) { continue }
    $why = Target-Refusal $call $Now
    if ($why) { if ($why -like 'drop:*') { $script:Skip[$call] = $why; Say "$call dropped ($why)" }; continue }
    if (-not $best -or $newest.period -gt $best.period) { $best = $newest }
  }
  $best
}
# The tx_hz for his CQ row from the newest free_tx_slots build, or $null.
function Pick-Tx($Build, $Row) {
  if ($null -eq $Build -or (P $Build 'rx_parity') -ne (Parity $Row.period)) { return $null }
  $w = Width-Hz; $clear = $w + 50; $his = $Row.hz
  $best = $null; $bestD = $null; $near = $null; $nearD = $null
  foreach ($range in @(P $Build 'open')) {
    $lo = [int]$range[0]; $top = [int]$range[1] - $w
    if ($top -lt $lo) { continue }
    $d = if ($his -lt $lo) { $lo - $his } elseif ($his -gt $top) { $his - $top } else { 0 }
    if ($null -eq $near -or $d -lt $nearD) { $near = $lo; $nearD = $d }
    foreach ($f in @([Math]::Round($his), [Math]::Ceiling($his + $clear), [Math]::Floor($his - $clear))) {
      $f = [int][Math]::Min([Math]::Max($f, $lo), $top)
      $dist = [Math]::Abs($f - $his)
      if ($dist -lt $clear) { continue }
      if ($null -eq $best -or $dist -lt $bestD -or ($dist -eq $bestD -and $f -lt $best)) { $best = $f; $bestD = $dist }
    }
  }
  if ($null -ne $best) { return $best }
  $near
}

# --- Judging each snapshot ---
function Auto-On($a) { $run = P $a 'run'; $null -ne $run -and (P $run 'state') -ne 'stopped' }
function Judge($t, $k, $a) {
  $tr = P $t 'transmit'
  $on = ($null -ne $script:Prev -and (P $script:Prev 'transmit.arm_state') -eq 'armed') -or $script:StartSince
  $p = P $tr 'last_period_utc'; $new = $false
  if ($null -ne $p -and $script:Seen.Add([long]$p)) {
    $new = $true
    $text = [string](P $tr 'last_text'); $to = First-Token $text
    $script:TxCount++; $script:CallsTo[$to] = 1 + [int]$script:CallsTo[$to]
    [void]$script:Sent.Add([pscustomobject]@{ period = [long]$p; text = $text })
    Say "transmission $($script:TxCount): period $p '$text'"
    if ($script:HaltSent -or -not $on) { Wrong "(a) a transmission started at $p while the transmit state was off ('$text')" }
    if ($text -match '^CQ(\s|$)') { Wrong "(b) a CQ was keyed: '$text'" }
    elseif ($script:Target -and $to -ne $script:Target) { Wrong "(b) '$text' is addressed to $to, not the target $($script:Target)" }
    foreach ($fwd in @($script:Fwd)) {
      if ([long]$p -le $fwd.ref) { continue }
      $fwd.n++
      if ($fwd.n -eq 2) {
        [void]$script:Fwd.Remove($fwd)
        if ($text -eq $fwd.text) { Wrong "(f) '$text' keyed again in the second own period after the decode that moved the contact forward" }
      }
    }
    $script:LastText = $text
  }
  if ($on -and (P $tr 'arm_state') -ne 'armed') {
    $cause = [string](P $tr 'last_disarm_cause')
    $changed = $new -or ($null -ne $script:Prev -and (P $script:Prev 'transmit.arm_state') -eq 'armed') -or $cause -ne $script:CauseAtStart
    if ($cause -eq 'contact_cancelled' -and $script:AbortSent) { $script:AbortSent = $false }
    elseif ($cause -eq 'halt' -and $script:HaltSent) { }
    elseif ($cause -ne 'contact_completed' -and $changed) {
      $script:Cause = $cause; $script:Refusal = P $tr 'refusal'
      $outcomes = @(P $t 'outcomes'); if ($outcomes.Count) { $script:Failure = P $outcomes[-1] 'failure' }
      Not-Tested "last_disarm_cause $cause (refusal $($script:Refusal), failure $($script:Failure))"
    }
  }
  $script:StartSince = $false
  $script:Prev = $t
  $busy = P $k 'watchdog.busy_with'
  if ($busy) { $script:BusySeen = $true }
  # (c): manual test QSO with Hold Tx Freq on; the busy move is exempt while busy_with is set
  # and in the step that clears it.
  if (-not $script:Ending -and $null -ne $script:ExpectTx) {
    $tx = P $k 'settings.tx_hz'
    if ($tx -ne $script:ExpectTx) {
      if (Auto-On $a) { Say "tx_hz $tx in Auto: (c) is not checked"; $script:ExpectTx = $tx }
      elseif ((P $k 'settings.hold_tx') -ne $true) { $script:ExpectTx = $tx }
      elseif ($busy -or $script:PrevBusy) { Say "busy move: tx_hz $($script:ExpectTx) -> $tx (busy_with $busy, before $($script:PrevBusy))"; $script:ExpectTx = $tx }
      else { Wrong "(c) tx_hz $tx, not $($script:ExpectTx), with Hold Tx Freq on and no busy move" }
    }
  }
  $script:PrevBusy = $busy
  $c = P $k 'contact'
  if ($script:ContactId -and $c -and (P $c 'id') -eq $script:ContactId) {
    $state = [string](P $c 'state')
    if ($Order.ContainsKey($state) -and $Order.ContainsKey([string]$script:LastState) -and $Order[$state] -gt $Order[[string]$script:LastState] -and $state -ne 'completed') {
      $rx = @(@(P $c 'dialogue') | Where-Object { (P $_ 'dir') -eq 'rx' })
      $ref = if ($rx.Count) { [long](P $rx[-1] 'period_utc_ms') } else { Qso-Now }
      [void]$script:Fwd.Add(@{ text = $script:LastText; ref = $ref; n = 0 })
    }
    $script:LastState = $state
    $limit = [int]$script:TxCalls * $(if ($script:BusySeen) { 2 } else { 1 })
    foreach ($row in @(P $c 'dialogue')) {
      if ((P $row 'dir') -eq 'tx' -and [int](P $row 'count') -gt $limit) { Wrong "(d) '$(P $row 'text')' keyed $(P $row 'count') times, above $limit" }
    }
    if ($state -eq 'completed' -and -not $script:Done) { Complete $c }
  }
}
function Answered($k) {
  $c = P $k 'contact'
  if ($script:ContactId -and $c -and (P $c 'id') -eq $script:ContactId) {
    foreach ($row in @(P $c 'dialogue')) { if ((P $row 'dir') -eq 'rx' -and (First-Token ([string](P $row 'text'))) -eq $script:Own) { return $true } }
  }
  @($script:Rows | Where-Object { $_.from -eq $script:Target -and $_.to -eq $script:Own -and $_.period -ge $script:ReplyAt - 2 * (Period-Ms) }).Count -gt 0
}
function Complete($c) {
  $script:Done = $true
  $id = P $c 'id'; $deadline = (Qso-Now) + $LogWaitMs; $log = $null
  for (;;) {
    $k = Agent-Get $script:C '/contact'
    if ((P $k 'log.contact_id') -eq $id) { $log = P $k 'log'; break }
    if ((Qso-Now) -ge $deadline) { break }
    Qso-Sleep $PollMs
  }
  if (-not $log) { Not-Tested "contact $id completed without a log entry within 30 s"; return }
  if ((P $log 'outcome') -ne 'saved' -or $null -ne (P $log 'error')) { Wrong "(e) contact $id completed with log outcome $(P $log 'outcome'), error $(P $log 'error')"; return }
  $t = Agent-Get $script:C '/transmit'; $cause = P $t 'transmit.last_disarm_cause'
  $rows = @(P $c 'dialogue')
  $rx = @($rows | Where-Object { (P $_ 'dir') -eq 'rx' } | ForEach-Object { [string](P $_ 'text') })
  $tx = @($rows | Where-Object { (P $_ 'dir') -eq 'tx' } | ForEach-Object { [string](P $_ 'text') })
  $report = '(^|\s)R?[+-]\d{1,2}(\s|$)'; $end = '(^|\s)(RR73|73)(\s|$)'
  $missing = @()
  if ($cause -ne 'contact_completed') { $missing += "last_disarm_cause $cause" }
  if (-not @($rx | Where-Object { (First-Token $_) -eq $script:Own }).Count) { $missing += 'his message to the own call' }
  if (-not @($rx | Where-Object { $_ -match $report }).Count) { $missing += 'a report received' }
  if (-not @($tx | Where-Object { $_ -match $report }).Count) { $missing += 'a report sent' }
  if (-not @(@($rx) + @($tx) | Where-Object { $_ -match $end }).Count) { $missing += 'RR73 or 73' }
  if ($missing) { Not-Tested "contact $id completed without: $($missing -join ', ')"; return }
  $script:Passed = $true
  Say "contact $id completed, logged (saved) and complete"
}

# --- Phase 1: the target and the calls ---
function Abort-Own([string]$Why) {
  Say "abort the call to $($script:Target): $Why"
  $script:Skip[$script:Target] = $Why
  $script:AbortSent = [bool](Contact-Command 'abort' @{})
  $script:Target = $null
}
# A limit counts whole transmissions: the send that reaches it is let end (transmitting false,
# PTT released) before the abort, which comes before the next own period at the latest.
function Send-Ended($t, [long]$Now) {
  $last = if ($script:Sent.Count) { $script:Sent[$script:Sent.Count - 1].period } else { 0 }
  if ((P $t 'transmitting') -ne $true -and (P $t 'ptt') -eq 'released') { return $true }
  if ($Now -ge $last + 2 * (Period-Ms) - 2000) { Note "the send of $last still reads on the air before the next own period: stopped now"; return $true }
  $false
}
function Phase-One($t, $k, $a, [long]$Now) {
  if ($script:Target) {
    if (Answered $k) { $script:Phase = 'phase2'; Say "phase 2: $($script:Target) answered"; return }
    if ($script:TxCount -ge $TotalCalls) {
      if (-not (Send-Ended $t $Now)) { return }
      Not-Tested "$TotalCalls transmissions without an answer"
    }
    if ([int]$script:CallsTo[$script:Target] -ge $PerStation) {
      if (-not (Send-Ended $t $Now)) { return }
      Abort-Own "$PerStation calls without an answer"; return
    }
    $why = Target-Refusal $script:Target $Now
    if ($why -like 'drop:*') { Abort-Own $why }
    return
  }
  if ($script:TxCount -ge $TotalCalls) { Not-Tested "$TotalCalls transmissions without an answer" }
  if ($null -eq $script:FirstCall -and $Now -ge $script:T255 + $NoCallMs) { Not-Tested "no call within 30 minutes of the $QsoPower read-back" }
  if ((P $t 'transmit.arm_state') -eq 'armed') { return }
  $row = Choose-Target $Now
  if (-not $row) { return }
  $f = Pick-Tx (P $a 'free_tx_slots') $row
  if ($null -eq $f) { return }
  [void](Get-Transmit)
  if (-not $script:HoldSet) {
    if (-not (Contact-Command 'set_hold_tx' @{ enabled = $true })) { Not-Tested 'set_hold_tx was refused' }
    $script:HoldSet = $true
  }
  if (-not (Contact-Command 'set_frequency' @{ rx_hz = (P $k 'settings.rx_hz'); tx_hz = $f })) { Not-Tested 'set_frequency was refused' }
  $script:ExpectTx = $f
  $kk = Agent-Get $script:C '/contact'
  $script:CauseAtStart = [string](P $t 'transmit.last_disarm_cause')
  $id = $script:Ident
  $ok = Contact-Command 'reply' @{ row = [ordered]@{ source_id = $id.source_id; job_id = $id.job_id; generation = $id.generation; sequence = $row.sequence }; safety_revision = (P $kk 'transmit.safety_revision') }
  if (-not $ok) { Not-Tested "the reply to $($row.from) was refused (refused)" }
  $script:StartSince = $true; $script:Target = $row.from; $script:ReplyAt = Qso-Now
  if ($null -eq $script:FirstCall) { $script:FirstCall = $script:ReplyAt }
  $script:ContactId = P (Agent-Get $script:C '/contact') 'contact.id'; $script:LastState = 'replying'
  Say "call $($row.from) at tx_hz $f (his CQ at $($row.hz) Hz, $(Parity $row.period)), contact $($script:ContactId)"
}
function Run-Qso {
  $script:Phase = 'phase1'
  for (;;) {
    $now = Qso-Now
    $t = Get-Transmit
    $k = Agent-Get $script:C '/contact'
    $a = Agent-Get $script:C '/automation'
    Read-Records
    Judge $t $k $a
    if ($script:Done) { return }
    if ($null -ne $script:FirstCall -and $now -ge $script:FirstCall + $BackstopMs) {
      $script:Backstop = $true; Note 'the 30-minute backstop from the first call is reached'; throw 'QSO-END'
    }
    if ($script:Phase -eq 'phase1') { Phase-One $t $k $a $now }
    Qso-Sleep $PollMs
  }
}

# --- The stop order ---
function Stop-Order {
  $script:Ending = $true
  if (-not $script:Touched -and -not $script:PowerUsed) { return }
  Say 'stop order'
  # Each step is skipped once the station runs another profile (the guard or a wrong_profile
  # refusal): Auto, the contact, Halt and the settings are then not this run's.
  $steps = [ordered]@{
    'Auto off' = {
      $a = Agent-Get $script:C '/automation'
      if (Auto-On $a) { $body = Transmit-Envelope; $body['action'] = 'stop'; $body['run_id'] = P $a 'run.id'; [void](Post-Command '/automation/command' 'auto_stop' $body) }
    }
    'abort' = { Abort-Or-Wait }
    'Halt' = { Halt-If-Keyed }
    'set back' = { Set-Back }
    'last look' = { Judge (Agent-Get $script:C '/transmit') (Agent-Get $script:C '/contact') (Agent-Get $script:C '/automation') }
  }
  foreach ($name in $steps.Keys) {
    if ($script:ProfileLost) { Note "the station runs another profile: $name and the steps after it are not done"; break }
    try { & $steps[$name] } catch { Note "$name failed: $($_.Exception.Message)" }
  }
  Qso-ClosePushes
  if ($script:PowerUsed) { try { Restore-Power } catch { Note "THE POWER IS NOT RESTORED: $($_.Exception.Message)"; [void]$script:AskOperator.Add('power not restored') } }
}
function Abort-Or-Wait {
  if (-not $script:ContactId) { return }
  $c = P (Agent-Get $script:C '/contact') 'contact'
  if (-not $c -or (P $c 'id') -ne $script:ContactId) { Say 'the contact it started is no longer the station''s: nothing aborted'; return }
  $state = [string](P $c 'state')
  if ($state -in $Ended) { return }
  if ($state -in $AtOrAfter73) {
    Say "contact at ${state}: not aborted, it ends on its own"
    $deadline = (Qso-Now) + $EndWaitMs
    for (;;) {
      Qso-Sleep $PollMs
      $t = Agent-Get $script:C '/transmit'; $k = Agent-Get $script:C '/contact'
      Judge $t $k (Agent-Get $script:C '/automation')
      $c = P $k 'contact'
      if (-not $c -or (P $c 'id') -ne $script:ContactId -or (P $c 'state') -in $Ended) { Say "contact ended: $(P $c 'state')"; return }
      if ((Qso-Now) -ge $deadline) { Note "the contact at $(P $c 'state') did not end within 10 minutes"; return }
    }
  }
  $script:AbortSent = [bool](Contact-Command 'abort' @{})
  if ($script:Backstop) { Note "contact $($script:ContactId) aborted at the backstop at ${state}: it stays unlogged" }
}
# Halt only while PTT is still keyed. Without an abort of its own the send on the air (a 73 of
# a contact that ended on its own) is let finish first, at most one period.
function Halt-If-Keyed {
  $t = Agent-Get $script:C '/transmit'
  if (-not $script:AbortSent) {
    $deadline = (Qso-Now) + (Period-Ms)
    while ((P $t 'transmitting') -eq $true -and (Qso-Now) -lt $deadline) { Qso-Sleep $PollMs; $t = Agent-Get $script:C '/transmit' }
  }
  if ((P $t 'ptt') -ne 'released') {
    $ptt = P $t 'ptt'
    if (Post-Command '/transmit/halt' 'halt' (Transmit-Envelope)) { $script:HaltSent = $true }
    Say "Halt sent: PTT was $ptt"
  }
}
function Set-Back {
  if (-not $script:Touched -or -not $script:Before) { return }
  if (-not (Contact-Command 'set_hold_tx' @{ enabled = [bool]$script:Before.hold }) -and $script:ProfileLost) { return }
  [void](Contact-Command 'set_frequency' @{ rx_hz = $script:Before.rx; tx_hz = $script:Before.tx })
  $k = Agent-Get $script:C '/contact'
  $script:After = [ordered]@{ hold_tx = (P $k 'settings.hold_tx'); rx_hz = (P $k 'settings.rx_hz'); tx_hz = (P $k 'settings.tx_hz') }
  Say "set back: hold_tx $($script:After.hold_tx), rx_hz $($script:After.rx_hz), tx_hz $($script:After.tx_hz)"
  if ($script:After.hold_tx -ne $script:Before.hold -or $script:After.rx_hz -ne $script:Before.rx -or $script:After.tx_hz -ne $script:Before.tx) {
    Note "THE SETTINGS DO NOT READ AS BEFORE (hold_tx $($script:Before.hold), rx_hz $($script:Before.rx), tx_hz $($script:Before.tx))"
  }
}

# --- Main ---
if (-not $Holder -or $Issue -notmatch '^[0-9]+$' -or $Item -notmatch '^[A-Za-z0-9._-]+$') {
  Write-Output 'QSO-TEST ERROR need -Holder <run>, -Issue <number> and -Item <acceptance item>'; exit 2
}
if (-not $Station) { $Station = Join-Path $env:LOCALAPPDATA 'WstxRust\station' }
if (-not $StateDir) { $StateDir = Join-Path (git -C $PSScriptRoot rev-parse --path-format=absolute --git-common-dir) 'harness-parallel\radio' }
# The repository root is three folders above tools/test/powershell/.
if (-not $AgentClient) { $AgentClient = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\tools\deploy\agent-client.ps1')) }
if (-not $Preflight) { $Preflight = Join-Path $PSScriptRoot 'radio-preflight.ps1' }
[void][IO.Directory]::CreateDirectory($StateDir)
$records = Join-Path $StateDir 'qso-tests.jsonl'

# The profile guard: SIM-IC7300's id and CAT port, read as station-switch.ps1 reads them.
$profilePath = Join-Path $Station "profiles\$SimProfile\profile.json"
try {
  $sim = [IO.File]::ReadAllText($profilePath) | ConvertFrom-Json
  $script:SimId = [string](P $sim 'profile_id'); $script:Own = [string](P $sim 'callsign'); $endpoint = [string](P $sim 'control.endpoint')
} catch { Write-Output "QSO-TEST ERROR cannot read $profilePath ($($_.Exception.Message)): nothing touched"; exit 2 }
$m = [regex]::Match($endpoint, '^icom7300://(COM[1-9][0-9]{0,2})\?(?:[^#]*&)?baud=([1-9][0-9]{2,6})(?:&|$)')
if (-not $m.Success -or -not $script:SimId -or -not $script:Own) { Write-Output "QSO-TEST ERROR the endpoint '$endpoint' of $SimProfile does not parse (icom7300://COM<n>?baud=<n>…): nothing touched"; exit 2 }
if ($m.Groups[1].Value -eq 'COM3') { Write-Output "QSO-TEST ERROR $SimProfile names COM3, the real IC-7300's port: agents key only the simulator; nothing touched"; exit 2 }
$script:Port = $m.Groups[1].Value; $script:Baud = $m.Groups[2].Value

. $AgentClient
$script:C = Open-AgentSession
$t0 = Agent-Get $script:C '/transmit'
if ((P $t0 'profile_id') -ne $script:SimId) {
  Write-Output "QSO-TEST ERROR the station runs profile $(P $t0 'profile_id'), not $SimProfile ($($script:SimId)): agents key only the simulator; nothing touched"; exit 2
}
$radio = [string](P $t0 'profile_id')

# The deployed revision: exactly one x-wstx-source-commit of 40 lowercase hex.
try { $reported = @(Qso-Revision $script:C | Where-Object { $null -ne $_ }) }
catch { Write-Output "QSO-TEST ERROR GET / of the station failed ($($_.Exception.Message)): nothing touched"; exit 2 }
if ($reported.Count -ne 1 -or [string]$reported[0] -cnotmatch '^[0-9a-f]{40}$') {
  Write-Output "QSO-TEST ERROR the station reports no deployed revision (x-wstx-source-commit: $(if ($reported.Count) { "'$($reported -join "', '")'" } else { 'none' })): a live acceptance runs only on a deployed revision; nothing touched"; exit 2
}
$revision = [string]$reported[0]

# Attempts of this item on this revision and radio: a 4th is refused. A record of another
# revision or radio, or one without a revision, does not count.
$attempt = 1
if (Test-Path -LiteralPath $records) {
  foreach ($line in [IO.File]::ReadAllLines($records)) {
    if (-not $line.Trim()) { continue }
    $r = $line | ConvertFrom-Json
    if ([string](P $r 'issue') -eq $Issue -and [string](P $r 'item') -eq $Item -and [string](P $r 'revision') -ceq $revision -and [string](P $r 'radio') -ceq $radio) { $attempt++ }
  }
}
$shortRev = $revision.Substring(0, 9)
if ($attempt -gt $Attempts) {
  Write-Output "QSO-TEST REFUSED #$Issue item $Item has had $Attempts attempts on revision $shortRev and radio ${radio}: a 4th is the operator's decision; ask the operator"; exit 4
}
Say "#$Issue item $Item, attempt $attempt of $Attempts on revision $shortRev and radio ${radio}: $SimProfile on $($script:Port) at $($script:Baud), own call $($script:Own)"

try {
  $script:TxCalls = [int](P $t0 'watchdog.tx_calls')
  if ($script:TxCalls -gt $TxCallsMax) { Not-Tested "the Tx watchdog is $($script:TxCalls) calls, above ${TxCallsMax}: not keyed (the driver never sets it)" }
  $k0 = Agent-Get $script:C '/contact'
  $script:Before = @{ hold = P $k0 'settings.hold_tx'; rx = P $k0 'settings.rx_hz'; tx = P $k0 'settings.tx_hz' }
  Say "before: hold_tx $($script:Before.hold), rx_hz $($script:Before.rx), tx_hz $($script:Before.tx)"
  $p0 = P $t0 'transmit.last_period_utc'; if ($null -ne $p0) { [void]$script:Seen.Add([long]$p0) }
  [void](Get-Transmit)
  Power $KeyPower
  [void](Get-Transmit)
  Swr-Key
  Power $QsoPower
  $script:T255 = Qso-Now
  $t = Get-Transmit; $p = P $t 'transmit.last_period_utc'; if ($null -ne $p) { [void]$script:Seen.Add([long]$p) }; $script:Prev = $t
  Run-Qso
} catch {
  if ($_.Exception.Message -ne 'QSO-END') { [void]$script:NotTested.Add("driver error: $($_.Exception.Message)"); Say "driver error: $($_.Exception.Message)" }
}
Stop-Order

$verdict = if ($script:Wrong.Count -or $script:Backstop) { 'failed' } elseif ($script:NotTested.Count -or -not $script:Passed) { 'not_tested' } else { 'passed' }
if ($verdict -eq 'not_tested' -and -not $script:NotTested.Count) { [void]$script:NotTested.Add('no QSO reached the pass conditions') }
if ($verdict -eq 'not_tested' -and $attempt -ge $Attempts) { [void]$script:AskOperator.Add("#$Issue item $Item left not tested $attempt times on revision $shortRev and radio $radio") }
$record = [ordered]@{
  time = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
  issue = $Issue; item = $Item; holder = $Holder; revision = $revision; radio = $radio; attempt = $attempt; verdict = $verdict
  wrong_actions = @($script:Wrong); backstop = $script:Backstop; not_tested = @($script:NotTested)
  last_disarm_cause = $script:Cause; failure = $script:Failure; refusal = $script:Refusal
  observations = @($script:Notes); ask_operator = @($script:AskOperator)
  profile_id = $script:SimId; port = $script:Port; baud = [int]$script:Baud
  swr_x10 = $script:Swr; po_pct = @($script:Po); target = $script:Target; contact_id = $script:ContactId
  transmissions = @($script:Sent); before = $script:Before; after = $script:After
}
[IO.File]::AppendAllText($records, (([pscustomobject]$record | ConvertTo-Json -Compress -Depth 6) + "`n"))
foreach ($ask in $script:AskOperator) { Write-Output "ASK THE OPERATOR: $ask" }
$reasons = @(@($script:Wrong) + @($script:NotTested)) -join '; '
switch ($verdict) {
  'passed' { Write-Output "QSO-TEST PASSED #$Issue item $Item, contact $($script:ContactId)"; exit 0 }
  'failed' { Write-Output "QSO-TEST FAILED #$Issue item ${Item}: $(if ($script:Backstop) { 'the backstop; ' })$reasons"; exit 1 }
  default { Write-Output "QSO-TEST NOT-TESTED #$Issue item ${Item}: $reasons"; exit 3 }
}
