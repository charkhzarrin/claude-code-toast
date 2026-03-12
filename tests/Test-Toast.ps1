<#
.SYNOPSIS
    Manual test: fires one notification of each type to preview all styles.
.DESCRIPTION
    Run this script to see all four notification types displayed on your system.
    Useful for verifying BurntToast installation and notification appearance.

    Usage: powershell -ExecutionPolicy Bypass -File tests\Test-Toast.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "Claude Code Toast — Manual Test" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Check BurntToast
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host "ERROR: BurntToast module not installed. Run install.ps1 first." -ForegroundColor Red
    exit 1
}
Import-Module BurntToast -Force

$iconPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
if (-not (Test-Path $iconPath)) {
    # Try local assets
    $iconPath = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\claude-icon.png"
}
if (-not (Test-Path $iconPath)) {
    Write-Host "WARNING: Icon not found. Notifications will use default icon." -ForegroundColor Yellow
    $iconPath = $null
}

# --- Test 1: Permission Prompt (Urgent) ---
Write-Host "[1/4] Permission Prompt (Urgent)..." -ForegroundColor Yellow
$params1 = @{
    Text             = "Claude Code — Permission Required",
                       "Claude wants to execute: git push origin main",
                       "D:\Projects\my-app"
    UniqueIdentifier = "test-permission"
}
if ($iconPath) { $params1["AppLogo"] = $iconPath }
$params1["Button"] = New-BTButton -Content "Open Claude" -Arguments "vscode://file/D:/Projects/my-app" -ActivationType Protocol
New-BurntToastNotification @params1
Write-Host "  Sent!" -ForegroundColor Green

Start-Sleep -Seconds 2

# --- Test 2: Idle Prompt (Default) ---
Write-Host "[2/4] Idle Prompt (Task Complete)..." -ForegroundColor Yellow
$params2 = @{
    Text             = "Claude Code — Task Complete",
                       "Finished implementing user authentication module with JWT tokens.",
                       "D:\Projects\my-app"
    UniqueIdentifier = "test-idle"
}
if ($iconPath) { $params2["AppLogo"] = $iconPath }
$params2["Button"] = New-BTButton -Content "Open Claude" -Arguments "vscode://file/D:/Projects/my-app" -ActivationType Protocol
New-BurntToastNotification @params2
Write-Host "  Sent!" -ForegroundColor Green

Start-Sleep -Seconds 2

# --- Test 3: Auth Success (Silent) ---
Write-Host "[3/4] Auth Success (Silent)..." -ForegroundColor Yellow
$params3 = @{
    Text             = "Claude Code", "Authentication successful."
    Silent           = $true
    UniqueIdentifier = "test-auth"
}
if ($iconPath) { $params3["AppLogo"] = $iconPath }
New-BurntToastNotification @params3
Write-Host "  Sent!" -ForegroundColor Green

Start-Sleep -Seconds 2

# --- Test 4: Elicitation Dialog (Reminder) ---
Write-Host "[4/4] Elicitation Dialog (Input Needed)..." -ForegroundColor Yellow
$params4 = @{
    Text             = "Claude Code — Input Needed",
                       "Which testing framework would you prefer: Jest or Vitest?",
                       "D:\Projects\my-app"
    UniqueIdentifier = "test-elicitation"
}
if ($iconPath) { $params4["AppLogo"] = $iconPath }
$params4["Button"] = New-BTButton -Content "Open Claude" -Arguments "vscode://file/D:/Projects/my-app" -ActivationType Protocol
New-BurntToastNotification @params4
Write-Host "  Sent!" -ForegroundColor Green

Write-Host ""
Write-Host "All 4 test notifications sent!" -ForegroundColor Green
Write-Host "Check your notification center if you missed any." -ForegroundColor White
