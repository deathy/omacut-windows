# Third-party components in the Windows build

omacut itself is MIT-licensed (see `LICENSE.txt`), Copyright (c) 2026 David
Heinemeier Hansson. The Windows build ships two things alongside it that carry
their own terms.

## Qt 6 — LGPL v3

The `Qt6*.dll` files, the `plugins/` folder and the `qml/` folder are the Qt
framework, used under the **LGPL v3**. Full text: `LGPL-3.0.txt` (and
`GPL-3.0.txt`, which it refers to).

Qt is **dynamically linked** and unmodified. You may replace it: swap in your
own build of the same Qt 6 modules and re-run the app, or rebuild omacut
against your own Qt with `bin\build-windows.ps1`.

- Qt source: <https://download.qt.io/official_releases/qt/>
- The exact version this build used is recorded in the release notes.

## Microsoft Visual C++ runtime

`msvcp140.dll`, `vcruntime140*.dll` and their siblings are the Visual C++
runtime that an MSVC-built program needs in order to start. They are
redistributable under the Visual Studio licence, and are included so the zip
runs on a machine that has never had Visual Studio or the redistributable
installed.

They are Microsoft's, unmodified. To use your own copy instead, delete them and
install the [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe).

## ffmpeg — GPL v3

`ffmpeg.exe`, `ffprobe.exe` and their `av*.dll` / `sw*.dll` files are a **GPL**
build of ffmpeg. It is GPL rather than LGPL because it includes libx264, which
omacut uses to encode cuts.

- Full text of ffmpeg's licence: `FFMPEG-LICENSE.txt`
- The exact build, its tag and its SHA256: `FFMPEG-BUILD.txt`
- Binaries from: <https://github.com/BtbN/FFmpeg-Builds>
- Corresponding source: <https://github.com/FFmpeg/FFmpeg>, and the build
  scripts that produced these binaries: <https://github.com/BtbN/FFmpeg-Builds>

ffmpeg is a **separate program** that omacut runs as a subprocess; the two are
merely aggregated in one archive, and no ffmpeg code is linked into omacut.
omacut's own terms therefore stay MIT.

If you would rather not have the bundled copy, delete `ffmpeg.exe`,
`ffprobe.exe` and the `av*`/`sw*` DLLs — omacut falls back to whatever `ffmpeg`
and `ffprobe` it finds on your `PATH`.
