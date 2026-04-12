<#
.SYNOPSIS
    Integration test: simulates Claude Code hook by piping JSON to the dispatcher.
.DESCRIPTION
    Tests the full hook flow by sending JSON payloads to Send-ClaudeToast.ps1
    via stdin, exactly as Claude Code would do.

    Usage: powershell -ExecutionPolicy Bypass -File tests\Test-Integration.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "Claude Code Toast — Integration Test" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

$dispatcherPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\src\Send-ClaudeToast.ps1"
if (-not (Test-Path $dispatcherPath)) {
    # Try local source
    $dispatcherPath = Join-Path (Split-Path -Parent $PSScriptRoot) "src\Send-ClaudeToast.ps1"
}
if (-not (Test-Path $dispatcherPath)) {
    Write-Host "ERROR: Send-ClaudeToast.ps1 not found. Run install.ps1 first." -ForegroundColor Red
    exit 1
}

# --- Test payloads ---
$testCases = @(
    @{
        Name = "permission_prompt"
        Json = @{
            session_id        = "test-session-001"
            transcript_path   = "C:\Users\test\.claude\transcripts\test.jsonl"
            cwd               = "D:\Projects\my-app"
            permission_mode   = "default"
            hook_event_name   = "Notification"
            message           = "Claude wants to execute: rm -rf node_modules && npm install"
            title             = "Permission Required"
            notification_type = "permission_prompt"
        } | ConvertTo-Json -Compress
    },
    @{
        Name = "idle_prompt"
        Json = @{
            session_id        = "test-session-002"
            transcript_path   = "C:\Users\test\.claude\transcripts\test.jsonl"
            cwd               = "D:\Projects\my-app"
            permission_mode   = "default"
            hook_event_name   = "Notification"
            message           = "All tests passing. 47 tests in 3 suites. Ready for next task."
            title             = "Task Complete"
            notification_type = "idle_prompt"
        } | ConvertTo-Json -Compress
    },
    @{
        Name = "auth_success"
        Json = @{
            session_id        = "test-session-003"
            transcript_path   = "C:\Users\test\.claude\transcripts\test.jsonl"
            cwd               = "D:\Projects\my-app"
            permission_mode   = "default"
            hook_event_name   = "Notification"
            message           = "Authentication successful."
            title             = "Claude Code"
            notification_type = "auth_success"
        } | ConvertTo-Json -Compress
    },
    @{
        Name = "elicitation_dialog"
        Json = @{
            session_id        = "test-session-004"
            transcript_path   = "C:\Users\test\.claude\transcripts\test.jsonl"
            cwd               = "D:\Projects\my-app"
            permission_mode   = "default"
            hook_event_name   = "Notification"
            message           = "Should I use TypeScript strict mode for the new module?"
            title             = "Input Needed"
            notification_type = "elicitation_dialog"
        } | ConvertTo-Json -Compress
    }
)

foreach ($test in $testCases) {
    Write-Host "Testing: $($test.Name)..." -ForegroundColor Yellow

    # Pipe JSON to dispatcher via stdin
    $test.Json | powershell.exe -ExecutionPolicy Bypass -NoProfile -File $dispatcherPath

    $exitCode = $LASTEXITCODE
    if ($exitCode -eq 0) {
        Write-Host "  Exit code: 0 — OK" -ForegroundColor Green
    } else {
        Write-Host "  Exit code: $exitCode — UNEXPECTED" -ForegroundColor Red
    }

    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "Integration test complete!" -ForegroundColor Green

# Check error log
$errorLog = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\error.log"
if (Test-Path $errorLog) {
    $errors = Get-Content $errorLog
    if ($errors.Count -gt 0) {
        Write-Host ""
        Write-Host "Errors found in log:" -ForegroundColor Yellow
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
} else {
    Write-Host "No errors logged." -ForegroundColor Green
}
