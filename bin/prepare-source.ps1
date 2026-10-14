#Requires -Version 7
<#
.SYNOPSIS
    Assembles the source tree the Windows build compiles: upstream omacut at a
    tag, with overlay\ copied in and patches\ applied on top.

.DESCRIPTION
    This repository holds only what the port adds. The tree that actually gets
    built is put together here, in work\ (ignored by git):

      1. upstream omacut, checked out at -Ref (default: UPSTREAM_VERSION);
      2. every file under overlay\, copied in at the same relative path. These
         are files upstream does not have, so they never conflict -- and if
         upstream ever adds a file by the same name, this stops rather than
         overwrite it;
      3. every patches\*.patch, applied in order with `git am --3way`, one
         commit each. HEAD in work\ is therefore -Ref plus one commit per patch,
         and `git -C work log`, `git -C work diff <ref>` and friends show
         exactly what the port changes.

    work\ is rebuilt from scratch on every run. Anything changed there and not
    yet exported with bin\export-patches.ps1 is thrown away.

    When a patch does not apply, this stops with `git am` paused on it, so the
    conflict can be resolved in place. PORT.md walks through what to do next.

.EXAMPLE
    pwsh -File bin\prepare-source.ps1

.EXAMPLE
    pwsh -File bin\prepare-source.ps1 -Ref v0.7.0
#>
[CmdletBinding()]
param(
    # Upstream tag or commit to build on. Defaults to UPSTREAM_VERSION.
    [string]$Ref,
    [string]$Upstream = 'https://github.com/omacom/omacut.git',
    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if (-not $Ref)     { $Ref = (Get-Content (Join-Path $root 'UPSTREAM_VERSION') -Raw).Trim() }
if (-not $WorkDir) { $WorkDir = Join-Path $root 'work' }
$overlay = Join-Path $root 'overlay'
$patches = @(Get-ChildItem -Path (Join-Path $root 'patches') -Filter '*.patch' -File |
             Sort-Object Name)

function Invoke-Git {
    & git -C $WorkDir @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed ($LASTEXITCODE)" }
}

# A full clone, not a shallow one: `git am --3way` falls back on the blobs each
# patch names, and those only exist with upstream's history to hand.
if (-not (Test-Path (Join-Path $WorkDir '.git'))) {
    # The patches carry upstream's LF line endings; keep the tree they apply to
    # in LF too, whatever this machine's core.autocrlf says.
    & git clone --quiet --no-checkout --config core.autocrlf=false $Upstream $WorkDir
    if ($LASTEXITCODE -ne 0) { throw "Could not clone $Upstream" }
} else {
    # Left over from a run that stopped on a conflict.
    if (Test-Path (Join-Path $WorkDir '.git/rebase-apply')) { Invoke-Git am --abort }
    Invoke-Git remote set-url origin $Upstream
}
Invoke-Git fetch --quiet --tags --force origin

# git am commits as someone; this is not anyone's real identity, and none of it
# reaches the exported patches, which keep their own authors.
Invoke-Git config core.autocrlf false
Invoke-Git config user.name 'omacut-windows prepare-source'
Invoke-Git config user.email 'prepare-source@omacut-windows.invalid'

Invoke-Git -c advice.detachedHead=false checkout --quiet --force --detach "$Ref^{commit}"
Invoke-Git clean --quiet -fdx
# export-patches.ps1 reads this back, so it exports against the same base.
Set-Content -Path (Join-Path $WorkDir '.git/omacut-windows-base') -Value $Ref -NoNewline

# Overlay first, so a tree stopped on a conflicting patch is still complete
# enough to build and check a resolution against.
$copied = 0
foreach ($file in Get-ChildItem -Path $overlay -Recurse -File) {
    $rel  = [IO.Path]::GetRelativePath($overlay, $file.FullName)
    $dest = Join-Path $WorkDir $rel
    if (Test-Path $dest) {
        throw "overlay/$($rel -replace '\\', '/') would overwrite upstream's own file of that name. " +
              "Upstream has added it since; see PORT.md for what the port's file is for, and rename or merge it."
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
    Copy-Item $file.FullName -Destination $dest
    $copied++
}
Write-Host "Copied $copied overlay file(s) onto upstream $Ref"

if ($patches.Count) {
    & git -C $WorkDir am --quiet --3way @($patches.FullName)
    if ($LASTEXITCODE -ne 0) {
        $current = (& git -C $WorkDir am --show-current-patch=raw 2>$null |
                    Select-String -Pattern '^Subject: ' | Select-Object -First 1) -replace '^Subject: (\[PATCH\] )?', ''
        Write-Host ''
        Write-Host "A patch does not apply to upstream $Ref$(if ($current) { ": $current" })."
        Write-Host 'git am is paused on it in work/. Resolve it there, then:'
        Write-Host '    git -C work add <files>; git -C work am --continue    (repeat per patch)'
        Write-Host '    pwsh -File bin/export-patches.ps1'
        Write-Host 'PORT.md describes what each patch is for, if one is easier to redo than to rescue.'
        exit 1
    }
}
Write-Host "Applied $($patches.Count) patch(es). Source tree ready in $WorkDir"
