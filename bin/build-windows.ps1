#Requires -Version 7
<#
.SYNOPSIS
    Builds omacut for Windows and leaves a runnable folder under build\.

.DESCRIPTION
    Run this from a shell that already has MSVC on the PATH -- the simplest is
    the "x64 Native Tools Command Prompt for VS", which brings CMake and Ninja
    too -- with Qt's bin directory on the PATH, or passed as -QtDir.

    The source is assembled first (bin\prepare-source.ps1: upstream omacut at
    UPSTREAM_VERSION, plus overlay\ and patches\) into work\. Pass
    -SkipPrepare to build work\ as it stands, e.g. while changing a patch.

    ffmpeg is downloaded automatically, so there is nothing to install first.
    To build and run the tests as well, use bin\check-local.ps1.

.EXAMPLE
    pwsh -File bin\build-windows.ps1 -QtDir C:\Qt\6.8.1\msvc2022_64
#>
[CmdletBinding()]
param(
    [string]$QtDir,
    [switch]$SkipFfmpeg,
    [switch]$SkipPrepare,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root  = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$work  = Join-Path $root 'work'

if (-not $SkipPrepare) {
    & (Join-Path $PSScriptRoot 'prepare-source.ps1')
    if ($LASTEXITCODE -ne 0) { throw "prepare-source failed ($LASTEXITCODE)" }
}

if ($QtDir) { $env:PATH = (Join-Path $QtDir 'bin') + [IO.Path]::PathSeparator + $env:PATH }

$buildArgs = @{ BuildDir = $build; WorkDir = $work; Target = 'omacut' }
if ($QtDir) { $buildArgs['QtDir'] = $QtDir }
if ($Clean) { $buildArgs['Clean'] = $true }
& (Join-Path $PSScriptRoot 'build-cmake.ps1') @buildArgs

# Staging, the Qt runtime, ffmpeg and the licences all live in one place, so a
# local build and a release build produce the same folder.
$packageArgs = @{ Version = 'local'; BuildDir = $build; OutDir = $build; SourceDir = $work }
if ($SkipFfmpeg) { $packageArgs['SkipFfmpeg'] = $true }
& (Join-Path $PSScriptRoot 'package-windows.ps1') @packageArgs

$stage = Join-Path $build 'omacut-local-win64'
Write-Host ''
Write-Host "Run: $(Join-Path $stage 'omacut.exe')"
