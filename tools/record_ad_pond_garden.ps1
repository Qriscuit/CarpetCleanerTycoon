param(
    [ValidateSet('smoke', 'full')][string]$Mode = 'smoke',
    [string]$SessionName = ('pond-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff')),
    [string]$ResumeSession = '',
    [int]$ResumeLane = 2,
    [int]$ResumePass = 2
)
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$captureRoot = [IO.Path]::GetFullPath((Join-Path $workspace 'build\ad-capture-v5'))
$session = [IO.Path]::GetFullPath((Join-Path $captureRoot $SessionName))
if (-not $session.StartsWith($captureRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Capture session must stay within build/ad-capture-v5.' }
if (Test-Path -LiteralPath $session) { throw 'Select a fresh session; existing evidence is never overwritten.' }
$projectSource = Join-Path $workspace 'CarpetToy'
$snapshot = Join-Path $session 'project'
New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
$hashes = [Collections.Generic.List[object]]::new()
foreach ($item in @('assets', 'resources', 'scenes', 'scripts', 'icon.svg', 'project.godot')) {
    $sourceItem = Join-Path $projectSource $item
    Copy-Item -LiteralPath $sourceItem -Destination $snapshot -Recurse -Force
    $files = if ((Get-Item -LiteralPath $sourceItem).PSIsContainer) { @(Get-ChildItem -LiteralPath $sourceItem -Recurse -File) } else { @((Get-Item -LiteralPath $sourceItem)) }
    foreach ($sourceFile in $files) {
        $relative = $sourceFile.FullName.Substring($projectSource.Length + 1)
        $snapshotFile = Join-Path $snapshot $relative
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $copyHash = (Get-FileHash -LiteralPath $snapshotFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($sourceHash -ne $copyHash) { throw "Source snapshot hash mismatch: $relative" }
        $hashes.Add([pscustomobject]@{ path = $relative.Replace('\','/'); sha256 = $sourceHash; snapshot_sha256 = $copyHash })
    }
}
$projectConfig = Join-Path $snapshot 'project.godot'
$configText = [IO.File]::ReadAllText($projectConfig)
$configText = $configText.Replace('window/size/viewport_width=720', 'window/size/viewport_width=1080').Replace('window/size/viewport_height=1000', 'window/size/viewport_height=1920').Replace('window/stretch/mode="canvas_items"', 'window/stretch/mode="viewport"')
[IO.File]::WriteAllText($projectConfig, $configText, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{ source_root = $projectSource; snapshot_root = $snapshot; snapshot_matches_source_before_viewport_config = $true; capture_only_project_config_changes = @('1080x1920 viewport', 'viewport stretch'); files = $hashes } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $session 'source_manifest.json') -Encoding utf8
$taskAppData = Join-Path $session 'profile\Roaming'
$taskLocalData = Join-Path $session 'profile\Local'
New-Item -ItemType Directory -Path $taskAppData,$taskLocalData -Force | Out-Null
$oldAppData = $env:APPDATA
$oldLocalData = $env:LOCALAPPDATA
try {
    $env:APPDATA = $taskAppData
    $env:LOCALAPPDATA = $taskLocalData
    $wrapper = Join-Path $PSScriptRoot 'run_godot.ps1'
    $importArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$wrapper,'--headless','--editor','--path',$snapshot,'--import','--quit','--','--shop-test')
    & pwsh.exe @importArgs *> (Join-Path $session 'import.log')
    if ($LASTEXITCODE -ne 0) { throw 'Pinned engine source-snapshot import failed. See import.log.' }
    $driver = Join-Path $PSScriptRoot 'capture_ad_pond_garden.gd'
    Copy-Item -LiteralPath $driver -Destination (Join-Path $session 'capture_driver_used.gd')
    $recordArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$wrapper,'--path',$snapshot,'--script',$driver,'--resolution','540x960','--position','30,30','--write-movie',(Join-Path $session 'restorations.avi'),'--fixed-fps','30','--audio-driver','Dummy','--log-file',(Join-Path $session 'engine.log'),'--','--shop-test','--audition-audio',('--ad-capture-mode=' + $Mode),('--ad-session-name=' + $SessionName))
    if ($ResumeSession) { $recordArgs += @(('--ad-resume-session=' + $ResumeSession), ('--ad-resume-lane=' + $ResumeLane), ('--ad-resume-pass=' + $ResumePass)) }
    & pwsh.exe @recordArgs *> (Join-Path $session 'console.log')
    $captureExit = $LASTEXITCODE
    [pscustomobject]@{session=$session;mode=$Mode;exit_code=$captureExit;movie=(Join-Path $session 'restorations.avi');manifest=(Join-Path $session 'take_manifest.json')} | ConvertTo-Json
    exit $captureExit
} finally {
    $env:APPDATA = $oldAppData
    $env:LOCALAPPDATA = $oldLocalData
}
