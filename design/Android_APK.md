# Build an APK without repeating setup

## Normal workflow

1. Save your changes in Godot.
2. Double-click **Build APK.cmd** in the project folder.
3. Wait for **SUCCESS**. Your phone-test build is **build/CarpetCleaner.apk**.

The builder always uses this project's **Godot 4.7.2 Mono/.NET**, selects **debug export**, auto-detects the configured or standard user Android SDK, and verifies the APK signature. It shares the editor launcher's strict engine version/flavor gate: no other version or standard build is accepted. The complete bundle is `tools/godot/Godot_v4.7.2-stable_mono_win64/`; keep its `GodotSharp` directory beside the executables. It runs Godot with an isolated build profile under `build/godot-build-profile`, so it does not require or rewrite your normal editor settings. It only replaces the previous APK after success. It does not install software or replace your signing key. It builds saved files, so unsaved editor changes are not included.

For editing, double-click **Open Game Editor.cmd**. This opens the same pinned Mono/.NET bundle on the floating main menu. Do not use the older standard executable or a different editor shortcut for this project.

Gameplay remains **GDScript**, not a C# port. The installed **.NET 8 SDK 8.0.400** supports the Mono editor. If C# gameplay is requested later, its Android target SDK/workloads and managed export must be configured and verified separately; installing the editor SDK does not establish Android C# build readiness.

The 2026-09-22 toolchain pin uses **4.7.2.stable.mono** export templates, installed from the official archive after SHA-512 verification. A fresh **34.1 MiB APK was exported and independently signature-verified** with `4.7.2.stable.mono.official.ed1daf0bf`. Wet-tool and squeegee/camera validation passed **172 checks** using that same engine. The current gameplay is GDScript, so this verifies a Mono-engine export, not compilation of a C# game.

The pinned engine emits `EditorSettings not instantiated yet` for `export/android/shutdown_adb_on_exit` during headless editor teardown. The builder records that exact diagnostic as a warning only when the export completed and the engine exited successfully, then independently verifies the APK signature. Every other engine/script error still fails the build. Raw stdout/stderr and the warning remain in `build/android-build-*.log` and `build/android-build-info.txt`. Exports launch the actual engine directly, avoiding Windows PowerShell 5.1 native-stderr handling and the console wrapper's shutdown hang.

