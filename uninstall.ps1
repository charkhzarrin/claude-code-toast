<#
.SYNOPSIS
    Removes Claude Code Toast notifications system.
.DESCRIPTION
    1. Removes Notification hook from Claude Code settings.json
    2. Removes AUMID registry entry
    3. Removes installed files from %LOCALAPPDATA%\ClaudeCodeToast
    4. Optionally removes BurntToast module

    Run: powershell -ExecutionPolicy Bypass -File uninstall.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Claude Code Toast — Uninstaller" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Remove hook from Claude Code settings ---
Write-Host "[1/4] Removing Claude Code hook..." -ForegroundColor Yellow
$claudeSettingsPath = Join-Path $env:USERPROFILE ".claude\settings.json"

if (Test-Path $claudeSettingsPath) {
    try {
        $settings = Get-Content $claudeSettingsPath -Raw | ConvertFrom-Json

        if ($settings.hooks -and ($settings.hooks.PSObject.Properties.Name -contains "Notification")) {
            $notifArray = @($settings.hooks.Notification)
            $filtered = @($notifArray | Where-Object {
                $dominated = $false
                foreach ($h in @($_.hooks)) {
                    if ($h.command -and $h.command -like "*Send-ClaudeToast*") {
                        $dominated = $true
                        break
                    }
                }
                -not $dominated
            })

            if ($filtered.Count -eq 0) {
                $settings.hooks.PSObject.Properties.Remove("Notification")
            } else {
                $settings.hooks.Notification = $filtered
            }

            $settings | ConvertTo-Json -Depth 10 | Set-Content $claudeSettingsPath -Encoding UTF8
            Write-Host "  Hook removed from settings.json — OK" -ForegroundColor Green
        } else {
            Write-Host "  No Claude Code Toast hook found — skipping" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  WARNING: Could not modify settings.json: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  settings.json not found — skipping" -ForegroundColor Yellow
}

# --- Step 2: Remove AUMID registry entry ---
Write-Host "[2/4] Removing Windows App ID registration..." -ForegroundColor Yellow
$regPath = "HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Toast"
if (Test-Path $regPath) {
    Remove-Item -Path $regPath -Recurse -Force
    Write-Host "  Registry entry removed — OK" -ForegroundColor Green
} else {
    Write-Host "  Registry entry not found — skipping" -ForegroundColor Yellow
}

# --- Step 3: Remove installed files ---
Write-Host "[3/4] Removing installed files..." -ForegroundColor Yellow
$installDir = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force
    Write-Host "  Removed: $installDir — OK" -ForegroundColor Green
} else {
    Write-Host "  Install directory not found — skipping" -ForegroundColor Yellow
}

# --- Step 4: Optionally remove BurntToast ---
Write-Host "[4/4] BurntToast module..." -ForegroundColor Yellow
if (Get-Module -ListAvailable -Name BurntToast) {
    $response = Read-Host "  Remove BurntToast module? Other scripts may use it. (y/N)"
    if ($response -eq "y" -or $response -eq "Y") {
        try {
            Uninstall-Module -Name BurntToast -Force -AllVersions
            Write-Host "  BurntToast removed — OK" -ForegroundColor Green
        } catch {
            Write-Host "  WARNING: Could not remove BurntToast: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  BurntToast kept — OK" -ForegroundColor Green
    }
} else {
    Write-Host "  BurntToast not installed — skipping" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Uninstall Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
