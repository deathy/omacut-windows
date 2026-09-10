#Requires -Version 5.1
<#
.SYNOPSIS
    Turns a built omacut.exe into a self-contained, zipped Windows release.

.DESCRIPTION
    Collects the executable, the Qt runtime it needs (via windeployqt), a
    bundled ffmpeg, and the licences all of that obliges us to ship. Local
    builds and CI both go through here, so what you test is what ships.

.EXAMPLE
    pwsh -File bin\package-windows.ps1 -Version v0.4.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir,
    [string]$OutDir,
    [switch]$SkipFfmpeg
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if (-not $BuildDir) { $BuildDir = Join-Path $root 'build' }
if (-not $OutDir)   { $OutDir   = Join-Path $root 'dist' }

$name  = "omacut-$Version-win64"
$stage = Join-Path $OutDir $name

# The MSVC mkspec keeps debug_and_release on, so the binary may be in build\ or
# build\release\. Take the newest, ignoring anything already staged.
$exe = Get-ChildItem -Path $BuildDir -Recurse -File -Filter 'omacut.exe' -ErrorAction SilentlyContinue |
       Where-Object { $_.FullName -notlike "$OutDir*" } |
       Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { throw "No omacut.exe found under $BuildDir -- build it first" }
Write-Host "Packaging $($exe.FullName)"

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

Copy-Item $exe.FullName -Destination $stage -Force
Copy-Item (Join-Path $root 'LICENSE')         -Destination (Join-Path $stage 'LICENSE.txt')     -Force
Copy-Item (Join-Path $root 'THIRD-PARTY.md')  -Destination (Join-Path $stage 'THIRD-PARTY.md')  -Force
# THIRD-PARTY.md points at these by name, so they have to travel with it.
Get-ChildItem -Path (Join-Path $root 'licenses') -File |
    ForEach-Object { Copy-Item $_.FullName -Destination $stage -Force }

$windeployqt = Get-Command 'windeployqt' -ErrorAction SilentlyContinue
if (-not $windeployqt) { throw "windeployqt was not found on the PATH" }
& $windeployqt.Source --release --qmldir (Join-Path $root 'src') `
    --no-translations --no-system-d3d-compiler --no-compiler-runtime `
    (Join-Path $stage 'omacut.exe')
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed ($LASTEXITCODE)" }

# omacut is built with MSVC, so it needs the Visual C++ runtime. windeployqt
# would drop in vc_redist.x64.exe -- 25 MB of installer the user still has to
# run by hand. Copying the DLLs themselves is ~600 KB and just works.
$redistRoot = $env:VCToolsRedistDir
if ($redistRoot -and (Test-Path $redistRoot)) {
    $crt = Get-ChildItem -Path (Join-Path $redistRoot 'x64') -Directory -Filter 'Microsoft.VC*.CRT' `
             -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($crt) {
        Get-ChildItem -Path $crt.FullName -File -Filter '*.dll' |
            ForEach-Object {
                Copy-Item $_.FullName -Destination $stage -Force
                Write-Host "  runtime: $($_.Name)"
            }
    } else {
        Write-Warning "No Microsoft.VC*.CRT folder under $redistRoot"
    }
} else {
    Write-Warning 'VCToolsRedistDir is not set; the VC++ runtime will not be bundled.'
}

if (-not $SkipFfmpeg) {
    & (Join-Path $PSScriptRoot 'fetch-ffmpeg.ps1') -Destination $stage
}

# Fail loudly rather than shipping a zip that cannot possibly run.
foreach ($required in @('omacut.exe', 'Qt6Core.dll', 'Qt6Quick.dll', 'Qt6Multimedia.dll',
                        'LICENSE.txt', 'THIRD-PARTY.md', 'LGPL-3.0.txt', 'GPL-3.0.txt')) {
    if (-not (Test-Path (Join-Path $stage $required))) { throw "Missing $required in the staged folder" }
}
if ($redistRoot) {
    # Without these the executable will not start on a machine that has no
    # Visual C++ runtime installed, and the failure gives the user nothing.
    foreach ($required in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
        if (-not (Test-Path (Join-Path $stage $required))) { throw "Missing $required in the staged folder" }
    }
}
if (-not $SkipFfmpeg) {
    foreach ($required in @('ffmpeg.exe', 'ffprobe.exe', 'FFMPEG-LICENSE.txt')) {
        if (-not (Test-Path (Join-Path $stage $required))) { throw "Missing $required in the staged folder" }
    }
}

$zip = Join-Path $OutDir "$name.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $zip
Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ''
Write-Host "Packaged: $zip ($mb MB)"
