# WSTX station launcher, run by the scheduled task "WSTX Rust Station HB9BLA" as HB9BLA
# (Limited). It starts the version named in station\active.json, so updating the station
# needs no administrator rights: stage the version, switch active.json, restart the task.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$base=Join-Path $env:LOCALAPPDATA 'WstxRust\station'
$active=Get-Content -LiteralPath (Join-Path $base 'active.json') -Raw | ConvertFrom-Json
if ($active.version -notmatch '^[0-9a-f]{9}$' -or $active.source_commit -notmatch '^[0-9a-f]{40}$' -or -not $active.source_commit.StartsWith($active.version)) { throw 'active.json is malformed.' }
$version=Join-Path $base $active.version;$exe=Join-Path $version 'wstx-rust.exe'
$secrets=Join-Path $base 'secrets'
$env:WSTX_TLS_CERT=Join-Path $secrets 'server.pem';$env:WSTX_TLS_KEY=Join-Path $secrets 'server.key.pem'
$env:WSTX_TOKEN=([IO.File]::ReadAllText((Join-Path $secrets 'access-token.txt'))).Trim()
$stationProfilePath=Join-Path $base 'profiles\ic7300';$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-ffff')
$child=Start-Process -FilePath $exe -ArgumentList @('--profile',('"'+$stationProfilePath+'"')) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $base ('logs\'+$stamp+'.stdout.log')) -RedirectStandardError (Join-Path $base ('logs\'+$stamp+'.stderr.log'))
$receipt=[ordered]@{source_commit=$active.source_commit;artifact_sha256=(Get-FileHash $exe).Hash.ToLower();executable=$exe;profile=$stationProfilePath;process_id=$child.Id;started_utc=$child.StartTime.ToUniversalTime().ToString('o');url='https://192.168.0.37:18081';scheduled_task='WSTX Rust Station HB9BLA';authentication='TLS and per-profile HttpOnly session cookie';firewall_client='192.168.0.6';launcher='active.json'}
# The scheduled task starts at Windows' default task priority (BelowNormal). The station
# does real-time audio capture and decoding, so it runs at High: otherwise builds and gates
# starve its capture queue (queue_full loss epochs, the receive restarting every second).
try { $child.PriorityClass=[Diagnostics.ProcessPriorityClass]::High } catch { }
[IO.File]::WriteAllText((Join-Path $base 'station-running.json'),($receipt|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$child.WaitForExit();exit $child.ExitCode
