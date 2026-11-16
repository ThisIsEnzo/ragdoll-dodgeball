# Сборка place без живого синка Rojo. Запуск: pwsh tools/build.ps1
param(
    [string]$Project = "default.project.json",
    [string]$Out = "build/ragdoll-dodgeball.rbxlx",
    [switch]$NoOpen
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command rojo -ErrorAction SilentlyContinue)) {
    Write-Error "rojo не найден в PATH. Установи: aftman add rojo-rbx/rojo, затем aftman install"
    exit 1
}

$outDir = Split-Path -Parent $Out
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

Write-Host "Rojo:" (rojo --version)
Write-Host "Сборка $Project -> $Out"
rojo build $Project -o $Out
if ($LASTEXITCODE -ne 0) { Write-Error "rojo build завершился с ошибкой"; exit $LASTEXITCODE }

$size = [math]::Round((Get-Item $Out).Length / 1KB, 1)
Write-Host "Готово: $Out ($size KB)"

if (-not $NoOpen) { Start-Process $Out }
