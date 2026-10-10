# Collect the phone's existing crash evidence

After a crash, connect the phone to this computer with a USB data cable. Unlock the phone, enable **Developer options > USB debugging** manually if needed, and accept the USB debugging authorization prompt. Double-click **Collect Android Crash Logs.cmd**. The collector reads existing evidence without starting or stopping the game, installing an APK, resetting saves, clearing logs, or changing phone settings. It does not run Godot.

The report is saved in **build/android-crash-reports/yyyyMMdd-HHmmss-fff/**. Read `summary.txt` first. Share that folder for diagnosis; collection does not upload it anywhere. Logs can expire or be overwritten, so collect soon after the failure. Rebooting, reinstalling, and repeatedly reopening the game may make the original evidence harder to recover.

For a phone already authorized through ADB, the collector can run while the game remains closed after the crash. Collection is a snapshot, not a live recording, and does not reproduce the failure. If no useful evidence remains, record the approximate crash time, phone model, cleaning tool, rug/store, and what happened immediately before it closed; collect another snapshot soon after the next naturally occurring failure.

## Select a phone or the matching APK

From PowerShell in the project folder:

```powershell
& '.\Collect Android Crash Logs.cmd' -Serial PHONE_SERIAL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\collect_android_crash_logs.ps1 -CheckOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\collect_android_crash_logs.ps1 -ApkPath 'S:\path\to\the-installed-build.apk'
```

`-CheckOnly` validates local tools/the APK and lists ADB device authorization; it reads no phone logs or app data. When several devices are visible, the collector refuses to choose one and prints their serials. Rerun with `-Serial`. An unauthorized/offline phone also stops collection before any phone logs are read. A missing device requires a data cable, working USB driver, and USB debugging authorization; the collector does not enable debugging automatically.

The SDK root comes from `build/android-build-info.txt`, then the pinned editor's Android SDK setting, then `%LOCALAPPDATA%\Android\Sdk`. Override it with `-SdkPath 'C:\path\to\Android\Sdk'` when necessary. The current recorded SDK is `C:\Users\Hurshuuuuuu\AppData\Local\Android\Sdk`. The helper calls only that SDK's `platform-tools\adb.exe` and `build-tools\…\aapt.exe`, never tools resolved from PATH. The exact app package/version is extracted from the local APK with `aapt dump badging`; Godot's `com.example.$genname` preset is not a usable package identifier. The default APK is `build/CarpetCleaner.apk`. If the installed build differs, pass its APK so version and hash metadata describe the relevant build.

## Evidence and limits

- `summary.json` / `summary.txt`: APK identity/hash, phone model/Android version, available EGL/Vulkan driver properties, installed version/update metadata, per-source counts, native/Java crash counts, bounded process/signal/top-stack evidence with its source filename, available exit reasons, and collection warnings. GPU renderer lines are included only when attributable to this app's logs.
- `app-exit-info.txt`: package-scoped Android process exit history when available. Android 11+ can distinguish native crashes, Java exceptions, ANRs, and some low-memory kills. A SIGKILL record alone does not prove low memory. History may include earlier game sessions; compare timestamps to the reported event.
- `app-crash-buffer.txt`: the crash buffer is always read separately, examining at most 8,000 recent entries by default. This preserves app-attributed native/Java crash blocks even when busy main/system buffers would push them outside a combined tail. Unrelated crashes are filtered out before writing.
- `app-crash-logcat.txt`: a separate bounded snapshot of the main/system buffers preserves exact package references, attributed Java/native crash blocks, and logs during a witnessed game-process lifetime. A historical PID alone is not trusted because Android can reuse it. `-TailLines` adjusts each of the two reads from 100 to 20,000 entries (8,000 each by default); broad unfiltered logs remain in memory only. Logs before a missing process-start marker may be omitted, and old crashes can still expire from the phone's crash buffer.
- `installed-app.txt`: selected package version/update fields; full package/activity dumps and general phone logs are not saved. Missing or unsupported diagnostics are recorded as warnings. Empty evidence does not demonstrate that the app did not crash.

This deliberately avoids a full bug report, contacts, files, screenshots, phone-wide property dumps, and app save data. App logs can still contain text the app itself logged; review the report before sharing it. A local SDK ADB server may start to service reads, but no phone app or phone setting is changed.

References: Android's [ADB device authorization and selection guide](https://developer.android.com/tools/adb), [logcat buffer/filter guide](https://developer.android.com/tools/logcat), [ApplicationExitInfo reasons](https://developer.android.com/reference/android/app/ApplicationExitInfo), and the [AOSP package-scoped exit-history implementation](https://android.googlesource.com/platform/frameworks/base/+/HEAD/services/core/java/com/android/server/am/AppExitInfoTracker.java).

## Confirmed brush-audio crash repair — 2026-10-08

The connected Pixel 6 Pro, running Android 17, recorded four native SIGSEGV crashes after the October 8 upgrade APK was installed. All four failed on the AudioTrack thread at the same instruction in the matching Godot 4.7.2 Mono Android library. The separate crash buffer retained the stacks after the busy main/system tail no longer contained them.

Both brush clips contain 176,400 PCM16 mono frames, with 176,399 as the last valid index. `GameAudio._voice()` incorrectly set `loop_end` to the frame count. The pinned WAV mixer can decode that endpoint inclusively. The fault instruction read `data + 176400 * 2`, exactly the guard-page address in all four tombstones. The corrected endpoint is `frame_count - 1`; frame counting also respects format and channel count. Music and brush effects remain enabled.

Validation completed with the pinned engine and isolated saves:

- Existing audio lifecycle suite: 71 checks, zero failures.
- Native loop-boundary suite: 124 checks, zero failures, including 36 mixer cases and 9.208 seconds of sustained brush playback.
- Physical Pixel sound check: 88 checks, zero failures in 32.157 seconds. During its initial 30 seconds, music wrapped once and each brush loop wrapped seven times; it then sought across each loop boundary 24 times and tested focus interruption/resume.
- The signed game APK was updated in place over USB. The player's save checksum was identical before and after installation. The separate sound-check app was removed after its result was copied locally.

Evidence is in `build/android-crash-reports/20261008-170919-245/app-crash-buffer.txt`, `build/android-symbolication/symbolication.json`, `build/audio_loop_bounds_validation.json`, and `build/android-audio-probe-result.json`. The fixed APK is recorded in `build/android-build-info.txt`, SHA-256 `2933A1B5B7C79E97946F920332C7BDF9D2C6B02897E0553C54ED3627B3CFA235`.

The opt-in hardware probe lives in `scenes/test/android_audio_probe.tscn`. Export it as the configured main scene in a separate package with `command_line/extra_args="-- --shop-test --audition-audio"`, then restore the normal scene/package/arguments. The official Android template rejects command-line scene-path overrides, so a scene path in the extra arguments will abort before the probe runs. The delivered game uses the normal Home scene and has no test launch arguments.

Mixer reference: [exact pinned Godot source](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/scene/resources/audio_stream_wav.cpp).
