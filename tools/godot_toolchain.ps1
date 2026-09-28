# Shared, fail-closed engine selection for editing, tests and Android exports.
# Never search PATH or fall back to another Godot installation.
function Get-ProjectGodot {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $bundle = Join-Path $root 'tools\godot\Godot_v4.7.2-stable_mono_win64'
    $console = Join-Path $bundle 'Godot_v4.7.2-stable_mono_win64_console.exe'
    $editor = Join-Path $bundle 'Godot_v4.7.2-stable_mono_win64.exe'
    foreach ($required in @(
        $console, $editor,
        (Join-Path $bundle 'GodotSharp\Tools\GodotTools.dll'),
        (Join-Path $bundle 'GodotSharp\Api\Debug\GodotSharp.dll'),
        (Join-Path $bundle 'GodotSharp\Tools\nupkgs\Godot.NET.Sdk.4.7.2.nupkg')
    )) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "The complete Godot 4.7.2 Mono/.NET bundle is required. Missing: $required. Restore the full official Windows .NET archive, including GodotSharp; no other engine will be used."
        }
    }
    $version = (& $console --version | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable\.mono\.') {
        throw "Refusing Godot '$version'. This project requires Godot 4.7.2 stable Mono/.NET only."
    }
    $dotnet = Get-Command dotnet.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $dotnet) { throw 'The Mono editor requires the .NET SDK. Install .NET 8 or newer, then reopen this launcher.' }
    $sdks = @(& $dotnet.Source --list-sdks)
    if ($LASTEXITCODE -ne 0 -or -not ($sdks | Where-Object { $_ -match '^(\d+)\.' -and [int]$Matches[1] -ge 8 })) {
        throw 'No .NET 8+ SDK is available. A runtime alone is not the C# build SDK.'
    }
    return [pscustomobject]@{
        Console = $console
        Editor = $editor
        Version = $version
        TemplateVersion = '4.7.2.stable.mono'
        Project = Join-Path $root 'CarpetToy'
    }
}
