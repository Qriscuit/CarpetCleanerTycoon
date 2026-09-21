[CmdletBinding()]
param([switch]$CheckOnly, [switch]$ForceFallbackSdk)

# Pins the standard editor and debug export, checks the actual configured tools,
# and only replaces the last APK after successful export AND signature checking.
# No installs, editor shutdowns, global settings edits, or signing-key changes.
$ErrorActionPreference = 'Stop'
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$project = Join-Path $repository 'CarpetToy'
$buildDirectory = Join-Path $repository 'build'
$engine = Join-Path $repository 'tools\godot\Godot_v4.7.2-stable_win64_console.exe'
$settingsFile = Join-Path $env:APPDATA 'Godot\editor_settings-4.7.tres'
$templateDirectory = Join-Path $env:APPDATA 'Godot\export_templates\4.7.2.stable'
$finalApk = Join-Path $buildDirectory 'CarpetCleaner.apk'
$originalJavaHome = $env:JAVA_HOME
$originalPath = $env:PATH
$originalAppData = $env:APPDATA
$exitStatus = 0
$transcriptStarted = $false
$launcherLog = Join-Path $buildDirectory ('android-build-launcher-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.log')
$latestLauncherLog = Join-Path $buildDirectory 'android-build-launcher.log'

function Require-File([string]$Path, [string]$Help) {
    # Probe the actual file instead of reducing missing, inaccessible and transient
    # file-update errors to Test-Path's single false result.
    $fullPath = [IO.Path]::GetFullPath($Path.Replace('/', '\'))
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            if ($item.PSIsContainer) { throw "Expected a file, found a folder: $fullPath" }
            $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
            $stream.Dispose()
            return
        } catch {
            if ($attempt -lt 2) { Start-Sleep -Milliseconds 250; continue }
            throw "$Help`nChecked file: $fullPath`nWindows reported: $($_.Exception.Message)"
        }
    }
}

function Normalize-ToolPath([string]$Path, [string]$SettingName) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$SettingName is empty in Editor Settings > Export > Android. See design/Android_APK.md." }
    $normalized = $Path.Trim().Replace('/', '\')
    if (-not [IO.Path]::IsPathRooted($normalized)) { throw "$SettingName must be an absolute folder path: $Path" }
    return [IO.Path]::GetFullPath($normalized)
}

function Read-ToolPath([string]$Name) {
    $pattern = '^' + [regex]::Escape($Name) + '\s*=\s*(".*")\s*$'
    foreach ($line in Get-Content -LiteralPath $settingsFile) {
        if ($line -match $pattern) {
            return [string](ConvertFrom-Json -InputObject $Matches[1])
        }
    }
    return ''
}

function Inspect-AndroidSdk([string]$SdkPath) {
    try {
        $buildToolsRoot = Join-Path $SdkPath 'build-tools'
        $buildTools = Get-ChildItem -LiteralPath $buildToolsRoot -Directory -ErrorAction Stop |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName 'lib\apksigner.jar')) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'zipalign.exe')) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'aapt.exe'))
            } | Select-Object -First 1
        if ($null -eq $buildTools) { throw "No complete build-tools version was found under $buildToolsRoot" }
        $platform = Get-ChildItem -LiteralPath (Join-Path $SdkPath 'platforms') -Directory -ErrorAction Stop |
            Where-Object { $_.Name -match '^android-\d+$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'android.jar')) } |
            Sort-Object { [int]($_.Name -replace '^android-','') } -Descending | Select-Object -First 1
        if ($null -eq $platform) { throw "No complete Android platform was found under $(Join-Path $SdkPath 'platforms')" }
        return [pscustomobject]@{ Sdk = $SdkPath; BuildTools = $buildTools; Platform = $platform; Error = '' }
    } catch {
        return [pscustomobject]@{ Sdk = $SdkPath; BuildTools = $null; Platform = $null; Error = $_.Exception.Message }
    }
}

function Set-GodotStringSetting([string]$Text, [string]$Name, [string]$Value) {
    $line = $Name + ' = ' + (ConvertTo-Json -InputObject $Value -Compress)
    $pattern = '(?m)^' + [regex]::Escape($Name) + '\s*=.*$'
    if ([regex]::IsMatch($Text, $pattern)) { return [regex]::Replace($Text, $pattern, $line) }
    return $Text.TrimEnd() + "`r`n" + $line + "`r`n"
}

