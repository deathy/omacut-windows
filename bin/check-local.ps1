#Requires -Version 7
<#
.SYNOPSIS
    Runs what CI runs, on this machine: assemble the source, build omacut and
    both test suites, run the tests, and package the zip.

.DESCRIPTION
    The local twin of .github/workflows/build.yml, for checking a change --
    or a newer upstream tag, with -Ref -- before pushing it. Needs MSVC (found
    with vswhere; no special prompt required, and it brings CMake and Ninja),
    Qt 6 with Qt Multimedia, and ffmpeg on the PATH for the tests.

    Exits non-zero if anything fails to build or any test fails. Test output
    goes to build\test-logs\*.txt, the same way CI collects it.

.EXAMPLE
    pwsh -File bin\check-local.ps1

.EXAMPLE
    pwsh -File bin\check-local.ps1 -Ref v0.7.0
#>
[CmdletBinding()]
param(
    [string]$QtDir = 'C:\Qt\6.8.1\msvc2022_64',
    # Upstream tag to check against. Defaults to UPSTREAM_VERSION.
    [string]$Ref,
    # Build work\ as it stands, e.g. mid-way through resolving a conflict.
    [switch]$SkipPrepare,
    [switch]$SkipPackage
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root  = Split-Path -Parent $PSScriptRoot
$work  = Join-Path $root 'work'
$build = Join-Path $root 'build'

# The MSVC environment, the same one vcvars64.bat sets up in a Native Tools
# prompt, imported into this process so every step below inherits it.
if (-not (Get-Command 'cl' -ErrorAction SilentlyContinue)) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found -- is Visual Studio installed?' }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vs) { throw 'No Visual Studio with the x64 C++ tools found' }
    $vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    & cmd.exe /d /s /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
    }
    if (-not (Get-Command 'cl' -ErrorAction SilentlyContinue)) { throw "vcvars64.bat did not put cl on the PATH ($vcvars)" }
}

if (-not (Test-Path (Join-Path $QtDir 'lib\cmake\Qt6'))) { throw "No Qt 6 under $QtDir -- pass -QtDir" }
$env:PATH = (Join-Path $QtDir 'bin') + [IO.Path]::PathSeparator + $env:PATH
if (-not (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)) { throw 'ffmpeg is not on the PATH; the tests need it' }

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Host ''
    Write-Host "== $Name" -ForegroundColor Cyan
    & $Body
}

if (-not $SkipPrepare) {
    Invoke-Step 'Prepare source' {
        $prepareArgs = @{}
        if ($Ref) { $prepareArgs['Ref'] = $Ref }
        & (Join-Path $PSScriptRoot 'prepare-source.ps1') @prepareArgs
        if ($LASTEXITCODE -ne 0) { throw "prepare-source failed ($LASTEXITCODE)" }
    }
}

Invoke-Step 'Build omacut and the tests' {
    & (Join-Path $PSScriptRoot 'build-cmake.ps1') -BuildDir $build -WorkDir $work -QtDir $QtDir -Clean
}

$failed = @()
Invoke-Step 'Run tests' {
    # No desktop needed: offscreen is the platform plugin CI uses too.
    $env:QT_QPA_PLATFORM = 'offscreen'
    $logs = Join-Path $build 'test-logs'
    New-Item -ItemType Directory -Force -Path $logs | Out-Null
    foreach ($suite in 'omacut_tests', 'dialogfilepicker_tests') {
        $exe = Join-Path $build "$suite.exe"
        if (-not (Test-Path $exe)) { throw "No $suite.exe was built" }
        # QtTest's stdout is not reliable here, as on CI, so read its file log.
        $log = Join-Path $logs "$suite.txt"
        & $exe -o "$log,txt"
        $code = $LASTEXITCODE
        Get-Content $log | Where-Object { $_ -match '^(FAIL|XPASS|SKIP|Totals)|failure location' } |
            ForEach-Object { Write-Host "  $_" }
        if ($code -ne 0) { $script:failed += "$suite ($code)" }
    }
}

if (-not $SkipPackage) {
    Invoke-Step 'Package' {
        & (Join-Path $PSScriptRoot 'package-windows.ps1') -Version 'local-check'
    }
}

Write-Host ''
if ($failed.Count) {
    Write-Host "FAILED: $($failed -join ', ') -- full logs in build\test-logs\" -ForegroundColor Red
    exit 1
}
Write-Host 'All built, all tests passed.' -ForegroundColor Green
