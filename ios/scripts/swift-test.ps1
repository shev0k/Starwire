<#
.SYNOPSIS
Runs the StarwireKit tests (`swift test`) on Windows.

.DESCRIPTION
Swift for Windows links with Microsoft's tools, so `swift test` fails in a plain shell ("could not
find CLI tool `link`", or "unable to load standard library" without SDKROOT). This script enters
the Visual Studio developer shell for x64, takes SDKROOT and the Swift folders on PATH from the
user's environment (where the Swift installer puts them), then runs the tests. It changes
nothing outside ios/StarwireKit/.build.

Needs the Swift toolchain (winget install Swift.Toolchain) and Visual Studio 2022 or its Build
Tools with the C++ workload and a Windows SDK.

    powershell -NoProfile -ExecutionPolicy Bypass -File ios\scripts\swift-test.ps1

Exits with swift's exit code: 0 when every test passes.

.PARAMETER Filter
Runs only the tests whose names match, as `swift test --filter` does.

.PARAMETER ScratchPath
Builds in this folder instead of ios/StarwireKit/.build, so two runs at once don't wait on each
other's lock.
#>
param(
    [string]$Filter = '',
    [string]$ScratchPath = ''
)

$ErrorActionPreference = 'Stop'
$package = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'StarwireKit'

# The Visual Studio install that has the x64 C++ tools: vswhere knows, or the usual Build Tools
# folder.
$vs = $null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path $vswhere) {
    $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath | Select-Object -First 1
}
if (-not $vs) { $vs = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\2022\BuildTools' }
$devShell = Join-Path $vs 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
if (-not (Test-Path $devShell)) {
    Write-Error "No Visual Studio C++ tools found (looked for $devShell). Install Visual Studio 2022 Build Tools with the C++ workload."
}

if (-not $env:SDKROOT) { $env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT', 'User') }
if (-not $env:SDKROOT) { $env:SDKROOT = [Environment]::GetEnvironmentVariable('SDKROOT', 'Machine') }
if (-not $env:SDKROOT) { Write-Error 'SDKROOT is not set. Reinstall Swift, or set it to the Windows.sdk folder of the Swift install.' }

# Enter-VsDevShell runs vswhere from the installer folder, so that goes on PATH first.
$env:Path = (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer') + ';' + $env:Path
Import-Module $devShell
Enter-VsDevShell -VsInstallPath $vs -SkipAutomaticLocation -DevCmdArguments '-arch=x64 -host_arch=x64' | Out-Null
# The developer shell rebuilds PATH from the machine's, which may leave out the user's Swift folders.
$env:Path += ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    Write-Error 'swift is not on PATH. Install it with: winget install Swift.Toolchain'
}

$swiftArgs = @('test', '--package-path', $package)
if ($Filter) { $swiftArgs += @('--filter', $Filter) }
if ($ScratchPath) { $swiftArgs += @('--scratch-path', $ScratchPath) }
Write-Host "swift $($swiftArgs -join ' ')"
& swift @swiftArgs
exit $LASTEXITCODE
