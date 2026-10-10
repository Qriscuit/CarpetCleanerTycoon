[CmdletBinding()]
param(
    [string]$Serial = '',
    [string]$SdkPath = '',
    [string]$ApkPath = '',
    [ValidateRange(100, 20000)][int]$TailLines = 8000,
    [switch]$CheckOnly
)

# Reads existing evidence only. Never launches/stops the game, installs anything,
# clears logs/data, changes a phone setting, or runs a Godot executable.
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$utf8 = New-Object Text.UTF8Encoding($false)

function Invoke-DiagnosticCommand([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 20) {
    # Direct process invocation; do not interpolate arguments into a shell.
    $quoted = foreach ($argument in $Arguments) {
        '"' + [regex]::Replace([regex]::Replace($argument, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = $quoted -join ' '
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill() # Only this local diagnostic client, never the phone app.
            $process.WaitForExit()
            return [pscustomobject]@{ ExitCode = -1; Output = ''; Error = 'Diagnostic read timed out.' }
        }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $stdout.Result; Error = $stderr.Result.Trim() }
    } finally { $process.Dispose() }
}

function Get-DiagnosticSdk {
    if ($SdkPath) { return [IO.Path]::GetFullPath($SdkPath) }
    $buildInfo = Join-Path $repository 'build\android-build-info.txt'
    if (Test-Path -LiteralPath $buildInfo -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $buildInfo) {
            if ($line -match '^SDK:\s*(.+)$') { return [IO.Path]::GetFullPath($Matches[1].Trim()) }
        }
    }
    $settings = Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
    if (Test-Path -LiteralPath $settings -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $settings) {
            if ($line -match '^export/android/android_sdk_path\s*=\s*(".*")\s*$') {
                return [IO.Path]::GetFullPath([string](ConvertFrom-Json $Matches[1]))
            }
        }
    }
    return Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}

function Get-ApkIdentity([string]$Sdk, [string]$Apk) {
    if (-not (Test-Path -LiteralPath $Apk -PathType Leaf)) {
        throw "APK not found: $Apk. Use -ApkPath for the APK that crashed; collection does not rebuild or install it."
    }
    $aapt = Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $aapt) { throw "No aapt.exe exists in the selected SDK's build-tools: $Sdk. The generated app package must be read from the APK, not guessed." }
    $badging = Invoke-DiagnosticCommand $aapt @('dump', 'badging', $Apk)
    if ($badging.ExitCode -ne 0 -or $badging.Output -notmatch "(?m)^package: name='([A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+)' versionCode='([^']*)' versionName='([^']*)'") {
        throw "Unable to read the APK package with SDK aapt. $($badging.Error)"
    }
    $package = $Matches[1]; $versionCode = $Matches[2]; $versionName = $Matches[3]
    $stream = [IO.File]::OpenRead($Apk)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try { $hash = ([BitConverter]::ToString($hasher.ComputeHash($stream))).Replace('-', '') }
    finally { $stream.Dispose(); $hasher.Dispose() }
    return [pscustomobject]@{ Package = $package; VersionCode = $versionCode; VersionName = $versionName; SHA256 = $hash; Path = $Apk }
}

function Select-DiagnosticDevice([string]$DeviceList, [string]$RequestedSerial) {
    $devices = @(foreach ($line in ($DeviceList -split '\r?\n')) {
        if ($line -match '^(\S+)\s+(device|unauthorized|offline|no permissions)\b') {
            [pscustomobject]@{ Serial = $Matches[1]; State = $Matches[2] }
        }
    })
    if ($RequestedSerial) {
        if ($RequestedSerial -notmatch '^[A-Za-z0-9_.:-]+$') { throw 'Invalid device serial. Copy the serial shown by the SDK adb devices command.' }
        $chosen = @($devices | Where-Object { $_.Serial -eq $RequestedSerial })
        if ($chosen.Count -ne 1) { throw "Selected phone '$RequestedSerial' is not visible to ADB. Connect it with a USB data cable and enable USB debugging manually." }
    } else {
        if ($devices.Count -eq 0) { throw 'No Android device is connected. Connect the phone with a USB data cable, enable Developer options > USB debugging manually, unlock it, and accept the USB debugging prompt. Then rerun this collector.' }
        if ($devices.Count -gt 1) { throw "Multiple Android devices are visible. Select one with -Serial; none was read. Visible devices: $(($devices | ForEach-Object { $_.Serial + ' (' + $_.State + ')' }) -join ', ')" }
        $chosen = @($devices[0])
    }
    if ($chosen[0].State -eq 'unauthorized') { throw "Phone '$($chosen[0].Serial)' is unauthorized. Unlock it and accept the USB debugging authorization prompt, then rerun. No phone logs were read." }
    if ($chosen[0].State -ne 'device') { throw "Phone '$($chosen[0].Serial)' is $($chosen[0].State). Reconnect/unlock it and check USB debugging manually, then rerun. No phone logs were read." }
    return $chosen[0].Serial
}

