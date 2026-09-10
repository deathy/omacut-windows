#Requires -Version 5.1
<#
.SYNOPSIS
    Builds omacut for Windows and leaves a runnable folder under build\.

.DESCRIPTION
    Run this from a shell that already has MSVC on the PATH -- the simplest is
    the "x64 Native Tools Command Prompt for VS" -- with Qt's bin directory on
    the PATH too, or passed as -QtDir.

    ffmpeg is downloaded automatically, so there is nothing to install first.

.EXAMPLE
    pwsh -File bin\build-windows.ps1 -QtDir C:\Qt\6.8.1\msvc2022_64
#>
[CmdletBinding()]
param(
    [string]$QtDir,
    [switch]$SkipFfmpeg,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'

if ($Clean -and (Test-Path $build)) { Remove-Item -Recurse -Force $build }
New-Item -ItemType Directory -Force -Path $build | Out-Null

if ($QtDir) { $env:PATH = (Join-Path $QtDir 'bin') + [IO.Path]::PathSeparator + $env:PATH }

$qmake = Get-Command 'qmake' -ErrorAction SilentlyContinue
if (-not $qmake) { throw "qmake was not found on the PATH. Pass -QtDir, or add Qt's bin directory to the PATH." }

# jom is a drop-in parallel nmake; use it when it happens to be installed.
$make = Get-Command 'jom' -ErrorAction SilentlyContinue
if (-not $make) { $make = Get-Command 'nmake' -ErrorAction SilentlyContinue }
if (-not $make) { throw 'Neither jom nor nmake was found. Run this from an "x64 Native Tools" prompt.' }

Write-Host "qmake: $($qmake.Source)"
Write-Host "make:  $($make.Source)"

Push-Location $build
try {
    & $qmake.Source (Join-Path $root 'omacut.pro')
    if ($LASTEXITCODE -ne 0) { throw "qmake failed ($LASTEXITCODE)" }
    & $make.Source
    if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
} finally { Pop-Location }

# Staging, the Qt runtime, ffmpeg and the licences all live in one place, so a
# local build and a release build produce the same folder.
$packageArgs = @{ Version = 'local'; BuildDir = $build; OutDir = $build }
if ($SkipFfmpeg) { $packageArgs['SkipFfmpeg'] = $true }
& (Join-Path $PSScriptRoot 'package-windows.ps1') @packageArgs

$stage = Join-Path $build 'omacut-local-win64'
Write-Host ''
Write-Host "Run: $(Join-Path $stage 'omacut.exe')"
