<#
.SYNOPSIS
Opens testufo.com full screen on the stream's virtual display, for the iOS device runs.

.DESCRIPTION
Vibeshine runs this as the "Starwire test pattern" app (see docs/ios/mac-runbook.md). The app is
set to "virtual-display-layout": "extended_isolated", so the PC's own monitors stay on and the
virtual display sits apart from them. This script finds that display (the one whose shape matches
the stream, from Vibeshine's SUNSHINE_CLIENT_WIDTH and SUNSHINE_CLIENT_HEIGHT, waiting up to 20 s for
it to appear and never using one of the PC's own monitors instead), and opens Chrome in
kiosk mode there with its own empty profile, so nothing on the PC's monitors is covered and no
tabs or bookmarks show. It waits for Chrome, so Vibeshine closes it when the stream's app quits.

Install: copy this file to %LOCALAPPDATA%\StarwireTestPattern\ and point the app's command at
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LOCALAPPDATA%\StarwireTestPattern\test-pattern.ps1"
#>

param(
    # What to show: testufo.com by default, or a page such as colour-bars.html next to this script
    [string]$Url = 'https://www.testufo.com'
)

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

# The stream's own display: the one the size of the stream. Vibeshine may still be setting it
# up when this starts, so wait for it. Never fall back to one of the PC's own monitors (with the
# monitors asleep, Windows lists only them or the virtual display): the window would cover the
# owner's screen. A physical-monitor stream at the stream's own size still works.
function Find-StreamScreen {
    $screens = [System.Windows.Forms.Screen]::AllScreens
    $sameSize = $screens | Where-Object { $_.Bounds.Width -eq $width -and $_.Bounds.Height -eq $height }
    # Only the exact size: a monitor of the same shape could be one of the PC's own
    $sameSize | Where-Object { -not $_.Primary } | Select-Object -First 1
}
$target = $null
for ($try = 0; $try -lt 40 -and -not $target; $try++) {
    $target = Find-StreamScreen
    if (-not $target) {
        $only = [System.Windows.Forms.Screen]::AllScreens
        if ($only.Count -eq 1 -and $only[0].Bounds.Width -eq $width -and $only[0].Bounds.Height -eq $height) {
            $target = $only[0]
        } else {
            Start-Sleep -Milliseconds 500
        }
    }
}
$screens = [System.Windows.Forms.Screen]::AllScreens
if (-not $target) {
    Write-Log ("stream {0}x{1}; screens: {2}; no display of the stream's size after 20 s, so nothing is opened" -f $width, $height,
        (($screens | ForEach-Object { "$($_.DeviceName) $($_.Bounds)" }) -join '; '))
    exit 0
}
$b = $target.Bounds
Write-Log ("stream {0}x{1}; screens: {2}; using {3} at {4},{5} {6}x{7}" -f $width, $height,
    (($screens | ForEach-Object { "$($_.DeviceName) $($_.Bounds)" }) -join '; '),
    $target.DeviceName, $b.X, $b.Y, $b.Width, $b.Height)

$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$arguments = @(
    '--kiosk', '--no-first-run', '--no-default-browser-check', '--disable-session-crashed-bubble',
    "--user-data-dir=`"$(Join-Path $root 'chrome')`"",
    "--window-position=$($b.X + 50),$($b.Y + 50)", "--window-size=800,600",
    $Url
)
$process = Start-Process -FilePath $chrome -ArgumentList $arguments -PassThru
$process.WaitForExit()
Write-Log "chrome exited"
