#Requires -Version 7
<#
.SYNOPSIS
    Runs what CI runs, on this machine: assemble the source, build omacut,
    build and run both test suites, and package the zip.

.DESCRIPTION
    The local twin of .github/workflows/build.yml, for checking a change --
    or a newer upstream tag, with -Ref -- before pushing it. Needs MSVC (found
    with vswhere; no special prompt required), Qt 6 with Qt Multimedia, and
    ffmpeg on the PATH for the backend tests.

    Exits non-zero if anything fails to build or any test fails. Test output
    goes to build-tests\*.txt, the same way CI collects it.

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

$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root 'work'

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

if (-not (Test-Path (Join-Path $QtDir 'bin\qmake.exe'))) { throw "No qmake under $QtDir -- pass -QtDir" }
$env:PATH = (Join-Path $QtDir 'bin') + [IO.Path]::PathSeparator + $env:PATH
if (-not (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue)) { throw 'ffmpeg is not on the PATH; the backend tests need it' }

# jom is a drop-in parallel nmake; use it when it happens to be installed.
$make = (Get-Command 'jom' -ErrorAction SilentlyContinue) ?? (Get-Command 'nmake')

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Host ''
    Write-Host "== $Name" -ForegroundColor Cyan
    & $Body
}

function Build-Project([string]$Dir, [string]$Pro) {
    $path = Join-Path $root $Dir
    if (Test-Path $path) { Remove-Item -Recurse -Force $path }
    New-Item -ItemType Directory -Path $path | Out-Null
    Push-Location $path
    try {
        # Absolute .pro paths, as in CI: the QML tests find Main.qml through
        # __FILE__, which qmake only makes absolute when given one.
        & qmake $Pro
        if ($LASTEXITCODE -ne 0) { throw "qmake $Pro failed ($LASTEXITCODE)" }
        & $make.Source /nologo
        if ($LASTEXITCODE -ne 0) { throw "building $Pro failed ($LASTEXITCODE)" }
    } finally { Pop-Location }
}

if (-not $SkipPrepare) {
    Invoke-Step 'Prepare source' {
        $prepareArgs = @{}
        if ($Ref) { $prepareArgs['Ref'] = $Ref }
        & (Join-Path $PSScriptRoot 'prepare-source.ps1') @prepareArgs
        if ($LASTEXITCODE -ne 0) { throw "prepare-source failed ($LASTEXITCODE)" }
    }
}

Invoke-Step 'Build omacut' { Build-Project 'build' (Join-Path $work 'omacut-windows.pro') }
Invoke-Step 'Build tests' {
    Build-Project 'build-tests'        (Join-Path $work 'tests\backend_tests-windows.pro')
    Build-Project 'build-tests-picker' (Join-Path $work 'tests\dialogfilepicker_tests.pro')
}

$failed = @()
Invoke-Step 'Run tests' {
    # No desktop needed: offscreen is the platform plugin CI uses too.
    $env:QT_QPA_PLATFORM = 'offscreen'
    foreach ($dir in 'build-tests', 'build-tests-picker') {
        $exe = Get-ChildItem -Path (Join-Path $root $dir) -Recurse -File -Filter '*_tests.exe' |
               Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if (-not $exe) { throw "No test binary was built in $dir" }
        $log = Join-Path $root "build-tests\$($exe.BaseName).txt"
        # From the directory qmake ran in, as CI does. QtTest's stdout is not
        # reliable here either, so read its file log.
        Push-Location (Join-Path $root $dir)
        try { & $exe.FullName -o "$log,txt"; $code = $LASTEXITCODE } finally { Pop-Location }
        Get-Content $log | Where-Object { $_ -match '^(FAIL|XPASS|SKIP|Totals)|Loc:' } |
            ForEach-Object { Write-Host "  $_" }
        if ($code -ne 0) { $script:failed += "$($exe.Name) ($code)" }
    }
}

if (-not $SkipPackage) {
    Invoke-Step 'Package' {
        & (Join-Path $PSScriptRoot 'package-windows.ps1') -Version 'local-check'
    }
}

Write-Host ''
if ($failed.Count) {
    Write-Host "FAILED: $($failed -join ', ') -- full logs in build-tests\" -ForegroundColor Red
    exit 1
}
Write-Host 'All built, all tests passed.' -ForegroundColor Green