function Select-GameLogLines([string[]]$Lines, [string]$Package) {
    $packagePattern = '(?<![A-Za-z0-9_.])' + [regex]::Escape($Package) + '(?=[:/\s,)>''"\]]|$)'
    $keep = New-Object 'System.Collections.Generic.HashSet[int]'
    $active = New-Object 'System.Collections.Generic.HashSet[string]'
    $blocks = @{}
    $witnessed = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        # threadtime output uses emitting PID, not the crashed PID in a tombstone.
        if ($line -notmatch '^\d\d-\d\d\s+\d\d:\d\d:\d\d\.\d+\s+(\d+)\s+\d+\s+[VDIWEF]\s+([^:]+):\s?(.*)$') { continue }
        $emitter = $Matches[1]; $tag = $Matches[2].Trim(); $message = $Matches[3]
        if ($tag -eq 'ActivityManager' -and $message -match '\bStart proc (\d+):([A-Za-z0-9_.:]+)/') {
            $startedPid = $Matches[1]; $startedPackage = $Matches[2]
            $null = $active.Remove($startedPid)
            if ($startedPackage -eq $Package -or $startedPackage.StartsWith($Package + ':')) {
                $null = $active.Add($startedPid); $null = $witnessed.Add($startedPid)
            }
        }
        # Package lines and a witnessed process lifetime are the only broad-log attribution.
        if ($message -match $packagePattern -or $active.Contains($emitter)) { $null = $keep.Add($index) }
        if ($tag -in @('DEBUG', 'AndroidRuntime')) {
            $key = $tag + ':' + $emitter
            $identityName = ''
            if ($tag -eq 'DEBUG' -and $message -match '>>> ([A-Za-z0-9_.:]+) <<<') { $identityName = $Matches[1] }
            if ($tag -eq 'AndroidRuntime' -and $message -match '^Process: ([A-Za-z0-9_.:]+), PID:') { $identityName = $Matches[1] }
            $newBlock = ($tag -eq 'DEBUG' -and $message -match '^\*\*\* \*\*\*') -or ($tag -eq 'AndroidRuntime' -and $message -match '^FATAL EXCEPTION:')
            if ($identityName -and $blocks.ContainsKey($key) -and $blocks[$key].IdentityName -and $blocks[$key].IdentityName -ne $identityName) { $newBlock = $true }
            if ($newBlock -or -not $blocks.ContainsKey($key)) {
                if ($blocks.ContainsKey($key) -and $blocks[$key].Attributed) {
                    foreach ($entry in $blocks[$key].Indices) { $null = $keep.Add($entry) }
                }
                $blocks[$key] = [pscustomobject]@{ Indices = New-Object 'System.Collections.Generic.List[int]'; Attributed = $false; IdentityName = '' }
            }
            $blocks[$key].Indices.Add($index)
            if ($identityName) {
                $blocks[$key].IdentityName = $identityName
                $blocks[$key].Attributed = $identityName -eq $Package -or $identityName.StartsWith($Package + ':')
            }
        }
        if ($tag -eq 'ActivityManager' -and $message -match '\bProcess .+ \(pid (\d+)\) has died') { $null = $active.Remove($Matches[1]) }
        if ($tag -eq 'ActivityManager' -and $message -match '\bKilling (\d+):') { $null = $active.Remove($Matches[1]) }
        if ($tag -eq 'lmkd' -and $message -match "\bKill '[^']+' \((\d+)\)") { $null = $active.Remove($Matches[1]) }
    }
    foreach ($block in $blocks.Values) {
        if ($block.Attributed) { foreach ($entry in $block.Indices) { $null = $keep.Add($entry) } }
    }
    $selected = @($keep | Sort-Object | ForEach-Object { $Lines[$_] })
    return [pscustomobject]@{ Lines = $selected; WitnessedPids = @($witnessed | Sort-Object) }
}

