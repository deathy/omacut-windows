# How the Windows port works

This repository is **not a copy of omacut**. It holds only what the Windows
port adds or changes. The source that gets compiled is assembled at build time:

```
upstream omacut @ UPSTREAM_VERSION      https://github.com/omacom/omacut
  + overlay/                            files the port adds, copied in as-is
  + patches/*.patch                     the port's edits to upstream's files
  = work/                               what CMake builds (ignored by git)
```

`bin/prepare-source.ps1` does the assembling; `bin/export-patches.ps1` turns
edits made in `work/` back into `patches/`. Both are PowerShell 7 and run the
same on Windows, Linux and macOS. `bin/build-cmake.ps1` builds `work/` with
upstream's `CMakeLists.txt`, adjusted from outside by
`overlay/port/omacut-port.cmake` (see below); CI, releases and the local
scripts all build through it.

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
- **Prefer adjusting from outside to patching.** The build is the example:
  `overlay/port/omacut-port.cmake` is passed to CMake as
  `CMAKE_PROJECT_INCLUDE`, which runs it right after upstream's `project()`.
  It defers its adjustments (`cmake_language(DEFER)`) to the end of
  upstream's `CMakeLists.txt` and then changes upstream's targets in place,
  so upstream's build file is never touched. Only what cannot be reached from
  outside belongs in a patch.
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

