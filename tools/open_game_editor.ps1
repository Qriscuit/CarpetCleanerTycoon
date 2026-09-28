param([string]$Scene = 'res://scenes/production/floating_home.tscn')
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'godot_toolchain.ps1')
    $toolchain = Get-ProjectGodot
    Write-Host "Opening $($toolchain.Version)"
    # Start-Process joins arguments into one Windows command line; quote paths.
    $arguments = '--path "' + $toolchain.Project + '" --editor "' + $Scene + '"'
    Start-Process -FilePath $toolchain.Editor -ArgumentList $arguments -WorkingDirectory $toolchain.Project
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
