#Requires -Version 7
<#
.SYNOPSIS
    Writes the commits in work\ back out as patches\, and any overlay files
    edited in work\ back to overlay\.

.DESCRIPTION
    The other half of bin\prepare-source.ps1. After changing the port in work\
    -- resolving a conflict, adjusting a patch, rewriting one from PORT.md --
    commit there, one commit per concern, then run this. patches\ is replaced
    wholesale with one file per commit on top of the upstream base.

    The base is the ref prepare-source.ps1 last checked out, so after
    preparing against a newer upstream tag the patches come out rebased onto
    it. Bumping UPSTREAM_VERSION to match is left to the caller.

    Refuses to export a half-finished state: a paused `git am`, uncommitted
    changes to upstream files, a merge commit, or a patch that creates a file
    (new files belong in overlay\, so that patches only ever touch upstream's).

.EXAMPLE
    pwsh -File bin\export-patches.ps1
#>
[CmdletBinding()]
param(
    [string]$WorkDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if (-not $WorkDir) { $WorkDir = Join-Path $root 'work' }
$overlay    = Join-Path $root 'overlay'
$patchesDir = Join-Path $root 'patches'

function Get-Git {
    $out = & git -C $WorkDir @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed ($LASTEXITCODE)" }
    $out
}

$baseFile = Join-Path $WorkDir '.git/omacut-windows-base'
if (-not (Test-Path $baseFile)) { throw "No prepared tree in $WorkDir -- run bin/prepare-source.ps1 first" }
$base = (Get-Content $baseFile -Raw).Trim()

if (Test-Path (Join-Path $WorkDir '.git/rebase-apply')) {
    throw 'git am is still paused in work/. Finish it (git -C work am --continue) before exporting.'
}
# Tracked files only: the overlay copies are untracked by design.
$dirty = Get-Git status --porcelain --untracked-files=no
if ($dirty) { throw "Uncommitted changes to upstream files in work/ -- commit them first:`n$($dirty -join "`n")" }
if (Get-Git rev-list --merges "$base..HEAD") { throw "Merge commits in $base..HEAD cannot be exported as patches" }
$added = Get-Git diff --name-only --diff-filter=A $base HEAD
if ($added) {
    throw "Patches may only change upstream's files. Move these into overlay/ instead:`n$($added -join "`n")"
}

# Overlay files edited in work/ go back where they live.
foreach ($file in Get-ChildItem -Path $overlay -Recurse -File) {
    $rel    = [IO.Path]::GetRelativePath($overlay, $file.FullName)
    $edited = Join-Path $WorkDir $rel
    if (-not (Test-Path $edited)) { continue }
    if ((Get-FileHash $edited).Hash -ne (Get-FileHash $file.FullName).Hash) {
        Copy-Item $edited -Destination $file.FullName -Force
        Write-Host "overlay: kept the edit to $($rel -replace '\\', '/')"
    }
}

# Untracked files that are neither overlay nor build output are probably new
# port files that were meant for overlay/.
$overlayRel = Get-ChildItem -Path $overlay -Recurse -File |
              ForEach-Object { [IO.Path]::GetRelativePath($overlay, $_.FullName) -replace '\\', '/' }
foreach ($stray in Get-Git ls-files --others --exclude-standard) {
    if ($stray -notin $overlayRel) { Write-Warning "work/$stray is untracked and not in overlay/ -- it will not be kept" }
}

Get-ChildItem -Path $patchesDir -Filter '*.patch' -File | Remove-Item
# --zero-commit and --no-signature drop the two lines that would otherwise
# change on every export; --full-index keeps the blob ids `git am --3way` needs.
Get-Git format-patch --quiet --zero-commit --no-signature --no-numbered --full-index `
    --output-directory $patchesDir "$base..HEAD" | Out-Null

$written = @(Get-ChildItem -Path $patchesDir -Filter '*.patch' -File | Sort-Object Name)
Write-Host "Exported $($written.Count) patch(es) against upstream ${base}:"
$written | ForEach-Object { Write-Host "  $($_.Name)" }
