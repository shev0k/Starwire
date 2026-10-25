<#
.SYNOPSIS
The iOS app's microphone code (StarwireKit) against the real Windows receiver, on this PC's
loopback.

.DESCRIPTION
Builds the receiver (windows/StarwireMicReceiver.cs and SecureMic.cs) into a temporary folder, as
windows/tests/e2e-loopback.ps1 does, and starts it with --console --loopback on a test port, its
own paired devices file, and an audio output that doesn't exist, so nothing is heard and an
installed receiver is never touched. Then StarwireKit's SwmcLoopback pairs with the code the
receiver prints, starts a session and streams a quiet tone in real time, followed by a replayed
and a plain VBAN packet. When the receiver stops by itself, its summary must say every packet
played, in order, with the same PCM, and that the two extra packets were refused.

This checks the Swift code the app uses against the receiver's C#, beyond the shared vectors. It
doesn't check the iPad's network path (that is the hands-on test).

    powershell -NoProfile -ExecutionPolicy Bypass -File ios\scripts\mic-loopback.ps1

Exits with 1 if anything fails.

.PARAMETER Port
The test receiver's UDP port. Default 6995, so it never meets the usual 6980.

.PARAMETER Packets
How many audio packets to send (187.5 make a second). Default 375.

.PARAMETER OutDir
Where the builds and logs go. Default: a folder in TEMP.
#>
param(
    [ValidateRange(1024, 65535)][int]$Port = 6995,
    [ValidateRange(10, 5000)][int]$Packets = 375,
    [string]$OutDir = (Join-Path $env:TEMP 'starwire-ios-mic-loopback')
)

$ErrorActionPreference = 'Stop'
$scripts = Split-Path -Parent $PSCommandPath
$repo = Split-Path -Parent (Split-Path -Parent $scripts)
$windows = Join-Path $repo 'windows'
New-Item -ItemType Directory -Force $OutDir | Out-Null

Write-Host '== Building StarwireKit''s SwmcLoopback' -ForegroundColor Cyan
$built = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'swift-test.ps1') `
    -Product SwmcLoopback -ScratchPath (Join-Path $OutDir 'swift')
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL building SwmcLoopback' -ForegroundColor Red; exit 1 }
$sender = ($built | Select-Object -Last 1).Trim()

Write-Host '== Building the receiver' -ForegroundColor Cyan
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe = Join-Path $OutDir 'StarwireMicReceiver.exe'
& $csc /nologo /optimize /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Security.dll "/out:$exe" `
    (Join-Path $windows 'StarwireMicReceiver.cs') (Join-Path $windows 'SecureMic.cs')
if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL building the receiver' -ForegroundColor Red; exit 1 }

$stamp = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$pairings = Join-Path $OutDir "pairings-$stamp.dat"
$log = Join-Path $OutDir "receiver-$stamp.txt"
$empty = Join-Path $OutDir 'empty.txt'
Set-Content -Path $empty -Value '' -Encoding Ascii
Write-Host "== Starting the test receiver on UDP $Port (loopback only, no audio output)" -ForegroundColor Cyan
$receiver = Start-Process -FilePath $exe -PassThru -WindowStyle Hidden `
    -ArgumentList @('--console', '--loopback', '--port', $Port, '--pairings-file', "`"$pairings`"", '--pair', '--exit-after-idle', '5',
        '--device', '"Starwire iOS loopback (no such output)"') `
    -RedirectStandardOutput $log -RedirectStandardError (Join-Path $OutDir "receiver-$stamp-errors.txt") -RedirectStandardInput $empty
$code = $null
for ($i = 0; $i -lt 150 -and -not $code; $i++) {
    Start-Sleep -Milliseconds 100
    if (Test-Path $log) {
        $line = Get-Content $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Pairing code: ([0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4})' } | Select-Object -First 1
        if ($line) { $code = $Matches[1] }
    }
    if ($receiver.HasExited) { break }
}
if (-not $code) {
    Write-Host 'FAIL the receiver printed no pairing code' -ForegroundColor Red
    if (-not $receiver.HasExited) { Stop-Process -Id $receiver.Id -Force }
    exit 1
}

Write-Host '== Pairing and streaming from StarwireKit' -ForegroundColor Cyan
$sent = & $sender $Port $code $Packets
$senderCode = $LASTEXITCODE
$sent | ForEach-Object { "  sender: $_" }

if (-not $receiver.WaitForExit(20000)) {
    Stop-Process -Id $receiver.Id -Force
    Write-Host 'FAIL the receiver did not stop by itself' -ForegroundColor Red
    exit 1
}
$lines = Get-Content $log
$lines | ForEach-Object { "  receiver: $_" }
Remove-Item $pairings -ErrorAction SilentlyContinue

$summary = $lines | Where-Object { $_ -like 'Summary: *' } | Select-Object -Last 1
$expect = $sent | Where-Object { $_ -like 'SENT *' } | Select-Object -Last 1
if ($senderCode -ne 0 -or -not $summary -or -not $expect) {
    Write-Host 'FAIL no summary from the receiver or the sender' -ForegroundColor Red
    exit 1
}
$v = @{}
foreach ($pair in ($expect -replace '^SENT ', '') -split ' ') { $k, $val = $pair -split '='; $v[$k] = $val }
$failed = @()
if ($summary -notlike "Summary: played $($v['played']),*") { $failed += "played (wanted $($v['played']))" }
if ($summary -notlike "*replayed or late $($v['replayed_or_late']),*") { $failed += 'the replayed packet' }
if ($summary -notlike "*unencrypted $($v['unencrypted']),*") { $failed += 'the plain VBAN packet' }
if ($summary -notlike "*forged 0,*" -or $summary -notlike "*errors 0,*") { $failed += 'forged or errors' }
if ($summary -notlike "*PCM fnv1a64 $($v['pcm'])") { $failed += 'the PCM' }
if ($failed.Count -gt 0) {
    Write-Host "FAIL $($failed -join '; ')" -ForegroundColor Red
    Write-Host "  sender:   $expect"
    Write-Host "  receiver: $summary"
    exit 1
}
Write-Host 'PASS every packet StarwireKit sealed played in order with the same PCM; the replay and the plain VBAN packet were refused' -ForegroundColor Green
exit 0
