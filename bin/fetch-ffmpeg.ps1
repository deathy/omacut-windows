#Requires -Version 5.1
<#
.SYNOPSIS
    Puts ffmpeg.exe, ffprobe.exe and the DLLs they need into -Destination.

.DESCRIPTION
    omacut shells out to ffmpeg and ffprobe at runtime. On Linux that is a
    package dependency; on Windows there is nothing to depend on, so we fetch a
    known build and keep it next to the executable.

    The build is pinned by tag AND by hash. Bumping it means changing all three
    defaults together -- the hash is what makes the download verifiable, so
    never bump the tag alone.

    Source: https://github.com/BtbN/FFmpeg-Builds (GPL, because omacut encodes
    with libx264). See THIRD-PARTY.md for what that obliges us to ship.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [string]$Tag    = 'autobuild-2026-09-09-14-51',
    [string]$Asset  = 'ffmpeg-n9.0.1-27-g9b0578816c-win64-gpl-shared-9.0.zip',
    [string]$Sha256 = '26add2aceeba58279024dcb658bc6fd1a7f2c3914a89c5ca70e2d2784f34df57',
    [string]$CacheDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'omacut-ffmpeg-cache')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -ItemType Directory -Force -Path $CacheDir  | Out-Null
New-Item -ItemType Directory -Force -Path $Destination | Out-Null

$zip = Join-Path $CacheDir $Asset

function Test-Hash($path, $expected) {
    if (-not (Test-Path $path)) { return $false }
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash -ieq $expected
}

if (Test-Hash $zip $Sha256) {
    Write-Host "Using cached $Asset"
} else {
    $url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/$Tag/$Asset"
    Write-Host "Downloading $url"
    Remove-Item -Force -ErrorAction SilentlyContinue $zip
    # Progress rendering makes Invoke-WebRequest crawl on large files.
    $prior = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
    try   { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
    finally { $ProgressPreference = $prior }

    if (-not (Test-Hash $zip $Sha256)) {
        $got = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
        Remove-Item -Force -ErrorAction SilentlyContinue $zip
        throw "SHA256 mismatch for ${Asset}: expected $Sha256, got $got"
    }
}

$extract = Join-Path $CacheDir "extract-$Tag"
if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
Expand-Archive -Path $zip -DestinationPath $extract -Force

$bin = Get-ChildItem -Path $extract -Recurse -Directory -Filter 'bin' | Select-Object -First 1
if (-not $bin) { throw "No bin/ directory inside $Asset" }

# ffplay is a media player we never invoke; leaving it out saves ~19 MB.
Get-ChildItem -Path $bin.FullName -File |
    Where-Object { $_.Name -ne 'ffplay.exe' } |
    ForEach-Object { Copy-Item $_.FullName -Destination $Destination -Force }

$license = Get-ChildItem -Path $extract -Recurse -File -Filter 'LICENSE.txt' | Select-Object -First 1
if ($license) {
    Copy-Item $license.FullName -Destination (Join-Path $Destination 'FFMPEG-LICENSE.txt') -Force
} else {
    throw "No LICENSE.txt in $Asset -- refusing to ship a GPL binary without it"
}

# Record exactly what was shipped, so the GPL source offer names a real build.
@"
ffmpeg for Windows, bundled with omacut.

  Build:  $Asset
  Tag:    $Tag
  SHA256: $Sha256
  From:   https://github.com/BtbN/FFmpeg-Builds/releases/tag/$Tag

This is a GPL build of ffmpeg (it includes libx264). Its licence is in
FFMPEG-LICENSE.txt. Corresponding source, and the scripts used to build it,
are at https://github.com/BtbN/FFmpeg-Builds and https://github.com/FFmpeg/FFmpeg
(this build is tagged $Tag upstream).

ffmpeg is a separate program that omacut runs; omacut itself is MIT.
"@ | Set-Content -Path (Join-Path $Destination 'FFMPEG-BUILD.txt') -Encoding UTF8

Write-Host "ffmpeg ready in $Destination"
Get-ChildItem -Path $Destination -Filter '*.exe' | ForEach-Object { Write-Host "  $($_.Name)" }
