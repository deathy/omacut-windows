# How the Windows port works

This repository is **not a copy of omacut**. It holds only what the Windows
port adds or changes. The source that gets compiled is assembled at build time:

```
upstream omacut @ UPSTREAM_VERSION      https://github.com/omacom/omacut
  + overlay/                            files the port adds, copied in as-is
  + patches/*.patch                     the port's edits to upstream's files
  = work/                               what qmake builds (ignored by git)
```

`bin/prepare-source.ps1` does the assembling; `bin/export-patches.ps1` turns
edits made in `work/` back into `patches/`. Both are PowerShell 7 and run the
same on Windows, Linux and macOS.

## What is ours and what is upstream's

| Path | Whose | What it is |
|---|---|---|
| `UPSTREAM_VERSION` | ours | the upstream tag the patches apply to, exactly |
| `patches/` | ours | edits to files upstream has; one patch per concern |
| `overlay/` | ours | files upstream does not have; copied to the same path in `work/` |
| `bin/`, `.github/` | ours | assembling, building, packaging, CI |
| `licenses/`, `THIRD-PARTY.md` | ours | what the bundled Qt and ffmpeg oblige the zip to carry |
| `work/` | upstream + ours | generated; never commit it, never treat it as the source of truth |

Ground rules that keep it that way:

- **A patch only changes files upstream has.** A new file goes in `overlay/`.
  `export-patches.ps1` refuses a patch that adds a file, and
  `prepare-source.ps1` refuses an overlay file that would overwrite one of
  upstream's.
- **Prefer adjusting from outside to patching.** The `.pro` files are the
  example: `overlay/omacut-windows.pro` does `include(omacut.pro)` and then
  removes and adds sources, so upstream's project file is never touched. Only
  what cannot be reached from outside belongs in a patch.
- **Keep patches small and one concern each**, and keep each one matching its
  section below. Every patch is one more place upstream can conflict.
- **Never fix things in `work/` and stop there.** `prepare-source.ps1` rebuilds
  `work/` from scratch. Export, or the change is gone.

## The changes, and why each exists

This section is the specification. The patches are one way of carrying it out
against one upstream version. If a patch stops applying and is easier to
redo than to rescue, redo it from here against the new upstream code. Look
things up by the identifiers named, not by line numbers.

### 1. File picker: QFileDialog instead of the desktop portal

*Overlay:* `src/dialogfilepicker.{h,cpp}`, `omacut-windows.pro`,
`tests/backend_tests-windows.pro`, `tests/dialogfilepicker_tests.{cpp,pro}`.
*Patch:* `Pick files with QFileDialog instead of the desktop portal`.

**Why.** Upstream opens and saves files through xdg-desktop-portal over D-Bus
(`PortalFilePicker`, `src/portalfilepicker.*`). Windows has neither.

**What.** Upstream defines an abstract `FilePicker` (`src/filepicker.h`):
`openVideo()`, `exportVideo(suggestedUrl, scaleHeights)`, and the signals
`openSelected(url)`, `exportSelected(url, scaleHeight)`, `failed(message)`.
The port's `DialogFilePicker` implements it with `QFileDialog`, which shows
the native Windows dialogs:

- *Open:* starts in the Videos folder (home if there is none). The filter
  offers the same video extensions the portal picker does, plus "All files".
