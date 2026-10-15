#Requires -Version 7
<#
.SYNOPSIS
    Turns a built omacut.app into a self-contained, zipped macOS build.

.DESCRIPTION
    The macOS counterpart of package-windows.ps1, for the experimental macOS
    build (Apple silicon only). Takes the omacut.app qmake built, puts the Qt
    runtime inside it (macdeployqt), adds a bundled ffmpeg and the licences,
    signs it ad hoc, checks that nothing in it still points outside the
    bundle, and zips it with ditto -- which, unlike Compress-Archive, keeps the
    framework symlinks and the signature intact.

    Ad hoc signing is not Developer ID signing: it is the minimum an Apple
    silicon Mac needs to run the code at all, and Gatekeeper still blocks the
    app on first launch. README.md says how to let it through.

.EXAMPLE
    pwsh -File bin/package-macos.ps1 -Version v0.7.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BuildDir,
    [string]$OutDir,
    # The prepared tree -- upstream plus the port; see bin/prepare-source.ps1.
    [string]$SourceDir,
    [switch]$SkipFfmpeg,
    # Skip starting the packaged app to see that it comes up.
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsMacOS) { throw 'package-macos.ps1 runs on macOS only' }

$root = Split-Path -Parent $PSScriptRoot
if (-not $BuildDir)  { $BuildDir  = Join-Path $root 'build' }
if (-not $OutDir)    { $OutDir    = Join-Path $root 'dist' }
if (-not $SourceDir) { $SourceDir = Join-Path $root 'work' }

# No param block on purpose: an advanced function would try to bind the
# tool's own -flags as its parameters.
function Invoke-Native {
    $exe, $rest = $args
    & $exe @rest
    if ($LASTEXITCODE -ne 0) { throw "$exe $($rest -join ' ') failed ($LASTEXITCODE)" }
}

$built = Join-Path $BuildDir 'omacut.app'
if (-not (Test-Path $built)) { throw "No omacut.app in $BuildDir -- build it first" }
Write-Host "Packaging $built"

$name  = "omacut-$Version-macos-arm64"
$stage = Join-Path $OutDir $name
$app   = Join-Path $stage 'omacut.app'
$macos = Join-Path $app 'Contents/MacOS'
$res   = Join-Path $app 'Contents/Resources'
$fw    = Join-Path $app 'Contents/Frameworks'

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
# ditto, so a rebuilt bundle's symlinks come across as symlinks.
Invoke-Native ditto $built $app

$macdeployqt = Get-Command 'macdeployqt' -ErrorAction SilentlyContinue
if (-not $macdeployqt) { throw 'macdeployqt was not found on the PATH' }
Invoke-Native $macdeployqt.Source $app "-qmldir=$(Join-Path $SourceDir 'src')" -always-overwrite -verbose=1

if (-not $SkipFfmpeg) {
    & (Join-Path $PSScriptRoot 'fetch-ffmpeg-macos.ps1') -Destination $macos -InfoDir $res
}

# omacut's own licence, from the upstream tree this was built from, and what
# the bundled Qt and ffmpeg oblige us to ship. Inside the bundle, because the
# .app is what people keep.
Copy-Item (Join-Path $SourceDir 'LICENSE')   -Destination (Join-Path $res 'LICENSE.txt')    -Force
Copy-Item (Join-Path $root 'THIRD-PARTY.md') -Destination (Join-Path $res 'THIRD-PARTY.md') -Force
Get-ChildItem -Path (Join-Path $root 'licenses') -File |
    ForEach-Object { Copy-Item $_.FullName -Destination $res -Force }

# Every Mach-O file in the bundle, and what each one loads. A reference to
# the build machine (Qt's install, Homebrew) works here and nowhere else, and
# an @rpath one with nothing behind it fails only when it is first loaded --
# for the multimedia plugin, not until a video is opened.
$machO = @(& find $app -type f -exec file -F '|' '{}' + |
           Where-Object { $_ -match '\|\s*Mach-O' } |
           ForEach-Object { ($_ -split '\|', 2)[0] } |
           # A universal binary adds a "path (for architecture ...)" line per
           # slice; keep the real paths only.
           Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
           Select-Object -Unique)
