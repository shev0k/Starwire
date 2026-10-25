<#
.SYNOPSIS
Opens testufo.com full screen on the stream's virtual display, for the iOS device runs.

.DESCRIPTION
Vibeshine runs this as the "Starwire test pattern" app (see docs/ios/mac-runbook.md). The app is
set to "virtual-display-layout": "extended_isolated", so the PC's own monitors stay on and the
virtual display sits apart from them. This script finds that display (the one whose shape matches
the stream, from Vibeshine's SUNSHINE_CLIENT_WIDTH and SUNSHINE_CLIENT_HEIGHT), and opens Chrome in
kiosk mode there with its own empty profile, so nothing on the PC's monitors is covered and no
tabs or bookmarks show. It waits for Chrome, so Vibeshine closes it when the stream's app quits.

Install: copy this file to %LOCALAPPDATA%\StarwireTestPattern\ and point the app's command at
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\StarwireTestPattern\test-pattern.ps1"
#>

$ErrorActionPreference = 'Stop'
$root = Join-Path $env:LOCALAPPDATA 'StarwireTestPattern'
$log = Join-Path $root 'test-pattern.log'
function Write-Log($text) { Add-Content -Path $log -Value ("{0:u} {1}" -f (Get-Date).ToUniversalTime(), $text) }

# Screen coordinates in real pixels, the same ones Chrome uses
Add-Type -Namespace Starwire -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(System.IntPtr value);'
[void][Starwire.Dpi]::SetProcessDpiAwarenessContext([IntPtr]-4)
Add-Type -AssemblyName System.Windows.Forms

$width = [double]($env:SUNSHINE_CLIENT_WIDTH, 16 | Where-Object { $_ } | Select-Object -First 1)
$height = [double]($env:SUNSHINE_CLIENT_HEIGHT, 10 | Where-Object { $_ } | Select-Object -First 1)
$aspect = $width / $height

# The virtual display: never the primary monitor, and the closest in shape to the stream. With
# no second display (a physical-monitor stream), fall back to the primary one.
$screens = [System.Windows.Forms.Screen]::AllScreens
$target = $screens | Where-Object { -not $_.Primary } |
    Sort-Object { [math]::Abs($_.Bounds.Width / $_.Bounds.Height - $aspect) } | Select-Object -First 1
if (-not $target) { $target = [System.Windows.Forms.Screen]::PrimaryScreen }
$b = $target.Bounds
Write-Log ("stream {0}x{1}; screens: {2}; using {3} at {4},{5} {6}x{7}" -f $width, $height,
    (($screens | ForEach-Object { "$($_.DeviceName) $($_.Bounds)" }) -join '; '),
    $target.DeviceName, $b.X, $b.Y, $b.Width, $b.Height)

$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$arguments = @(
    '--kiosk', '--no-first-run', '--no-default-browser-check', '--disable-session-crashed-bubble',
    "--user-data-dir=`"$(Join-Path $root 'chrome')`"",
    "--window-position=$($b.X + 50),$($b.Y + 50)", "--window-size=800,600",
    'https://www.testufo.com'
)
$process = Start-Process -FilePath $chrome -ArgumentList $arguments -PassThru
$process.WaitForExit()
Write-Log "chrome exited"
