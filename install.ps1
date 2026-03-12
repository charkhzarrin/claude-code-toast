<#
.SYNOPSIS
    One-command installer for Claude Code Toast notifications.
.DESCRIPTION
    Sets up everything needed for rich Windows toast notifications from Claude Code:
    1. Installs BurntToast PowerShell module (user scope)
    2. Registers AUMID in Windows registry (HKCU, no admin)
    3. Copies assets and scripts to %LOCALAPPDATA%\ClaudeCodeToast
    4. Merges Notification hook into Claude Code settings.json
    5. Fires a test notification to confirm it works

    Run: powershell -ExecutionPolicy Bypass -File install.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Toast — Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Check PowerShell version ---
Write-Host "[1/6] Checking PowerShell version..." -ForegroundColor Yellow
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host "ERROR: PowerShell 5.1 or later is required. You have $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}
Write-Host "  PowerShell $($PSVersionTable.PSVersion) — OK" -ForegroundColor Green

# --- Step 2: Install BurntToast ---
Write-Host "[2/6] Installing BurntToast module..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name BurntToast) {
    Write-Host "  BurntToast already installed — OK" -ForegroundColor Green
} else {
    try {
        Install-Module -Name BurntToast -Scope CurrentUser -Force -AllowClobber
        Write-Host "  BurntToast installed successfully — OK" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to install BurntToast. Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Try running manually: Install-Module BurntToast -Scope CurrentUser -Force" -ForegroundColor Yellow
        exit 1
    }
}
Import-Module BurntToast -Force

# --- Step 3: Copy files to LOCALAPPDATA ---
Write-Host "[3/6] Installing files..." -ForegroundColor Yellow
$installDir = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Create directory structure
$dirs = @(
    $installDir,
    (Join-Path $installDir "src"),
    (Join-Path $installDir "src\notifications"),
    (Join-Path $installDir "config")
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Copy files
$fileMappings = @(
    @{ Src = "assets\claude-icon.png";                  Dst = "claude-icon.png" },
    @{ Src = "src\Send-ClaudeToast.ps1";                Dst = "src\Send-ClaudeToast.ps1" },
    @{ Src = "src\Config.ps1";                          Dst = "src\Config.ps1" },
    @{ Src = "src\Register-AppId.ps1";                  Dst = "src\Register-AppId.ps1" },
    @{ Src = "src\notifications\PermissionPrompt.ps1";  Dst = "src\notifications\PermissionPrompt.ps1" },
    @{ Src = "src\notifications\IdlePrompt.ps1";        Dst = "src\notifications\IdlePrompt.ps1" },
    @{ Src = "src\notifications\AuthSuccess.ps1";       Dst = "src\notifications\AuthSuccess.ps1" },
    @{ Src = "src\notifications\ElicitationDialog.ps1"; Dst = "src\notifications\ElicitationDialog.ps1" },
    @{ Src = "config\defaults.json";                    Dst = "config\defaults.json" }
)

foreach ($mapping in $fileMappings) {
    $srcPath = Join-Path $sourceDir $mapping.Src
    $dstPath = Join-Path $installDir $mapping.Dst
    if (Test-Path $srcPath) {
        Copy-Item -Path $srcPath -Destination $dstPath -Force
    } else {
        Write-Host "  WARNING: Source file not found: $srcPath" -ForegroundColor Yellow
    }
}
Write-Host "  Files installed to: $installDir — OK" -ForegroundColor Green

# --- Step 4: Register AUMID ---
Write-Host "[4/6] Registering Windows App ID..." -ForegroundColor Yellow
$iconPath = Join-Path $installDir "claude-icon.png"
& (Join-Path $installDir "src\Register-AppId.ps1") -IconPath $iconPath

# --- Step 5: Configure Claude Code hook ---
Write-Host "[5/6] Configuring Claude Code hook..." -ForegroundColor Yellow
$claudeSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

$sendToastScript = (Join-Path $installDir "src\Send-ClaudeToast.ps1") -replace '\\', '/'

$hookEntry = @{
    matcher = ""
    hooks = @(
        @{
            type    = "command"
            command = "powershell.exe -ExecutionPolicy Bypass -NoProfile -File `"$sendToastScript`""
            timeout = 10
        }
    )
}

if (Test-Path $claudeSettingsPath) {
    $settings = Get-Content $claudeSettingsPath -Raw | ConvertFrom-Json
} else {
    # Create .claude directory if needed
    $claudeDir = Split-Path $claudeSettingsPath -Parent
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }
    $settings = [PSCustomObject]@{}
}

# Ensure hooks object exists
if (-not ($settings.PSObject.Properties.Name -contains "hooks")) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue ([PSCustomObject]@{})
}

# Check if Notification hook already exists with our command
$existingNotifHooks = $settings.hooks.PSObject.Properties.Name -contains "Notification"
$alreadyInstalled = $false

if ($existingNotifHooks) {
    $notifArray = @($settings.hooks.Notification)
    foreach ($entry in $notifArray) {
        foreach ($h in @($entry.hooks)) {
            if ($h.command -and $h.command -like "*Send-ClaudeToast*") {
                $alreadyInstalled = $true
                break
            }
        }
    }
}

if ($alreadyInstalled) {
    Write-Host "  Claude Code hook already configured — OK" -ForegroundColor Green
} else {
    if ($existingNotifHooks) {
        # Append to existing Notification array
        $existingArray = @($settings.hooks.Notification)
        $existingArray += $hookEntry
        $settings.hooks.Notification = $existingArray
    } else {
        $settings.hooks | Add-Member -NotePropertyName "Notification" -NotePropertyValue @($hookEntry) -Force
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content $claudeSettingsPath -Encoding UTF8
    Write-Host "  Hook added to: $claudeSettingsPath — OK" -ForegroundColor Green
}

# --- Step 6: Test notification ---
Write-Host "[6/6] Sending test notification..." -ForegroundColor Yellow
try {
    New-BurntToastNotification `
        -Text "Claude Code Toast", "Installation successful! You will now receive notifications from Claude Code." `
        -AppLogo $iconPath `
        -UniqueIdentifier "claude-install-test"
    Write-Host "  Test notification sent — OK" -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Test notification failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "  Notifications may still work. Check error.log for details." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Install location: $installDir" -ForegroundColor White
Write-Host "  Hook config:      $claudeSettingsPath" -ForegroundColor White
Write-Host ""
Write-Host "  To customize, create:" -ForegroundColor White
Write-Host "  $installDir\config.json" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To uninstall, run:" -ForegroundColor White
Write-Host "  powershell -ExecutionPolicy Bypass -File uninstall.ps1" -ForegroundColor Cyan
Write-Host ""
