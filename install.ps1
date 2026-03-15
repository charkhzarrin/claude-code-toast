<#
.SYNOPSIS
    One-command installer for Claude Code Toast notifications.
.DESCRIPTION
    Sets up Windows toast notifications for Claude Code:
    1. Installs BurntToast PowerShell module (user scope)
    2. Copies scripts and assets to %LOCALAPPDATA%\ClaudeCodeToast
    3. Registers AUMID in Windows registry (HKCU, no admin required)
    4. Adds Stop hook to Claude Code settings.json (no BOM)
    5. Sends a test notification

    Run: powershell -ExecutionPolicy Bypass -File install.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Toast - Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Check PowerShell version ---
Write-Host "[1/5] Checking PowerShell version..." -ForegroundColor Yellow
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or later required. You have $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}
Write-Host "  PowerShell $($PSVersionTable.PSVersion) - OK" -ForegroundColor Green

# --- Step 2: Install BurntToast ---
Write-Host "[2/5] Installing BurntToast module..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name BurntToast) {
    Write-Host "  BurntToast already installed - OK" -ForegroundColor Green
} else {
    try {
        Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber
        Write-Host "  BurntToast installed - OK" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to install BurntToast: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try: Install-Module BurntToast -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}
Import-Module BurntToast -Force

# --- Step 3: Copy files ---
Write-Host "[3/5] Installing files..." -ForegroundColor Yellow
$installDir = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
$sourceDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

foreach ($dir in @($installDir, "$installDir\src", "$installDir\config")) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$files = @(
    @{ Src = "assets\claude-icon.png";  Dst = "claude-icon.png" },
    @{ Src = "src\hook.ps1";            Dst = "src\hook.ps1" },
    @{ Src = "src\Register-AppId.ps1";  Dst = "src\Register-AppId.ps1" },
    @{ Src = "config\defaults.json";    Dst = "config\defaults.json" }
)
foreach ($f in $files) {
    $src = Join-Path $sourceDir $f.Src
    $dst = Join-Path $installDir $f.Dst
    if (Test-Path $src) { Copy-Item $src $dst -Force }
    else { Write-Host "  WARNING: not found: $src" -ForegroundColor Yellow }
}
Write-Host "  Files installed to: $installDir - OK" -ForegroundColor Green

# --- Step 4: Register AUMID ---
Write-Host "[4/5] Registering Windows App ID..." -ForegroundColor Yellow
& (Join-Path $installDir "src\Register-AppId.ps1") -IconPath (Join-Path $installDir "claude-icon.png")

# --- Step 5: Configure Claude Code hook ---
Write-Host "[5/5] Configuring Claude Code hook..." -ForegroundColor Yellow
$settingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"
$hookScript   = (Join-Path $installDir "src\hook.ps1") -replace '\\', '/'

$hookEntry = [ordered]@{
    matcher = ""
    hooks   = @(
        [ordered]@{
            type    = "command"
            command = "powershell.exe -ExecutionPolicy Bypass -NoProfile -NoLogo -NonInteractive -File `"$hookScript`""
            timeout = 10
        }
    )
}

# Read or create settings
if (Test-Path $settingsPath) {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
} else {
    $claudeDir = Split-Path $settingsPath -Parent
    if (-not (Test-Path $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null }
    $settings = [PSCustomObject]@{}
}

# Ensure hooks object exists
if (-not ($settings.PSObject.Properties.Name -contains "hooks")) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}

# Check if already installed
$alreadyInstalled = $false
if ($settings.hooks.PSObject.Properties.Name -contains "Stop") {
    foreach ($entry in @($settings.hooks.Stop)) {
        foreach ($h in @($entry.hooks)) {
            if ($h.command -like "*ClaudeCodeToast*") {
                $alreadyInstalled = $true; break
            }
        }
    }
}

# Also remove any old Notification hook from previous installs
if ($settings.hooks.PSObject.Properties.Name -contains "Notification") {
    $oldFiltered = @($settings.hooks.Notification | Where-Object {
        $keep = $true
        foreach ($h in @($_.hooks)) {
            if ($h.command -like "*ClaudeCodeToast*" -or $h.command -like "*Send-ClaudeToast*") { $keep = $false; break }
        }
        $keep
    })
    if ($oldFiltered.Count -eq 0) {
        $settings.hooks.PSObject.Properties.Remove("Notification")
        Write-Host "  Removed old Notification hook - OK" -ForegroundColor Green
    } else {
        $settings.hooks.Notification = $oldFiltered
    }
}

if ($alreadyInstalled) {
    Write-Host "  Stop hook already configured - OK" -ForegroundColor Green
} else {
    if ($settings.hooks.PSObject.Properties.Name -contains "Stop") {
        $existing = @($settings.hooks.Stop)
        $existing += $hookEntry
        $settings.hooks.Stop = $existing
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Stop" -NotePropertyValue @($hookEntry) -Force
    }
    Write-Host "  Stop hook added to: $settingsPath - OK" -ForegroundColor Green
}

# Write without BOM — critical: Set-Content -Encoding UTF8 adds BOM in PowerShell 5
$json     = $settings | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($settingsPath, $json, $utf8NoBom)

# Test notification
Write-Host ""
Write-Host "Sending test notification..." -ForegroundColor Yellow
try {
    $iconPath = Join-Path $installDir "claude-icon.png"
    New-BurntToastNotification `
        -Text "Claude Code Toast", "Installed! You'll be notified when Claude finishes a task." `
        -AppLogo $iconPath `
        -UniqueIdentifier "claude-install-test"
    Write-Host "Test notification sent - OK" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Test notification failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install location : $installDir" -ForegroundColor White
Write-Host "  Hook config      : $settingsPath" -ForegroundColor White
Write-Host ""
Write-Host "  To customize, create:" -ForegroundColor White
Write-Host "  $installDir\config.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Available config options:" -ForegroundColor White
Write-Host "    idleThresholdSeconds  (default: 30)" -ForegroundColor Gray
Write-Host "    cooldownSeconds       (default: 10)" -ForegroundColor Gray
Write-Host "    maxPerHour            (default: 30)" -ForegroundColor Gray
Write-Host "    sound                 (default: Default)" -ForegroundColor Gray
Write-Host "    silent                (default: false)" -ForegroundColor Gray
Write-Host "    vscodeVariant         (default: code)" -ForegroundColor Gray
Write-Host ""
Write-Host "  To uninstall:" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File uninstall.ps1" -ForegroundColor Cyan
Write-Host ""