if ($machO.Count -eq 0) { throw 'Found no Mach-O files in the bundle' }

$problems = @()
foreach ($bin in $machO) {
    $own  = Split-Path -Leaf $bin
    $deps = @(& otool -arch arm64 -L $bin 2>$null | Select-Object -Skip 1 |
              ForEach-Object { ($_.Trim() -split ' \(compatibility')[0] })
    if ($LASTEXITCODE -ne 0) { $problems += "$bin has no arm64 code"; continue }
    foreach ($dep in $deps) {
        if (-not $dep -or (Split-Path -Leaf $dep) -eq $own) { continue }   # its own install name
        if ($dep -match '^(/System/|/usr/lib/)') { continue }
        if ($dep -like '@rpath/*') {
            if (-not (Test-Path (Join-Path $fw $dep.Substring(7)))) {
                $problems += "$bin loads $dep, which is not in Contents/Frameworks"
            }
            continue
        }
        if ($dep -match '^@(executable|loader)_path/') { continue }
        $problems += "$bin loads $dep, outside the bundle"
    }
}
if ($problems) {
    $problems | ForEach-Object { Write-Host "  $_" }
    throw "The bundle is not self-contained ($($problems.Count) problem(s) above)"
}
Write-Host "Checked $($machO.Count) Mach-O files: every library is in the bundle or the OS"

# Everything was rewritten by macdeployqt, or added after it, so sign the lot
# again. --deep is fine for an ad hoc signature; Developer ID would want each
# piece signed inside out instead.
Invoke-Native codesign --force --deep --sign - $app
Invoke-Native codesign --verify --deep --strict --verbose=2 $app

foreach ($required in @('Contents/MacOS/omacut', 'Contents/Frameworks/QtCore.framework',
                        'Contents/Frameworks/QtQuick.framework', 'Contents/Frameworks/QtMultimedia.framework',
                        'Contents/PlugIns/multimedia', 'Contents/PlugIns/platforms/libqcocoa.dylib',
                        'Contents/Resources/LICENSE.txt', 'Contents/Resources/THIRD-PARTY.md',
                        'Contents/Resources/LGPL-3.0.txt', 'Contents/Resources/GPL-3.0.txt')) {
    if (-not (Test-Path (Join-Path $app $required))) { throw "Missing $required in the bundle" }
}
if (-not $SkipFfmpeg) {
    foreach ($required in @('Contents/MacOS/ffmpeg', 'Contents/MacOS/ffprobe', 'Contents/Resources/FFMPEG-BUILD.txt')) {
        if (-not (Test-Path (Join-Path $app $required))) { throw "Missing $required in the bundle" }
    }
    Invoke-Native (Join-Path $macos 'ffmpeg') -hide_banner -version | Select-Object -First 1
}

if (-not $SkipSmokeTest) {
    # Start the packaged app (offscreen, so it needs no display) and give it a
    # few seconds. Missing frameworks kill it at once; a QML import that
    # macdeployqt left out shows up as an error on stderr.
    $log = Join-Path $OutDir "$name-smoke.log"
    $env:QT_QPA_PLATFORM = 'offscreen'
    try {
        $proc = Start-Process -FilePath (Join-Path $macos 'omacut') -PassThru `
                    -RedirectStandardError $log -RedirectStandardOutput "$log.out"
        Start-Sleep -Seconds 8
        $exited = $proc.HasExited
        if (-not $exited) { $proc.Kill() ; $proc.WaitForExit() }
    } finally { Remove-Item Env:QT_QPA_PLATFORM }
    $output = (Get-Content $log, "$log.out" -Raw -ErrorAction SilentlyContinue) -join "`n"
    if ($output) { Write-Host $output }
    if ($exited) { throw "The packaged app exited on its own within seconds (code $($proc.ExitCode))" }
    if ($output -match 'is not installed|module ".*" plugin ".*" not found|Library not loaded|Cannot load library') {
        throw 'The packaged app came up with load errors (see above)'
    }
    Write-Host 'Smoke test: the packaged app started and stayed up'
}

$zip = Join-Path $OutDir "$name.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $zip
Invoke-Native ditto -c -k --sequesterRsrc --keepParent $app $zip

$mb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host ''
Write-Host "Packaged: $zip ($mb MB)"
