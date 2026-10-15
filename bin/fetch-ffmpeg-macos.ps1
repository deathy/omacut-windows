#Requires -Version 7
<#
.SYNOPSIS
    Puts ffmpeg and ffprobe for Apple silicon Macs into -Destination.

.DESCRIPTION
    The macOS counterpart of fetch-ffmpeg.ps1, for the experimental macOS
    build. omacut looks for ffmpeg next to its executable first (PORT.md,
    "Prefer the bundled ffmpeg"), which inside omacut.app is Contents/MacOS.

    These are Martin Riedl's static builds: one self-contained binary each,
    linking nothing but system frameworks, so there are no dylibs to bundle
    or relocate. They need macOS 12 or later, which Qt 6.8 needs anyway.
    Release builds stay downloadable for years (back to 5.0, from 2022), so
    pinning one is safe -- but pin a *release*, never a snapshot.

    Pinned by build folder AND by hash, for each binary. Bumping it means
    changing all three defaults together; never bump the folder alone. The
    site publishes each zip's hash next to it as <zip>.sha256.

    Source: https://ffmpeg.martin-riedl.de (GPL v3, because omacut encodes
    with libx264). See THIRD-PARTY.md for what that obliges us to ship.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    # Where FFMPEG-BUILD.txt goes. Not Contents/MacOS: codesign takes
    # everything there for code, and refuses to sign a bundle with a text
    # file in it.
    [string]$InfoDir = $Destination,
    [string]$Build         = '1789931890_9.0.2',
    [string]$FfmpegSha256  = 'c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924',
    [string]$FfprobeSha256 = 'fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6',
    [string]$CacheDir = (Join-Path ([System.IO.Path]::GetTempPath()) 'omacut-ffmpeg-macos-cache')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

New-Item -ItemType Directory -Force -Path $CacheDir    | Out-Null
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
New-Item -ItemType Directory -Force -Path $InfoDir     | Out-Null

$base = "https://ffmpeg.martin-riedl.de/download/macos/arm64/$Build"

function Test-Hash($path, $expected) {
    if (-not (Test-Path $path)) { return $false }
    return (Get-FileHash -Path $path -Algorithm SHA256).Hash -ieq $expected
}

foreach ($tool in @(@{ Name = 'ffmpeg';  Sha256 = $FfmpegSha256 },
                    @{ Name = 'ffprobe'; Sha256 = $FfprobeSha256 })) {
    $zip = Join-Path $CacheDir "$($tool.Name)-$Build.zip"
    if (Test-Hash $zip $tool.Sha256) {
        Write-Host "Using cached $($tool.Name) $Build"
    } else {
        $url = "$base/$($tool.Name).zip"
        Write-Host "Downloading $url"
        Remove-Item -Force -ErrorAction SilentlyContinue $zip
        $prior = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
        try   { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
        finally { $ProgressPreference = $prior }

        if (-not (Test-Hash $zip $tool.Sha256)) {
            $got = (Get-FileHash -Path $zip -Algorithm SHA256).Hash
            Remove-Item -Force -ErrorAction SilentlyContinue $zip
            throw "SHA256 mismatch for $($tool.Name) ${Build}: expected $($tool.Sha256), got $got"
        }
    }

    # ditto rather than Expand-Archive: it keeps the executable bit, and the
    # code signature the binary arrives with.
    $out = Join-Path $Destination $tool.Name
    Remove-Item -Force -ErrorAction SilentlyContinue $out
    & ditto -x -k $zip $Destination
    if ($LASTEXITCODE -ne 0) { throw "Unpacking $zip failed ($LASTEXITCODE)" }
    if (-not (Test-Path $out)) { throw "No $($tool.Name) inside $zip" }
    & chmod +x $out
}

# Record exactly what was shipped, so the GPL source offer names a real build.
# These zips carry no licence file of their own; the build is configured with
# --enable-gpl --enable-version3, i.e. GPL v3, whose text ships as GPL-3.0.txt.
@"
ffmpeg and ffprobe for macOS (Apple silicon), bundled with omacut.

  Build:          $Build
  ffmpeg SHA256:  $FfmpegSha256  (ffmpeg.zip)
  ffprobe SHA256: $FfprobeSha256  (ffprobe.zip)
  From:           $base/

This is a static GPL v3 build of ffmpeg (it includes libx264); the licence
text is GPL-3.0.txt. Corresponding source is at https://github.com/FFmpeg/FFmpeg,
and the scripts used to build it at https://git.martin-riedl.de/ffmpeg/build-script.
'ffmpeg -buildconf' prints the exact configuration.

ffmpeg is a separate program that omacut runs; omacut itself is MIT.
"@ | Set-Content -Path (Join-Path $InfoDir 'FFMPEG-BUILD.txt') -Encoding UTF8

Write-Host "ffmpeg ready in $Destination"