*Overlay:* `src/dialogfilepicker.{h,cpp}`, `tests/dialogfilepicker_tests.cpp`,
`port/omacut-port.cmake`.
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
- `tests/omacut_tests.cpp` (`backend_tests.cpp` before v0.8.0): upstream tests
  `PortalFilePicker` itself
  (`portalPickerReplacesAnUnansweredRequest`, since v0.7.2), against a fake
  portal on a private D-Bus. The Windows test build has neither the picker
  nor D-Bus, so everything that needs them (the `QDBus*` and
  `portalfilepicker.h` includes, `FakePortalRequest`, `FakePortalService`,
  the test's body) goes under `#ifndef OMACUT_NO_PORTAL_PICKER`, and the test
  `QSKIP`s with the reason instead. Do the same for any later portal test.

**From outside** (overlay, no patch): upstream's `CMakeLists.txt` globs
`src/`, so the overlay's `dialogfilepicker.*` land in its `omacut_core`
library on their own, and so does `portalfilepicker.*`.
`port/omacut-port.cmake` takes `portalfilepicker.*` back out of
`omacut_core`, swaps `Qt6::DBus` for `Qt6::Widgets` in what it links, defines
`OMACUT_NO_PORTAL_PICKER` for `omacut_tests` (which the test patch above keys
on), and adds the `dialogfilepicker_tests` target. It stops with an error if
`omacut_core` no longer builds `portalfilepicker.cpp`, or if any of
`omacut_core`, `omacut` and `omacut_tests` is gone, because otherwise its
changes would quietly do nothing.

The same file also fits upstream's GCC flags to MSVC: it drops the `-W*`
options (MSVC reads `-Wall` as `/Wall`, which floods the build with warnings
from Qt's headers) for `/W3 /utf-8`. `bin/build-cmake.ps1` passes
`CMAKE_BUILD_TYPE=Release` itself: upstream defaults to Release only when no
build type is set, and CMake sets Debug on its own for MSVC.

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
  time the call returns;
- symlinks made with `QFile::link`, which on Windows makes a `.lnk` shortcut
  instead.

**What.** Adapt the tests, never the code under test, and keep what each test
asserts. For example, the broken fake on Windows is an `ffmpeg.exe` that holds
no valid executable image, the fake `hyprctl` in
`themeFollowsHyprlandRounding` is a `hyprctl.cmd` that `type`s its answer, and
an assertion that only holds where failures are asynchronous goes under
`#ifndef Q_OS_WIN`. Only if a test truly cannot be expressed on Windows,
`QSKIP` it there with the reason. Do not delete it.
`themeFollowsASymlinkSwitch` is one: Omarchy switches themes by renaming one
symlink over another, and Windows has neither unprivileged directory symlinks
nor a rename that replaces one.

**Upstream adds tests of this kind regularly**, so check every new upstream
version for more (see the checklist below), even when every patch applies
cleanly. Watch for tests that pass on Windows only because their setup
quietly does nothing there, not just ones that fail.

Example: `thumbProviderStopsBlockedJobs` (`thumbnailWorkerStopsBlockedJobs`
before v0.7.0) fakes a hanging ffmpeg with a `#!/bin/sh` script that runs
`sleep`. On Windows that script never starts, so the test used to pass
without testing anything, and only where a `sleep` happened to be on the
PATH. On Windows the port now hangs the *real* ffmpeg instead: its input is
a named pipe (`CreateNamedPipeW`) that never sends a byte. The test then
waits until ffmpeg has opened the pipe (`GetNamedPipeClientProcessId`)
before timing the stop. The patch wraps this in a `SilentPipe` helper in
`tests/omacut_tests.cpp`, which `thumbProviderCancelsRunningJobs` uses the
same way. Use `SilentPipe` for any future test that needs a hung or slow
ffmpeg or ffprobe, where the test chooses what the tool reads.

Where it can't, fake the tool with a batch file, as the `hyprctl.cmd` does.
`toolPath()` finds a `.cmd` on the PATH. Since v0.8.4, `Backend` opens no
`\\.\pipe\...` path, and an export reads the loaded video, so three tests
use batch files:

- `probeRunsOffTheUiThread`'s `ffprobe.cmd` waits two seconds (`ping`, named
  in full because the test's PATH holds only the fake) and exits without
  output, as upstream's fake does. Halfway through, the test checks that the
  probe is still running, so a fake that never started can't pass it.
- `destroyingBackendMidExportStopsProcessCleanly`'s `ffmpeg.cmd` loops in
  place (`goto`), so killing it leaves no child process behind.
- `probeFallsBackPastNaDuration`'s `ffprobe.cmd` `echo`es upstream's JSON.

### 6. Play videos whose names need escaping

*Patch:* `Play videos whose names need escaping`.

**Why.** `Main.qml` decides whether the player already holds a clip's video
by comparing URLs as text: `player.source.toString()` against
`backend.videos[i].url.toString()`. The first is QML's own `url` type, which
prints decoded (`a b.mp4`). The second came from a `QUrl` inside the
`QVariantMap` that `Backend::videoList()` returns. On the Qt 6.8 that this
port builds with, that reaches QML as a JS `URL`, which prints fully
percent-encoded (`a%20b.mp4`). Any file name with a space or a non-ASCII
letter then never compared equal. That includes Windows Game Bar captures,
whose names are full of zero-width spaces. `show()` kept setting the same
source and waiting for a load that never came: the video showed, and play
did nothing.

**What.** `videoList()` hands out the url as text, `QUrl::toString()`, which
is the same form QML's `url` type prints. The test
`qmlPlaysVideosWhoseNamesNeedEscaping` opens such a file through the real
`Main.qml` and checks that Space plays it.

**When to drop it.** This is not Windows-specific. Whether upstream's Linux
build has it depends on the Qt version there. If upstream compares these URLs
some other way, or stops passing `QUrl`s through `videoList()`, check whether
the test still passes without this patch, and drop the patch if it does.

### 7. Add every video of a drop

*Patch:* `Add every video of a drop on Qt 6.8`.

**Why.** Since v0.7.2, `Main.qml`'s `dropVideos()` hands the drop's whole
url list to `Backend::addVideos(const QVariantList &, double)`. On Qt 6.8
each entry arrives as a `QVariant` holding a `QVariant` that holds the
`QUrl`, and `toUrl()` on the outer one gives an empty url. `checkedPath()`
then refused every file as not a local path, so dropping files on the
window never opened or added anything. This is section 6's problem in the
other direction, from QML to C++.

**What.** In `addVideos()`, read each entry through
`qvariant_cast<QVariant>(value).toUrl()`. That unwraps the extra level and
leaves an entry that holds the `QUrl` directly as it is. The upstream tests
`qmlDropOpensThenAddsVideos` and `qmlDropLandsAfterThePlayheadsClip` fail
without it.

**When to drop it.** As for section 6: this depends on the Qt version, not
on Windows. If upstream changes `addVideos()` to take a `QList<QUrl>` or
unwraps the entries itself, check whether the drop tests pass without this
patch, and drop the patch if they do.

### 8. Let go of a replaced dialog button's letter at once

*Patch:* `Let go of a replaced dialog button's letter at once`.

**Why.** Since v0.8.3, each `DialogButton` (`src/DialogButton.qml`) answers
its underlined letter through an application-wide `Shortcut`, enabled while
the button is visible. The quit question's buttons depend on
`backend.exporting`, so when an export ends its `Repeater` replaces them. On
Qt 6.8 a replaced button is destroyed but only freed on a later turn of the
event loop, and until then its `Shortcut` stays registered and enabled. The
old Quit button's Q and the window's own Q are then two live shortcuts on one
key, which Qt treats as ambiguous, so neither fires: a Q pressed right after
an export finishes quits nothing. `qmlQuitAsksWhileExporting` fails on it.

**What.** In `Component.onDestruction`, set the `Shortcut`'s `sequences` to
`[]`, which takes them out of the shortcut map at once.

**When to drop it.** Like sections 6 and 7, this depends on the Qt version,
not on Windows. If upstream stops replacing the buttons, or no longer gives
them application-wide shortcuts, check whether `qmlQuitAsksWhileExporting`
passes without this patch, and drop it if it does.

### 9. Upstream's tests on Qt 6.8

*Patch:* `Run upstream's tests on Qt 6.8`.

**Why.** Upstream tests against Arch's Qt, which is newer than the 6.8 the
port builds with, and some of its tests use what only the newer Qt has:

- `dropUrls()` builds a `QDragEnterEvent` from a `QPointF`, a constructor Qt
  6.8 lacks.
- `qmlTimelineViewDependsOnlyOnTheEdit` compares a grab of the edited bar
  with a fresh editor's, pixel by pixel. The tests run offscreen on Qt
  Quick's software renderer (upstream's test `main()` picks it), and on Qt
  6.8 that renderer can keep a node from before an edit on screen until the
  bar's geometry changes: the grab showed an accent clip frame where no clip
  was any more, while the scene itself matched the fresh editor's.

**What.** Pass `dropUrls()`'s point as a `QPoint`; it is a whole pixel
anyway. In `EditorUnderTest::view()`, just before the grab, hide the bar,
grab the window once, and show the bar again, which rebuilds its scene graph
nodes. The throwaway grab is what makes that certain: it renders a frame
while the bar is hidden. A fixed wait there instead (20 ms, the first
version of this) was usually enough on Windows but not on the slower macOS
runner, where the stale frame then failed a different seed on each run. What either test asserts does not
change. As with section 5, adapt tests like these rather than the code under
test.

**When to drop it.** When the port moves to a newer Qt: check whether the
tests pass without each part, and drop what is no longer needed.

### 10. Windows executable metadata

*Overlay only:* the `if(WIN32)` block in `port/omacut-port.cmake` and
`pkgbuild/omacut.ico`. Builds `omacut.exe` as a GUI-subsystem program
(`WIN32_EXECUTABLE`, or Windows opens a console beside it) and gives it its
icon and version-info strings through a generated `omacut.rc`. Nothing in
upstream's files changes.

### 11. macOS (experimental)

*Overlay only:* the `if(APPLE)` block in `port/omacut-port.cmake` and
`pkgbuild/omacut.icns`. *Build:* the `$IsMacOS` lines in
`bin/build-cmake.ps1`. *Packaging:* `bin/fetch-ffmpeg-macos.ps1`,
`bin/package-macos.ps1`, the `macos` job in `.github/workflows/build.yml`.

**Why.** Nothing in sections 1 to 9 is Windows-only in effect: each is either
guarded by `Q_OS_WIN`/`Q_OS_LINUX` or holds on any non-Linux desktop. The
QFileDialog picker shows the native macOS panels, `toolPath()` finds ffmpeg in
`Contents/MacOS` (the `applicationDirPath()` of an app bundle), and the
hardware decoder list is left to Qt, which means VideoToolbox. So a macOS
build is packaging and nothing more, and stays that way: **no patch is
macOS-specific**. If one ever has to be, say so here first.

**What.** The `if(APPLE)` block builds `omacut` as `omacut.app`
(`MACOSX_BUNDLE`; upstream's target is a bare executable) with the icon and
an `Info.plist` that names the identifier, the minimum macOS (12, as for
Qt 6.8) and Retina rendering, none of which CMake's default plist does.
`build-cmake.ps1` sets the architecture (arm64) and deployment target on
macOS, because both must be known before `project()`, and the hook runs
after it. `omacut.icns` is upstream's `pkgbuild/omacut.svg` drawn at 880 px on a
1024 px canvas, which puts the icon's body on the size Apple's icon grid
expects (824 px) so that it sits right next to other apps in the Dock.
`package-macos.ps1` runs `macdeployqt`, adds Martin Riedl's static arm64
ffmpeg and ffprobe (pinned by hash; they link only system frameworks),
checks that every Mach-O file in the bundle loads only the OS and the
bundle, signs it ad hoc, and starts it offscreen for a few seconds before
zipping it with `ditto`. CI uploads that zip before running the test suites,
so a macOS-only test failure does not cost the app.

Apple silicon only, and not released: there is no `macos` job in
`release.yml` yet. Before adding one, try a CI build on a real Mac the way
the checklist below says for Windows, including that the export quality
choices show in the save panel's format popup.

### Not changes, but differences users see

- The accent colour is upstream's default amber. Upstream reads it from the
  Omarchy theme and falls back to the default when there is none, which on
  Windows is always. No code is involved.
- Since v0.8.4, upstream opens and exports only paths with no host
  (`isLocalAbsolutePath()` in `src/backend.cpp`), so that ffprobe and ffmpeg
  are never handed a network address. On Windows that also refuses UNC paths
  (`\\server\share\...`); a share mapped to a drive letter works. The port
  keeps upstream's behaviour.
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
git -C work diff <old-tag> <new-tag> -- src tests CMakeLists.txt
```

and look in the new code for:

- changes to `CMakeLists.txt`: renamed targets, new link libraries or
  compiler flags, sources no longer globbed from `src/`, all of which
  `port/omacut-port.cmake` may need to follow (section 1);
- new uses of `std::rename`, or other POSIX-only file handling (section 2);
- tools found by anything other than `ffmpeg::toolPath()` (section 3);
- D-Bus, the portal, or new Linux-only sources in `src/`, and tests that use
  either (section 1);
- Linux-only environment tweaks in `main()` (section 4);
- new tests that use `':'` in PATH, `#!` fakes, `setPermissions(ExeOwner)`,
  `sleep`/`sh`, `QFile::link`, or that assume an asynchronous process failure
  (section 5);
- tests that build Qt events or call Qt APIs newer than 6.8 (section 9);
- a `QGuiApplication` created anywhere else, which the widget picker needs to
  be a `QApplication`;
- URLs compared as text in QML, or new `QUrl`s handed to QML inside a
  `QVariantMap`/`QVariantList`, which print differently from `url`
  properties (section 6);
- new `Q_INVOKABLE`s taking a `QVariant`, `QVariantList` or `QVariantMap`
  that QML fills with urls or other values that may arrive wrapped in an
  extra `QVariant` (section 7).

Then build and test it on Windows (`check-local.ps1`, and CI on the pull
request), and try the build artifact on a Windows machine. Use a video whose
name has spaces and a non-ASCII letter, because most real ones do: open,
play, trim, export, and export over an existing file.

## Recreating the patches from scratch

When the patches are too far gone to resolve, start again:

```powershell
Remove-Item patches/*.patch
pwsh -File bin/prepare-source.ps1 -Ref vX.Y.Z   # upstream + overlay, no patches
```

Then, in `work/`, carry out sections 1 to 9 against the code as it now is. Make one
commit per section with a message that explains the why, as the existing
patches do. Then run `export-patches.ps1`, update `UPSTREAM_VERSION`, and
go through the checklist above. If upstream has reworked something so far
that a section no longer applies as written (for example the file picker is no
longer behind `FilePicker`), keep the **Why**, work out the equivalent change,
and update this document in the same pull request.