function Prepare-BuildProfile([string]$SdkPath, [string]$JdkPath) {
    $profileAppData = Join-Path $buildDirectory 'godot-build-profile\AppData\Roaming'
    $profileGodot = Join-Path $profileAppData 'Godot'
    $profileTemplates = Join-Path $profileGodot 'export_templates\4.7.2.stable'
    $profileKeystores = Join-Path $profileGodot 'keystores'
    New-Item -ItemType Directory -Path $profileTemplates,$profileKeystores -Force | Out-Null

    $sourceTemplate = Join-Path $templateDirectory 'android_debug.apk'
    $targetTemplate = Join-Path $profileTemplates 'android_debug.apk'
    $sourceTemplateInfo = Get-Item -LiteralPath $sourceTemplate -Force
    $copyTemplate = -not (Test-Path -LiteralPath $targetTemplate -PathType Leaf)
    if (-not $copyTemplate) {
        $targetTemplateInfo = Get-Item -LiteralPath $targetTemplate -Force
        $copyTemplate = $targetTemplateInfo.Length -ne $sourceTemplateInfo.Length -or $targetTemplateInfo.LastWriteTimeUtc -ne $sourceTemplateInfo.LastWriteTimeUtc
    }
    if ($copyTemplate) {
        Write-Host 'Preparing the isolated Godot build profile...'
        Copy-Item -LiteralPath $sourceTemplate -Destination $targetTemplate -Force
    }

    $sourceKeystore = Normalize-ToolPath (Read-ToolPath 'export/android/debug_keystore') 'Android debug keystore'
    Require-File $sourceKeystore 'Godot debug keystore is missing. Open the bundled editor once to recreate it.'
    $targetKeystore = Join-Path $profileKeystores 'debug.keystore'
    Copy-Item -LiteralPath $sourceKeystore -Destination $targetKeystore -Force

    $profileSettings = Join-Path $profileGodot 'editor_settings-4.7.tres'
    $settingsText = [IO.File]::ReadAllText($settingsFile)
    $settingsText = Set-GodotStringSetting $settingsText 'export/android/android_sdk_path' $SdkPath
    $settingsText = Set-GodotStringSetting $settingsText 'export/android/java_sdk_path' $JdkPath
    $settingsText = Set-GodotStringSetting $settingsText 'export/android/debug_keystore' $targetKeystore
    [IO.File]::WriteAllText($profileSettings, $settingsText, (New-Object Text.UTF8Encoding($false)))
    return $profileAppData
}

