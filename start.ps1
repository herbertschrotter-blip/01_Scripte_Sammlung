# start.ps1
# Zweck: Startet direkt PhotoFolder-ReviewAndDelete

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Clear-Host

Write-Host "=================================" -ForegroundColor Cyan
Write-Host " PhotoFolder - Review & Delete" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan
Write-Host ""

# Direkt PhotoFolder starten
. "$PSScriptRoot\Module\PhotoFolder-ReviewAndDelete.ps1"

Write-Host ""
Write-Host "PhotoFolder beendet." -ForegroundColor Green