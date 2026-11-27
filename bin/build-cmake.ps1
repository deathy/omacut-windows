#Requires -Version 7
<#
.SYNOPSIS
    Configures and builds the prepared tree in work\ with CMake: omacut.exe and
    both test suites.

.DESCRIPTION
    Upstream builds with CMake. The port adjusts upstream's CMakeLists.txt from
    outside, through overlay\port\omacut-port.cmake, which this passes as
    CMAKE_PROJECT_INCLUDE (see PORT.md). Everything that builds the port --
    CI, releases, bin\check-local.ps1, bin\build-windows.ps1 -- goes through
    here, so they all build it the same way.

    Needs a compiler environment (on Windows, MSVC's: vcvars64.bat, or the
    "x64 Native Tools" prompt, which also puts CMake and Ninja on the PATH),
    and Qt 6 on the PATH or passed as -QtDir. Run bin\prepare-source.ps1 first.

.EXAMPLE
    pwsh -File bin\build-cmake.ps1

.EXAMPLE
    pwsh -File bin\build-cmake.ps1 -QtDir C:\Qt\6.8.1\msvc2022_64 -Target omacut
#>
[CmdletBinding()]
param(
    [string]$BuildDir,
    [string]$WorkDir,
    [string]$QtDir,
    # Targets to build; all of them (the app and both test suites) by default.
    [string[]]$Target,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if (-not $BuildDir) { $BuildDir = Join-Path $root 'build' }
if (-not $WorkDir)  { $WorkDir  = Join-Path $root 'work' }
$hook = Join-Path $WorkDir 'port/omacut-port.cmake'
if (-not (Test-Path $hook)) { throw "No $hook -- run bin/prepare-source.ps1 first" }

foreach ($tool in 'cmake', 'ninja') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool was not found on the PATH. On Windows, run this from an MSVC environment (vcvars64.bat)."
    }
}

if ($Clean -and (Test-Path $BuildDir)) { Remove-Item -Recurse -Force $BuildDir }

$configure = @(
    '-S', $WorkDir, '-B', $BuildDir, '-G', 'Ninja',
    # Upstream defaults to Release only when no build type is set, and CMake
    # sets Debug on its own for MSVC, so it has to be explicit.
    '-DCMAKE_BUILD_TYPE=Release',
    "-DCMAKE_PROJECT_INCLUDE=$hook"
)
if ($QtDir) { $configure += "-DCMAKE_PREFIX_PATH=$QtDir" }

& cmake @configure
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed ($LASTEXITCODE)" }

$build = @('--build', $BuildDir)
if ($Target) { $build += @('--target') + $Target }
& cmake @build
if ($LASTEXITCODE -ne 0) { throw "build failed ($LASTEXITCODE)" }
