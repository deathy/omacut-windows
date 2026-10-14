# omacut for Windows

An **unofficial Windows build** of [omacut](https://github.com/omacom/omacut) —
David Heinemeier Hansson's dead-simple video trimmer. Open a video, trim either
end, split it into clips and cut ranges out of the middle, preview, export.

All credit for omacut goes upstream. This repository contains **none of
omacut's code**, only the port: a small set of patches to upstream's files,
the few files the port adds, and the packaging. Each build applies them to
the upstream release named in [`UPSTREAM_VERSION`](UPSTREAM_VERSION).
[PORT.md](PORT.md) explains how that works and what every change is for.

## Install

Download the latest `omacut-*-win64.zip` from
[Releases](../../releases), unpack it anywhere, and run `omacut.exe`.

ffmpeg is bundled — there is nothing else to install.

> **SmartScreen will warn you on first run.** These builds are not code-signed
> (a certificate is a few hundred dollars a year). Choose *More info* →
> *Run anyway*. If you would rather not, build it yourself — see below.

Hotkeys and everything else about using omacut are in
[upstream's README](https://github.com/omacom/omacut#readme).

## How this differs from upstream

| | Upstream (Linux) | This build |
|---|---|---|
| File dialogs | xdg-desktop-portal over D-Bus | native Windows dialogs |
| Export quality | a "Quality" combo in the portal dialog | folded into the "Save as type" combo |
| Accent colour | follows your Omarchy theme | upstream's default amber |
| ffmpeg | a package dependency | bundled in the zip |

The accent difference is not a port decision — upstream already falls back to its
default when there is no Omarchy theme to read, which is every non-Omarchy
machine.

## What is in this repository

| Path | What it is |
|---|---|
| [`patches/`](patches) | the port's edits to upstream's files, one concern each |
| [`overlay/`](overlay) | files the port adds, copied into upstream's tree as-is |
| [`UPSTREAM_VERSION`](UPSTREAM_VERSION) | the upstream tag the patches apply to |
| [`PORT.md`](PORT.md) | what each change is for, and how to update or redo them |
| `bin/`, `.github/` | assembling, building, packaging and releasing |

`bin/prepare-source.ps1` puts the buildable tree together in `work/`: upstream
at `UPSTREAM_VERSION`, plus `overlay/`, plus `patches/`. It is a git
repository, so `git -C work diff v0.5.0` (say) shows everything the port
changes.

## Building it yourself

You need [Qt 6](https://www.qt.io/download-qt-installer) (with the Qt Multimedia
module), MSVC, git and PowerShell 7. From an *x64 Native Tools Command Prompt
for VS*:

```powershell
pwsh -File bin\build-windows.ps1 -QtDir C:\Qt\6.8.1\msvc2022_64
```

That assembles the source, builds it, gathers the Qt runtime, downloads ffmpeg,
and leaves a runnable folder in `build\omacut-local-win64\`. Pass `-SkipFfmpeg`
if you already have ffmpeg on your `PATH`.

The port also builds on macOS, which is a way to check it without a Windows
machine in the loop:

```sh
brew install qtbase qtdeclarative qtmultimedia powershell
pwsh -File bin/prepare-source.ps1
mkdir -p build && cd build && qmake ../work/omacut-windows.pro && make
```

## How releases track upstream

Releases here are tagged `win-v0.5.0` and so on, deliberately clear of
upstream's own `v0.5.0`. The version people see drops the prefix; a semver
suffix (`win-v0.5.0-alpha.1`) publishes as a pre-release.

A daily [workflow](.github/workflows/upstream-sync.yml) checks for a newer
upstream release and applies the patches to it. If they apply, it opens a pull
request with the patches re-exported against the new tag. If one does not, it
opens an issue instead. It never resolves a conflict on its own and never
publishes from one. PORT.md has the procedure for resolving one, and the
checklist for anything upstream changed that applies cleanly but still needs
the port's attention.

A green build is not a working app. Every sync PR carries a built artifact that
is meant to be run by a person on Windows before the PR is merged.

A sync normally arrives as a pull request. That needs *Allow GitHub Actions to
create and approve pull requests* under Settings → Actions → General, which is
off by default on a new repository and is already on here. If it is ever turned
off, the sync degrades rather than disappearing: it files an issue instead, and
failing that marks its own run failed with a compare link in the summary, so
the branch is never merged and forgotten.

> GitHub disables scheduled workflows after 60 days without repository activity.
> If syncs go quiet, re-enable it from the Actions tab.

## Licence

omacut is MIT, Copyright (c) 2026 David Heinemeier Hansson — see
[upstream's LICENSE](https://github.com/omacom/omacut/blob/master/LICENSE),
which is also the licence that ships in every zip. The patches and other files
in this repository are offered under the same terms; see [LICENSE](LICENSE).

Released archives bundle Qt (LGPL v3) and a GPL build of ffmpeg. What that
obliges and how to replace either is spelled out in
[THIRD-PARTY.md](THIRD-PARTY.md), which ships inside every zip.
