# Build an APK without repeating setup

## Normal workflow

1. Save your changes in Godot.
2. Double-click **Build APK.cmd** in the project folder.
3. Wait for **SUCCESS**. Your phone-test build is **build/CarpetCleaner.apk**.

The builder always uses this project's **standard Godot 4.7.2**, selects **debug export**, uses the machine-wide Android SDK listed below, and verifies the APK signature. It runs Godot with an isolated build profile under `build/godot-build-profile`, so it does not rewrite your normal editor settings. It only replaces the previous APK after success. It does not install software or replace your signing key. It builds saved files, so unsaved editor changes are not included.

For editing, double-click **Open Game Editor.cmd**. This opens the correct bundled editor on the floating main menu. The separate **Mono/.NET editor on the Desktop** is not the editor used for these successful GDScript builds.

Command-line equivalents (PowerShell, from the project folder):

```powershell
powershell.exe -NoProfile -File .\tools\build_android.ps1
powershell.exe -NoProfile -File .\tools\build_android.ps1 -CheckOnly
powershell.exe -NoProfile -File .\tools\build_android.ps1 -ForceFallbackSdk
```

## If you export in the Godot UI

Use **Project → Export → Android → Export Project**. Keep **Export With Debug** checked for this phone-test build. Save to `build/CarpetCleaner.apk`. Release exports require separately configured release signing credentials; reinstalling the SDK will not fix a missing release key.

## Match the error to the fix

| Error or symptom | Fix |
| --- | --- |
| Templates missing; a path ends in `4.7.2.stable.mono` | Close that editor and use **Open Game Editor.cmd**. The installed Android templates are for **standard 4.7.2.stable**. |
| Templates missing for `4.7.2.stable` | In the bundled editor, use **Editor → Manage Export Templates** and install the matching version. Don't mix engine/template versions. |
| No Android SDK / invalid Android SDK Path | In **Editor → Editor Settings → Export → Android**, set the SDK root listed below. It must contain `platform-tools/adb.exe`; do not select `platform-tools` itself. |
| Cannot read `platform-tools/adb.exe` | The builder records a warning and continues building the APK. ADB is needed for connected-phone discovery/deployment, not for creating the APK file. Check `build/android-build-launcher.log` before trying to deploy directly from Godot. |
| The Local AppData SDK appears completely missing only from the launcher | The builder automatically uses the complete SDK at `C:\Program Files (x86)\Android\android-sdk` for this build. It runs Godot with an isolated profile under `build/godot-build-profile`, without changing normal editor settings. |
| Java SDK / keytool not found | In the same screen, set the JDK root below, not its `bin` subfolder. |
| Release keystore or release password missing | For phone testing, check **Export With Debug**. This helper always does that. |
| Script, resource or import error | Read the first actual error in `build/android-build-console.log`. Fix that resource/code error; it isn't an SDK installation issue. |
| Export dialog looks stale but **Build APK.cmd** succeeds | Save the project, close old editor instances, reopen with **Open Game Editor.cmd**, then reopen Export. Record the exact dialog error if it persists. |

SDK paths verified on this computer:

```text
Build APK.cmd SDK: C:\Program Files (x86)\Android\android-sdk
Godot editor SDK:  C:\Users\Hursh\AppData\Local\Android\Sdk
Java SDK Path:    C:\Program Files\Java\jdk-21.0.12
Templates:       %APPDATA%\Godot\export_templates\4.7.2.stable
Builder tools:   35.0.0; Android platform 35
```

SDK/JDK paths are **user-wide Editor Settings**, not part of `project.godot`. When repairing them, first close older editor instances, then open one correct editor and set the paths there. Do not edit settings files externally while other editors may still save their cached settings. Do not regenerate the debug signing key to repair an SDK-path problem.

## Diagnosis recorded on 2026-09-20

The previous repair found a stale Desktop Mono executable reference. During this investigation, the shortcut, project editor metadata, SDK paths and standard templates were already correct. A fresh standard-editor export succeeded before changing project/export settings. The current reported UI failure could not be reproduced without its exact error message.

The menu and new Blender assets successfully exported. `Build APK.cmd` provides a reproducible route that avoids editor-selection and debug/release ambiguity. The fresh APK is signature-verified; installation and behavior on a physical phone have not been tested here.

Logs and build identity:

- `build/android-build-launcher.log`: copy of the latest preflight/build transcript. Timestamped `android-build-launcher-*.log` files preserve earlier failures instead of being overwritten by a later run.
- `build/android-build-console.log`: full export output and first failing step.
- `build/android-signature.log`: signature-verification result.
- `build/android-build-info.txt`: engine version, APK size, build time and SHA-256.

The reported `Android SDK Path is not a complete SDK` failure came from a split filesystem view. The SDK under Local AppData is visible from the Codex-managed environment, where it was installed and where exports succeeded, but an ordinary Explorer-launched `Hursh` process consistently sees both `platform-tools` and `build-tools` as missing. The path text, account, bitness and slash normalization are correct. The files were not deleted or quarantined. This is why checks from Codex passed while the user's double-click run failed against the same printed path.

`Build APK.cmd` now always selects the complete machine-wide Program Files SDK, whose permissions include ordinary and restricted desktop processes. Godot runs from an isolated build profile containing that SDK path, the matching template and a copy of the existing debug key. The normal Godot editor settings are never rewritten. Direct PowerShell use still detects the configured SDK and can fall back automatically. The launcher directly checks the build tools, platform, JDK, templates, export result and APK signature, and preserves timestamped diagnostics. No SDK reinstall or signing-key change was needed.

An end-to-end run of the `.cmd` also exposed a post-export `Get-FileHash` module-loading failure. Hashing now uses .NET directly and happens before the verified staged APK replaces the old output. The launcher no longer claims the old APK was kept for every possible post-export error.

Reference: Godot's [Android export setup](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) documents the two user-wide paths and debug/release signing distinction; its [command-line guide](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) documents `--export-debug`. The existing JDK 21 installation was tested successfully; no JDK replacement was needed.
