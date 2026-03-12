<#
.SYNOPSIS
    Registers the AppUserModelID (AUMID) for Claude Code Toast notifications.
.DESCRIPTION
    Creates a registry entry under HKCU so Windows can display branded toast
    notifications without requiring admin privileges.
#>
param(
    [string]$Aumid = "ClaudeCode.Toast",
    [string]$DisplayName = "Claude Code",
    [string]$IconPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $IconPath) {
    $IconPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
}

$regPath = "HKCU:\Software\Classes\AppUserModelId\$Aumid"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}

New-ItemProperty -Path $regPath -Name "DisplayName" -Value $DisplayName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "IconUri" -Value $IconPath -PropertyType String -Force | Out-Null
New-ItemProperty -Path $regPath -Name "IconBackgroundColor" -Value "FFDA7738" -PropertyType String -Force | Out-Null

Write-Host "Registered AUMID: $Aumid" -ForegroundColor Green
Write-Host "  DisplayName: $DisplayName"
Write-Host "  IconUri: $IconPath"
