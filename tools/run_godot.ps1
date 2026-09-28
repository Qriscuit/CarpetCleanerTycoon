# Forward all arguments unchanged after validating the project's pinned engine.
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'godot_toolchain.ps1')
    $toolchain = Get-ProjectGodot
    & $toolchain.Console @args
    exit $LASTEXITCODE
} catch {
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