try {
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    Start-Transcript -LiteralPath $launcherLog -Force | Out-Null
    $transcriptStarted = $true
    Write-Host "Launcher log: $launcherLog"
    Write-Host 'Checking Android export setup...' -ForegroundColor Cyan
    Require-File $engine 'The bundled standard Godot 4.7.2 is missing from tools/godot. Restore that version, not the Desktop Mono editor.'
    Require-File (Join-Path $project 'export_presets.cfg') 'Android export preset is missing. Restore CarpetToy/export_presets.cfg.'
    Require-File $settingsFile 'Godot editor settings are missing. Open the bundled editor and set Editor Settings > Export > Android paths. See design/Android_APK.md.'
    Require-File (Join-Path $templateDirectory 'android_debug.apk') 'Standard 4.7.2 Android templates are missing or unreadable. Use Editor > Manage Export Templates in the bundled STANDARD editor. See design/Android_APK.md.'

    $version = (& $engine --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable\.' -or $version -match 'mono') {
        throw "Unexpected editor version: $version. This project uses standard Godot 4.7.2."
    }

    $configuredSdk = Normalize-ToolPath (Read-ToolPath 'export/android/android_sdk_path') 'Android SDK Path'
    $jdk = Normalize-ToolPath (Read-ToolPath 'export/android/java_sdk_path') 'Java SDK Path'
    Write-Host "Settings: $settingsFile"
    Write-Host "Configured SDK: $configuredSdk"
    $fallbackSdk = 'C:\Program Files (x86)\Android\android-sdk'
    $sdkCandidates = @()
    if (-not $ForceFallbackSdk) { $sdkCandidates += $configuredSdk }
    if ($fallbackSdk -notin $sdkCandidates) { $sdkCandidates += $fallbackSdk }
    $selectedSdk = $null
    foreach ($candidate in $sdkCandidates) {
        $inspection = Inspect-AndroidSdk $candidate
        if ($null -ne $inspection.BuildTools) {
            $selectedSdk = $inspection
            break
        }
        Write-Warning "Android SDK candidate is unavailable: $candidate`n$($inspection.Error)"
    }
    if ($null -eq $selectedSdk) { throw 'No readable, complete Android SDK was found. See the candidate errors above.' }
    $sdk = $selectedSdk.Sdk
    $buildTools = $selectedSdk.BuildTools
    if ($sdk -ne $configuredSdk) {
        if ($ForceFallbackSdk) {
            Write-Host "Using the machine-wide SDK selected by Build APK.cmd: $sdk"
        } else {
            Write-Warning "The configured Local AppData SDK is not visible to this launcher. Using the installed Program Files SDK for this build only: $sdk"
        }
    }
    $adb = Join-Path $sdk 'platform-tools\adb.exe'
    $adbAvailable = $true
    try {
        Require-File $adb 'Cannot read Android platform-tools/adb.exe.'
    } catch {
        $adbAvailable = $false
        Write-Warning ($_.Exception.Message + "`nContinuing without ADB: it is used to discover/deploy to connected phones, not to create this APK file.")
    }
    $java = Join-Path $jdk 'bin\java.exe'
    Require-File $java "Java SDK Path is invalid: $jdk. Choose the JDK folder containing bin/java.exe."
    Require-File (Join-Path $jdk 'bin\keytool.exe') 'Java SDK Path points to a runtime rather than a full JDK; bin/keytool.exe is required.'
    $signerJar = Join-Path $buildTools.FullName 'lib\apksigner.jar'
    $env:JAVA_HOME = $jdk
    $env:PATH = (Join-Path $jdk 'bin') + ';' + $originalPath
    & $java --version | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw 'The configured Java installation could not run.' }
    Write-Host "Godot: $version"
    Write-Host "SDK:   $sdk"
    Write-Host "JDK:   $jdk"
    Write-Host "Tools: $($buildTools.Name)"
    Write-Host "Platform: $($selectedSdk.Platform.Name)"
    Write-Host ('ADB:   ' + $(if ($adbAvailable) { 'available' } else { 'unavailable (APK export continues)' }))

    if (-not $CheckOnly) {
        New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
        $stagingApk = Join-Path $buildDirectory ('CarpetCleaner-building-' + [guid]::NewGuid().ToString('N') + '.apk')
        $consoleLog = Join-Path $buildDirectory 'android-build-console.log'
        $engineLog = Join-Path $buildDirectory 'android-build.log'
        $verifyLog = Join-Path $buildDirectory 'android-signature.log'
        Write-Host 'Building a signed debug APK from the files saved on disk...' -ForegroundColor Cyan
        $buildAppData = Prepare-BuildProfile $sdk $jdk
        try {
            $env:APPDATA = $buildAppData
            & $engine --headless --path $project --log-file $engineLog --export-debug Android $stagingApk *> $consoleLog
            $exportExit = $LASTEXITCODE
        } finally {
            $env:APPDATA = $originalAppData
        }
        if ($exportExit -ne 0 -or -not (Test-Path -LiteralPath $stagingApk)) {
            Get-Content -LiteralPath $consoleLog -Tail 28 | ForEach-Object { Write-Host $_ }
            throw "Godot export failed (exit $exportExit). Full log: $consoleLog"
        }
        if (Select-String -LiteralPath $consoleLog -Pattern 'SCRIPT ERROR:|ERROR:' -Quiet) {
            throw "Godot reported errors despite completing. The previous APK is preserved; inspect $consoleLog."
        }
        & $java -jar $signerJar verify --verbose $stagingApk *> $verifyLog
        if ($LASTEXITCODE -ne 0) { throw "APK signature verification failed. See $verifyLog. The previous APK was preserved." }
        # .NET is already required by Windows PowerShell. Avoid relying on
        # Get-FileHash module auto-loading, which can differ between launchers.
        $hashStream = [IO.File]::OpenRead($stagingApk)
        $hasher = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = [BitConverter]::ToString($hasher.ComputeHash($hashStream)).Replace('-', '')
        } finally {
            $hashStream.Dispose()
            $hasher.Dispose()
        }
        Move-Item -LiteralPath $stagingApk -Destination $finalApk -Force
        if (Test-Path -LiteralPath ($stagingApk + '.idsig')) {
            Move-Item -LiteralPath ($stagingApk + '.idsig') -Destination ($finalApk + '.idsig') -Force
        } elseif (Test-Path -LiteralPath ($finalApk + '.idsig')) {
            # Only the old companion of this exact output; never a recursive delete.
            Remove-Item -LiteralPath ($finalApk + '.idsig')
        }
        $apk = Get-Item -LiteralPath $finalApk
        @(
            "Built: $(Get-Date -Format o)", "Engine: $version", 'Preset: Android (debug, signed)',
            "SDK: $sdk", "Build tools: $($buildTools.Name)", "Platform: $($selectedSdk.Platform.Name)",
            "APK: $finalApk", "Bytes: $($apk.Length)", "SHA256: $hash", 'Signature: verified'
        ) | Set-Content -LiteralPath (Join-Path $buildDirectory 'android-build-info.txt') -Encoding UTF8
        Write-Host "SUCCESS: $finalApk" -ForegroundColor Green
        Write-Host ('Signed and verified. {0:N1} MiB. Copy this APK to your phone.' -f ($apk.Length / 1MB))
    } else {
        Write-Host 'Preflight passed. No settings or APKs were changed.' -ForegroundColor Green
    }
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'Recovery checklist: design/Android_APK.md'
    $exitStatus = 1
} finally {
    $env:JAVA_HOME = $originalJavaHome
    $env:PATH = $originalPath
    $env:APPDATA = $originalAppData
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
        Copy-Item -LiteralPath $launcherLog -Destination $latestLauncherLog -Force
    }
}
exit $exitStatus