function Get-GameCrashIndicators([string[]]$Lines) {
    $nativeIdentities = @($Lines | Where-Object { $_ -match '\bDEBUG\s*:.*\bpid:.*>>>' })
    $javaFatal = @($Lines | Where-Object { $_ -match '\bAndroidRuntime\s*:\s*FATAL EXCEPTION:' })
    $signals = @($Lines | Where-Object { $_ -match '\bDEBUG\s*:.*\bsignal \d+ \(' } | Select-Object -First 12)
    $evidence = @($Lines | Where-Object { $_ -match '\bDEBUG\s*:.*(\bpid:.*>>>|\bsignal \d+ \(|\bCause:|\bAbort message:|#0[0-7]\s+pc\b)' -or $_ -match '\bAndroidRuntime\s*:.*(FATAL EXCEPTION:|\bProcess:|\b[a-zA-Z0-9_.]+Exception:)' } | Select-Object -First 64)
    return [ordered]@{
        source_file = 'app-crash-buffer.txt'
        retained_lines = $Lines.Count
        native_crash_blocks = $nativeIdentities.Count
        java_fatal_exception_blocks = $javaFatal.Count
        signal_lines = $signals
        process_signal_and_stack_lines = $evidence
    }
}

function Invoke-AndroidCrashCollector {
    $sdk = Get-DiagnosticSdk
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adb -PathType Leaf)) { throw "Android SDK adb.exe not found: $adb. Use -SdkPath with the SDK root recorded by Build APK.cmd. No PATH executable will be used." }
    $apk = if ($ApkPath) { [IO.Path]::GetFullPath($ApkPath) } else { Join-Path $repository 'build\CarpetCleaner.apk' }
    $identity = Get-ApkIdentity $sdk $apk
    Write-Host "App: $($identity.Package) (APK version code $($identity.VersionCode))"
    Write-Host "SDK: $sdk"
    $deviceRead = Invoke-DiagnosticCommand $adb @('devices')
    if ($deviceRead.ExitCode -ne 0) { throw "Unable to list Android devices. $($deviceRead.Error)" }
    $selectedSerial = Select-DiagnosticDevice $deviceRead.Output $Serial
    if ($CheckOnly) { Write-Host 'Ready. Local APK/tool checks and device authorization passed; no phone logs or app data were read.'; return }
    Write-Host 'Reading existing crash evidence. Leave the game as it is; the collector does not launch it.'
    $prefix = @('-s', $selectedSerial)
    $installed = Invoke-DiagnosticCommand $adb ($prefix + @('shell', 'pm', 'path', $identity.Package))
    if ($installed.ExitCode -ne 0 -or $installed.Output -notmatch '(?m)^package:') { throw "The selected phone does not expose the APK package '$($identity.Package)'. Use -ApkPath for the installed build. $($installed.Error)" }
    $report = Join-Path $repository ('build\android-crash-reports\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    $null = New-Item -ItemType Directory -Path $report
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $phone = [ordered]@{}
    foreach ($property in @('ro.product.manufacturer', 'ro.product.model', 'ro.build.version.release', 'ro.build.version.sdk', 'ro.board.platform', 'ro.hardware.egl', 'ro.hardware.vulkan')) {
        $read = Invoke-DiagnosticCommand $adb ($prefix + @('shell', 'getprop', $property))
        $phone[$property] = $read.Output.Trim()
        if ($read.ExitCode -ne 0) { $warnings.Add("Property unavailable: $property. $($read.Error)") }
    }
    $packageRead = Invoke-DiagnosticCommand $adb ($prefix + @('shell', 'dumpsys', 'package', $identity.Package))
    $installedMetadata = @($packageRead.Output -split '\r?\n' | Where-Object { $_ -match '^\s*(versionCode=|versionName=|firstInstallTime=|lastUpdateTime=|userId=)' } | Select-Object -First 20)
    [IO.File]::WriteAllLines((Join-Path $report 'installed-app.txt'), [string[]]$installedMetadata, $utf8)
    if ($packageRead.ExitCode -ne 0) { $warnings.Add("Installed version metadata unavailable. $($packageRead.Error)") }
    $exitRead = Invoke-DiagnosticCommand $adb ($prefix + @('shell', 'dumpsys', 'activity', 'exit-info', $identity.Package))
    # Older Android builds may ignore an unknown subcommand and print general activity data.
    # Save only a recognized, explicitly package-scoped exit-info response.
    $exitLines = @()
    $exitPackages = @([regex]::Matches($exitRead.Output, '(?m)^\s*package:\s*(\S+)\s*$') | ForEach-Object { $_.Groups[1].Value })
    if ($exitRead.ExitCode -eq 0 -and $exitRead.Output -match 'ACTIVITY MANAGER PROCESS EXIT INFO' -and $exitPackages.Count -eq 1 -and $exitPackages[0] -eq $identity.Package) {
        $exitLines = @($exitRead.Output -split '\r?\n' | Select-Object -First 1500)
    } else { $warnings.Add('Package exit history is unavailable or has no records; this is normal on older Android versions. Unrecognized output was not saved.') }
    [IO.File]::WriteAllLines((Join-Path $report 'app-exit-info.txt'), [string[]]$exitLines, $utf8)
    # Give the crash buffer its own bounded read: busy main/system buffers must
    # never crowd out retained native/Java crash records in a combined tail.
    $crashRead = Invoke-DiagnosticCommand $adb ($prefix + @('logcat', '-b', 'crash', '-d', '-t', [string]$TailLines, '-v', 'threadtime')) 30
    $crashFiltered = Select-GameLogLines @($crashRead.Output -split '\r?\n') $identity.Package
    [IO.File]::WriteAllLines((Join-Path $report 'app-crash-buffer.txt'), [string[]]$crashFiltered.Lines, $utf8)
    if ($crashRead.ExitCode -ne 0) { $warnings.Add("Crash-buffer read failed or was incomplete. $($crashRead.Error)") }
    $crashIndicators = Get-GameCrashIndicators $crashFiltered.Lines
    $logRead = Invoke-DiagnosticCommand $adb ($prefix + @('logcat', '-b', 'main', '-b', 'system', '-d', '-t', [string]$TailLines, '-v', 'threadtime')) 30
    $filtered = Select-GameLogLines @($logRead.Output -split '\r?\n') $identity.Package
    [IO.File]::WriteAllLines((Join-Path $report 'app-crash-logcat.txt'), [string[]]$filtered.Lines, $utf8)
    if ($logRead.ExitCode -ne 0) { $warnings.Add("Main/system logcat read failed or was incomplete. $($logRead.Error)") }
    $gpuLines = @($filtered.Lines | Where-Object { $_ -match '(?i)(Vulkan|OpenGL|renderer|Adreno|Mali|PowerVR|GPU)' } | Select-Object -First 40)
    $exitReasons = @($exitLines | Where-Object { $_ -match '\breason=' } | Select-Object -First 12)
    $summary = [ordered]@{
        collected_at = (Get-Date).ToString('o')
        package = $identity.Package
        local_apk = $identity
        phone = $phone
        installed_app = $installedMetadata
        logcat_tail_limit_per_read = $TailLines
        retained_app_log_lines = $filtered.Lines.Count + $crashFiltered.Lines.Count
        main_system_log_file = 'app-crash-logcat.txt'
        retained_main_system_lines = $filtered.Lines.Count
        crash_buffer = $crashIndicators
        witnessed_app_process_starts = $filtered.WitnessedPids
        historical_exit_reason_lines = $exitReasons
        app_gpu_diagnostic_lines = $gpuLines
        warnings = @($warnings.ToArray())
        interpretation = 'Historical evidence only. Match the phone event timestamp and installed app version before attributing a cause; an empty report does not rule out a crash.'
    }
    [IO.File]::WriteAllText((Join-Path $report 'summary.json'), ($summary | ConvertTo-Json -Depth 6), $utf8)
    $summaryText = @(
        "App: $($identity.Package)",
        "Phone: $($phone['ro.product.manufacturer']) $($phone['ro.product.model']); Android $($phone['ro.build.version.release'])",
        "Retained main/system app lines: $($filtered.Lines.Count); app crash-buffer lines: $($crashFiltered.Lines.Count) (each read examines at most $TailLines recent entries)",
        "Crash-buffer native blocks: $($crashIndicators.native_crash_blocks); Java fatal-exception blocks: $($crashIndicators.java_fatal_exception_blocks)",
        'Crash-buffer process/signal/top-stack evidence (app-crash-buffer.txt):'
    ) + $crashIndicators.process_signal_and_stack_lines + @(
        '',
        'Recent historical exit reasons (may include unrelated earlier game sessions):'
    ) + $exitReasons + @('', $summary.interpretation) + @($warnings.ToArray())
    [IO.File]::WriteAllLines((Join-Path $report 'summary.txt'), [string[]]$summaryText, $utf8)
    Write-Host "Saved: $report" -ForegroundColor Green
    if ($warnings.Count) { Write-Warning ($warnings -join "`n") }
}

# Dot-sourcing exposes pure filtering/device-selection helpers for offline fixtures.
if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-AndroidCrashCollector }
    catch { Write-Host ("Collection could not finish: " + $_.Exception.Message) -ForegroundColor Red; exit 1 }
}
