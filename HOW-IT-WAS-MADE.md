# How bodyslide-cli was made

Fork of ousnius/BodySlide-and-Outfit-Studio (branch `cmd-cli`, based on `dev`).
Goal: drive BodySlide builds from a plain Windows CMD with no GUI.

## Approach
1. **Reuse upstream's native build mode.** BodySlide already supports a
   command-line build (`-gbuild`, `BodySlideApp::CommandLineBuild`). Rather than
   reimplement it, the engine was patched to run fully headless and a thin
   frontend wraps it.
2. **Engine patches (`src/`)**
   - `BodySlideApp`: new `--appdir` option (`cmdAppDir`) so the data folder
     (Config.xml, SliderSets, etc.) is independent of the exe location.
   - No main window shown and no `wxProgressDialog` during a command-line build
     (progress dialog is now a nullable `unique_ptr`).
   - The "sets failed" modal dialog was removed; the result is stored in
     `cmdExitCode` and returned as the process exit code.
   - `WxBuildConfigCheck.cpp`, `PlatformUtil.cpp`, `wxHandleFatalExceptions` /
     `wxDebugReport`: guards so it also compiles with MinGW/LLVM and static wx.
   - `CMakeLists.txt`: resource files only for MSVC; added `lib/OpenGL-Headers`
     (glext.h, khrplatform.h) to the include path.
3. **Frontend**: `bodyslide-cli.cmd` -> `bodyslide-cli.ps1` (pwsh or Windows
   PowerShell). Commands: `help`, `doctor`, `list outfits|groups|presets`,
   `build`. It parses SliderSets/SliderGroups/SliderPresets XML for discovery,
   validates inputs, supports `--dry-run`, and shells out to the engine.
   Exit codes: 0 ok, 1 error, 2 usage, 3 bad data, 4 missing engine.
4. **Engine binary**: built with MSVC/CMake + wxWidgets (static), shipped as
   `dist/engine/BodySlideCLI-engine.exe`; used automatically when no installed
   `BodySlide x64.exe` is found. `tests/mock-engine.cmd` is a stub for tests.

## Build
    cmake -S . -B build-msvc -G "Visual Studio 17 2022" -A x64
    cmake --build build-msvc --config Release --target BodySlide

## Example runs (extras in this commit)
`zero-morph-preset.xml` is a preset that zeroes all sliders; `before-ayleid-build.csv`
is a SHA256 inventory of output files taken before a batch build of the
"[Imp] Ayleid Plugs" groups, used to confirm which files the build changed.
