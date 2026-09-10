# omacut for Windows

An **unofficial Windows build** of [omacut](https://github.com/omacom/omacut) —
David Heinemeier Hansson's dead-simple video length trimmer. Open a video, drag
two handles to pick a start and an end, preview, export.

This repository is a thin port. Nearly all of the code is upstream's; what is
added here is a file picker for platforms with no desktop portal, a Windows-safe
file replace, and the packaging to ship it. All credit for omacut goes upstream.

## Install

Download the latest `omacut-*-win64.zip` from
[Releases](../../releases), unpack it anywhere, and run `omacut.exe`.

ffmpeg is bundled — there is nothing else to install.

> **SmartScreen will warn you on first run.** These builds are not code-signed
> (a certificate is a few hundred dollars a year). Choose *More info* →
> *Run anyway*. If you would rather not, build it yourself — see below.

## Hotkeys

- *Space*: start/stop playback
- *Left/Right*: move the playhead by 1 second
- *Shift+Left/Right*: by 5 seconds; *Alt+Left/Right*: by 0.2 seconds
- *Ctrl+Space* / *Alt+Space*: set the start / end of the trim to the playhead
- *Z*: zoom into the selection for fine tuning
- *Ctrl+O*: open a file · *Ctrl+S*: export · *Q*: quit · *?*: show hotkeys

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

## Building it yourself

You need [Qt 6](https://www.qt.io/download-qt-installer) (with the Qt Multimedia
module) and MSVC. From an *x64 Native Tools Command Prompt for VS*:

```powershell
pwsh -File bin\build-windows.ps1 -QtDir C:\Qt\6.8.1\msvc2022_64
```

That builds, gathers the Qt runtime, downloads ffmpeg, and leaves a runnable
folder in `build\omacut-local-win64\`. Pass `-SkipFfmpeg` if you already have
ffmpeg on your `PATH`.

The port also builds and runs on macOS, which is how it gets tested without a
Windows machine in the loop:

```sh
brew install qtbase qtdeclarative qtmultimedia
./bin/build            # upstream's own build script
```

## How releases track upstream

Releases here are tagged `win-v0.4.0`, deliberately clear of upstream's own
`v0.4.0` — this repository carries upstream's history, and therefore its tags.
The version people see drops the prefix; a semver suffix (`win-v0.4.0-alpha.1`)
publishes as a pre-release.

`UPSTREAM_VERSION` records the upstream tag this port is built from. A daily
[workflow](.github/workflows/upstream-sync.yml) checks for a newer upstream
release and, when it finds one, merges it and opens a pull request. If the merge
conflicts it opens an issue instead — it never resolves a conflict on its own and
never publishes from one.

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
[LICENSE](LICENSE). The changes in this repository are offered under the same
terms.

Released archives bundle Qt (LGPL v3) and a GPL build of ffmpeg. What that
obliges and how to replace either is spelled out in
[THIRD-PARTY.md](THIRD-PARTY.md), which ships inside every zip.