Command-line equivalents (PowerShell, from the project folder):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build_android.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build_android.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\build_android.ps1 -ForceFallbackSdk
```

## If you export in the Godot UI

Use **Project → Export → Android → Export Project**. Keep **Export With Debug** checked for this phone-test build. Save to `build/CarpetCleaner.apk`. Release exports require separately configured release signing credentials; reinstalling the SDK will not fix a missing release key.

## Match the error to the fix

| Error or symptom | Fix |
| --- | --- |
| Templates missing; a path ends in `4.7.2.stable.mono` | Install the official **4.7.2 Mono/.NET export templates** through **Editor → Manage Export Templates**. The required folder is `%APPDATA%\Godot\export_templates\4.7.2.stable.mono`. Do not substitute or rename standard templates. |
| A template path ends in `4.7.2.stable` without `.mono`, or the launcher rejects the engine | The wrong build is being used. Save your changes, reopen via **Open Game Editor.cmd**, and retain only the pinned 4.7.2 Mono/.NET path in project launch/build commands. |
| Missing `GodotSharp`, .NET host, or SDK | Restore the **complete** Mono bundle rather than copying its executable alone; check `dotnet --list-sdks`. This Windows editor uses .NET 8; SDK 8.0.400 is installed on this computer. |
| No Android SDK / invalid Android SDK Path | In **Editor → Editor Settings → Export → Android**, set the SDK root listed below. It must contain `platform-tools/adb.exe`; do not select `platform-tools` itself. |
| Cannot read `platform-tools/adb.exe` | The builder records a warning and continues building the APK. ADB is needed for connected-phone discovery/deployment, not for creating the APK file. Check `build/android-build-launcher.log` before trying to deploy directly from Godot. |
| The configured SDK is missing or stale | The builder also checks `%LOCALAPPDATA%\Android\Sdk`, then the legacy machine-wide `C:\Program Files (x86)\Android\android-sdk` fallback. It reports every rejected candidate without changing normal editor settings. |
| Java SDK / keytool not found | In the same screen, set the JDK root below, not its `bin` subfolder. |
| Release keystore or release password missing | For phone testing, check **Export With Debug**. This helper always does that. |
| Script, resource or import error | Read the first actual error in `build/android-build-console.log`. Fix that resource/code error; it isn't an SDK installation issue. |
| Export dialog looks stale but **Build APK.cmd** succeeds | Save the project, close old editor instances, reopen with **Open Game Editor.cmd**, then reopen Export. Record the exact dialog error if it persists. |

SDK/JDK paths recorded on this computer, plus the required Mono template location:

```text
Build APK.cmd SDK: C:\Users\Hurshuuuuuu\AppData\Local\Android\Sdk
Godot editor SDK:  C:\Users\Hurshuuuuuu\AppData\Local\Android\Sdk
Java SDK Path:    C:\Program Files\Java\jdk-21.0.12
Templates:       %APPDATA%\Godot\export_templates\4.7.2.stable.mono
Builder tools:   36.1.0; Android platform 36
.NET editor SDK: 8.0.400 (C:\Program Files\dotnet\sdk)
```

SDK/JDK paths are **user-wide Editor Settings**, not part of `project.godot`. When repairing them, first close older editor instances, then open one correct editor and set the paths there. Do not edit settings files externally while other editors may still save their cached settings. Do not regenerate the debug signing key to repair an SDK-path problem.

## Historical diagnostics — standard-build workflow superseded

The following 2026-09-20/21 observations record the previous standard-build workflow. The 2026-09-22 requirement supersedes its editor/template choice: all current opening, validation and export commands must use **4.7.2 Mono/.NET**. Keep these notes as diagnostic history, not instructions to return to the standard build.

The previous repair found a stale Desktop Mono executable reference. During this investigation, the shortcut, project editor metadata, SDK paths and standard templates were already correct. A fresh standard-editor export succeeded before changing project/export settings. The current reported UI failure could not be reproduced without its exact error message.

The menu and new Blender assets successfully exported with the earlier standard toolchain. That APK was signature-verified; this does not verify the new Mono-pinned export. Installation and behavior on a physical phone were not tested here.

Logs and build identity:

- `build/android-build-launcher.log`: copy of the latest preflight/build transcript. Timestamped `android-build-launcher-*.log` files preserve earlier failures instead of being overwritten by a later run.
- `build/android-build-console.log`: full export output and first failing step.
- `build/android-signature.log`: signature-verification result.
- `build/android-build-info.txt`: engine version, APK size, build time and SHA-256.

The repair on 2026-09-21 installed a complete user SDK at the standard Local AppData path and removed the launcher's obsolete forced Program Files fallback. `Build APK.cmd` also supplies a process-scoped execution-policy override, because the machine policy otherwise blocked `build_android.ps1` before preflight began.

Godot runs from an isolated build profile containing the detected SDK path, the matching template and a copy of the existing debug key. The normal Godot editor settings are never rewritten or required. The launcher directly checks the build tools, platform, JDK, templates, export result and APK signature, and preserves timestamped diagnostics.

An end-to-end run of the `.cmd` also exposed a post-export `Get-FileHash` module-loading failure. Hashing now uses .NET directly and happens before the verified staged APK replaces the old output. The launcher no longer claims the old APK was kept for every possible post-export error.

Reference: Godot's [Android export setup](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) documents the two user-wide paths and debug/release signing distinction; its [command-line guide](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) documents `--export-debug`. The existing JDK 21 installation was tested successfully; no JDK replacement was needed.