- *Export:* starts at the suggested path. The portal shows a separate
  "Quality" combo (upstream's `choices`); a native save dialog has nowhere to
  put one, so each quality becomes a "Save as type" entry instead:
  `MP4 video - Original (*.mp4)`, then `MP4 video - 1080p (*.mp4)`, and so on
  for each of `scaleHeights`. The chosen entry maps back to a `scaleHeight` by
  position, with entry 0 and anything unrecognised meaning 0 (original). With
  no `scaleHeights` there is just `MP4 video (*.mp4)`.
- It does **not** force a `.mp4` suffix. `Backend` does that, and refuses when
  the rewrite would land on a file the dialog never offered to overwrite.
  Adding the suffix in the picker would quietly bypass that check.

**In upstream's files** (the patch), only what cannot be done from outside:

- `src/backend.cpp`: the convenience constructor
  `Backend(ThumbProvider *, QObject *)` builds the default picker. Make it
  build a `DialogFilePicker` instead of a `PortalFilePicker`, and include
  `dialogfilepicker.h` instead of `portalfilepicker.h`.
- `src/main.cpp`: `QFileDialog` is a widget, so the application object must be
  a `QApplication`, not a `QGuiApplication`. Change both the include and the
  object.

**From outside** (overlay, no patch): `omacut-windows.pro` and
`tests/backend_tests-windows.pro` include upstream's project files, then swap
`portalfilepicker.*` and the `dbus` module for `dialogfilepicker.*` and
`widgets`. They stop with an error if upstream's project file no longer lists
`portalfilepicker.cpp`, because otherwise the `-=` would quietly do nothing.

**Still right when:** the build has no D-Bus dependency, and
`dialogfilepicker_tests` passes.

### 2. Replace the exported file atomically

*Patch:* `Replace the exported file atomically on Windows`.

**Why.** An export is written to a temporary file and then renamed over the
destination (`replaceWithTemp()` in `src/backend.cpp`). `std::rename()` fails
on Windows when the destination exists, which is the normal case when
re-exporting over an earlier cut. `QFile::encodeName()` would also mangle a
non-ASCII path.

**What.** Under `#ifdef Q_OS_WIN`, use
`MoveFileExW(tmp.utf16(), out.utf16(), MOVEFILE_REPLACE_EXISTING)` (from
`<windows.h>`) and keep upstream's code in the `#else`. If upstream moves this
rename elsewhere or adds another rename-over-existing, the same applies there.

**Still right when:** `failedExportPreservesExistingFile` and the
export-over-existing tests pass, and an export over an existing file works in
the real app.

### 3. Prefer the bundled ffmpeg

*Patch:* `Look for ffmpeg next to the executable before the PATH`.
*Packaging:* `bin/fetch-ffmpeg.ps1`, `bin/package-windows.ps1`.

**Why.** On Linux ffmpeg is a package dependency found on the PATH. The
Windows zip bundles `ffmpeg.exe` and `ffprobe.exe` next to `omacut.exe`, and
those must win over whatever other ffmpeg is on the PATH.

**What.** In `toolPath()` (`src/ffmpeg.cpp`), the one place upstream resolves
`ffmpeg`/`ffprobe`, look in `QCoreApplication::applicationDirPath()` first
and fall back to the PATH. If upstream ever resolves a tool somewhere other
than `toolPath()`, route it through `toolPath()` or give it the same fallback.

### 4. Leave the hardware decoder list to Linux

*Patch:* `Keep the hardware decoder list to Linux`.

**Why.** `main()` sets `QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi,cuda` to keep
Qt off a Vulkan path that shows AV1 as black on Linux. That variable
*replaces* Qt's decoder list, and on Windows neither name is the platform
decoder (D3D11), so hardware decoding would silently turn off for everything.

**What.** Wrap that setting in `#ifdef Q_OS_LINUX`. Do the same for any other
Linux-specific multimedia environment tweak upstream adds.

### 5. Backend tests that run on Windows

*Patch:* `Make the backend tests pass on Windows`.

**Why.** Some upstream tests rely on POSIX behaviour that has nothing to do
with the code under test:

- joining PATH entries with `':'` (Windows uses `';'`, i.e.
  `QDir::listSeparator()`);
- faking a broken or hanging ffmpeg with a `#!` shell script. Windows finds
  executables by extension and starts them with `CreateProcess`, which knows
  nothing about shebangs;
- expecting a failed process start to be reported asynchronously.
  `CreateProcess` fails inline, so `errorOccurred` has already fired by the
  time the call returns.

**What.** Adapt the tests, never the code under test, and keep what each test
asserts. For example, the broken fake on Windows is an `ffmpeg.exe` that holds
no valid executable image, and an assertion that only holds where failures
are asynchronous goes under `#ifndef Q_OS_WIN`. Only if a test truly cannot
be expressed on Windows, `QSKIP` it there with the reason. Do not delete it.

**Upstream adds tests of this kind regularly**, so check every new upstream
version for more (see the checklist below), even when every patch applies
cleanly. Watch for tests that pass on Windows only because their setup
quietly does nothing there, not just ones that fail.

Known gap: `thumbnailWorkerStopsBlockedJobs` (`thumbProviderStopsBlockedJobs`
from v0.7.0) fakes a hanging ffmpeg with a `#!/bin/sh` script that runs
`sleep`. On Windows that script can never start, so the test proves nothing.
It passes in CI only because the runner happens to have Git's `sleep.exe` on
its PATH, and it fails its own precondition anywhere `sleep` is missing. It
still needs a Windows equivalent: a fake ffmpeg that really hangs.

### 6. Windows executable metadata

*Overlay only:* the `win32 {}` block in `omacut-windows.pro` and
`pkgbuild/omacut.ico`. Gives `omacut.exe` its icon and its version-info
strings. Nothing in upstream's files changes.

### Not changes, but differences users see

- The accent colour is upstream's default amber. Upstream reads it from the
  Omarchy theme and falls back to the default when there is none, which on
  Windows is always. No code is involved.
- Packaging (Qt runtime, MSVC runtime, ffmpeg, licences, zip) lives entirely
  in `bin/` and `.github/` and never touches the source tree.

## Moving to a new upstream release

The daily sync workflow tries this on its own. It runs `prepare-source.ps1`
against the new tag and either opens a pull request with the re-exported
patches, or files an issue if a patch does not apply. To do it by hand, or
to finish what the issue reports:

```powershell
pwsh -File bin/prepare-source.ps1 -Ref vX.Y.Z
# On a conflict, git am stops in work/ on that patch. Resolve it there,
# keeping the intent from the matching section above:
git -C work add <files>
git -C work am --continue          # repeat until all patches are applied
pwsh -File bin/export-patches.ps1  # rewrites patches/ against vX.Y.Z
Set-Content UPSTREAM_VERSION vX.Y.Z
pwsh -File bin/check-local.ps1     # clean re-apply, build, test, package -- as CI does
```

`check-local.ps1` runs CI's whole build on a Windows machine with MSVC, Qt
and ffmpeg. Pass `-Ref vX.Y.Z` to try a newer upstream before touching
`UPSTREAM_VERSION`, or `-SkipPrepare` to build `work/` as it is mid-resolution.

To change a patch rather than resolve one, edit the files in `work/`, change
the matching commit there (`git -C work commit --fixup`, then
`git -C work rebase -i --autosquash <tag>`, or simply amend), and export.
Overlay files can be edited in `overlay/` directly; edits made to them in
`work/` are copied back by the export.

**A clean apply proves nothing about behaviour.** Before calling a new
version done, compare it against the previous one:

```powershell
git -C work diff <old-tag> <new-tag> --stat
git -C work diff <old-tag> <new-tag> -- src tests '*.pro'
```

and look in the new code for:

- new uses of `std::rename`, or other POSIX-only file handling (section 2);
- tools found by anything other than `ffmpeg::toolPath()` (section 3);
- D-Bus, the portal, or new Linux-only sources in `omacut.pro` (section 1);
- Linux-only environment tweaks in `main()` (section 4);
- new tests that use `':'` in PATH, `#!` fakes, `setPermissions(ExeOwner)`,
  `sleep`/`sh`, or that assume an asynchronous process failure (section 5);
- a `QGuiApplication` created anywhere else, which the widget picker needs to
  be a `QApplication`.

Then build and test it on Windows (`check-local.ps1`, and CI on the pull
request), and try the build artifact
on a Windows machine: open, trim, export, and export over an existing file.

## Recreating the patches from scratch

When the patches are too far gone to resolve, start again:

```powershell
Remove-Item patches/*.patch
pwsh -File bin/prepare-source.ps1 -Ref vX.Y.Z   # upstream + overlay, no patches
```

Then, in `work/`, carry out sections 1 to 5 against the code as it now is. Make one
commit per section with a message that explains the why, as the existing
patches do. Then run `export-patches.ps1`, update `UPSTREAM_VERSION`, and
go through the checklist above. If upstream has reworked something so far
that a section no longer applies as written (for example the file picker is no
longer behind `FilePicker`), keep the **Why**, work out the equivalent change,
and update this document in the same pull request.
