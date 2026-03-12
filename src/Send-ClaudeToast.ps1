<#
.SYNOPSIS
    Main dispatcher for Claude Code toast notifications.
.DESCRIPTION
    This script is the hook entry point called by Claude Code's Notification hook.
    It reads JSON from stdin, routes to the appropriate notification builder,
    and handles rate limiting and error logging.

    IMPORTANT: This script must NEVER throw an error or return a non-zero exit code.
    A broken notification must never block Claude Code.

    ASYNC DESIGN: When called by the hook (no -PayloadFile), it reads stdin,
    writes to a temp file, spawns itself in the background, and exits immediately.
    This ensures the hook returns in ~50ms and never blocks Claude Code's UI.
#>
param(
    [string]$PayloadFile
)

# --- Hook mode: read stdin, fire async, exit fast ---
if (-not $PayloadFile) {
    try {
        $jsonInput = $input | Out-String
        if (-not $jsonInput -or $jsonInput.Trim().Length -eq 0) { exit 0 }

        $tempFile = Join-Path $env:TEMP "claude-toast-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
        [System.IO.File]::WriteAllText($tempFile, $jsonInput)

        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process -WindowStyle Hidden -FilePath "powershell.exe" -ArgumentList @(
            "-ExecutionPolicy", "Bypass", "-NoProfile", "-NoLogo", "-NonInteractive",
            "-File", "`"$scriptPath`"", "-PayloadFile", "`"$tempFile`""
        )
    } catch {
        # Never fail — silently ignore
    }
    exit 0
}

# --- Async mode: process the notification in the background ---
try {
    # Read and clean up temp file
    if (-not (Test-Path $PayloadFile)) { exit 0 }
    $jsonInput = [System.IO.File]::ReadAllText($PayloadFile)
    Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue

    if (-not $jsonInput -or $jsonInput.Trim().Length -eq 0) { exit 0 }

    $hookData = $jsonInput | ConvertFrom-Json

    # Convert PSCustomObject to hashtable for easier handling
    $hookDataHt = @{}
    foreach ($prop in $hookData.PSObject.Properties) {
        $hookDataHt[$prop.Name] = $prop.Value
    }

    $notificationType = $hookDataHt["notification_type"]
    if (-not $notificationType) { exit 0 }

    # Load configuration
    $scriptDir = $PSScriptRoot
    . "$scriptDir\Config.ps1"
    $config = Get-ClaudeToastConfig

    # Check if globally enabled
    if (-not $config.enabled) { exit 0 }

    # Get notification-specific config
    $notifConfig = @{}
    if ($config.notifications -and $config.notifications.ContainsKey($notificationType)) {
        $notifConfig = $config.notifications[$notificationType]
    }

    # Check if this notification type is enabled
    if ($notifConfig.ContainsKey("enabled") -and -not $notifConfig.enabled) { exit 0 }

    # --- Window focus detection: skip toast if editor is in foreground ---
    $skipFocusCheck = $config.ContainsKey("alwaysNotify") -and $config.alwaysNotify
    if (-not $skipFocusCheck) {
        try {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class FocusCheck {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    public static string GetForegroundProcessName() {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return "";
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        try {
            return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName;
        } catch {
            return "";
        }
    }
}
"@ -ErrorAction SilentlyContinue

            $foreground = [FocusCheck]::GetForegroundProcessName().ToLower()
            $editorProcesses = @("code", "cursor", "code - insiders", "windsurf")
            if ($foreground -in $editorProcesses) { exit 0 }
        } catch {
            # If focus detection fails, proceed with notification
        }
    }

    # --- Rate Limiting (file-timestamp based, avoids JSON parse overhead) ---
    $historyPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\last_notify"
    $now = [DateTime]::UtcNow

    # Fast cooldown check using file last-write time (no JSON parsing)
    $cooldownSeconds = if ($config.rateLimit -and $config.rateLimit.cooldownSeconds) { $config.rateLimit.cooldownSeconds } else { 5 }
    if (Test-Path $historyPath) {
        $lastWrite = (Get-Item $historyPath).LastWriteTimeUtc
        if (($now - $lastWrite).TotalSeconds -lt $cooldownSeconds) { exit 0 }

        # Hourly rate limit: count lines (each line = one timestamp)
        $maxPerHour = if ($config.rateLimit -and $config.rateLimit.maxPerHour) { $config.rateLimit.maxPerHour } else { 10 }
        $lines = @(Get-Content $historyPath -ErrorAction SilentlyContinue)
        # Prune entries older than 1 hour
        $cutoff = $now.AddHours(-1).ToString("o")
        $recent = @($lines | Where-Object { $_ -gt $cutoff })
        if ($recent.Count -ge $maxPerHour) { exit 0 }
        # Append current timestamp and write back pruned list
        $recent += $now.ToString("o")
        $recent | Set-Content $historyPath -Force
    } else {
        # First notification — create file
        $historyDir = Split-Path $historyPath -Parent
        if (-not (Test-Path $historyDir)) {
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        }
        $now.ToString("o") | Set-Content $historyPath -Force
    }

    # --- Ensure BurntToast is available ---
    # Import directly instead of scanning all module paths with Get-Module -ListAvailable (slow)
    try {
        Import-Module BurntToast -ErrorAction Stop
    } catch {
        exit 0
    }

    # --- Route to notification builder ---
    $notificationsDir = Join-Path $scriptDir "notifications"

    switch ($notificationType) {
        "permission_prompt" {
            & "$notificationsDir\PermissionPrompt.ps1" -HookData $hookDataHt -Config $config -NotifConfig $notifConfig
        }
        "idle_prompt" {
            & "$notificationsDir\IdlePrompt.ps1" -HookData $hookDataHt -Config $config -NotifConfig $notifConfig
        }
        "auth_success" {
            & "$notificationsDir\AuthSuccess.ps1" -HookData $hookDataHt -Config $config -NotifConfig $notifConfig
        }
        "elicitation_dialog" {
            & "$notificationsDir\ElicitationDialog.ps1" -HookData $hookDataHt -Config $config -NotifConfig $notifConfig
        }
        default {
            # Unknown notification type — show a generic toast
            New-BurntToastNotification `
                -Text "Claude Code", $hookDataHt["message"] `
                -AppLogo $config.iconPath `
                -UniqueIdentifier "claude-generic"
        }
    }

} catch {
    # Log error silently — never fail
    try {
        $logDir = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logPath = Join-Path $logDir "error.log"

        $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($_.Exception.Message)"

        # Cap log at 100 lines
        if (Test-Path $logPath) {
            $existingLines = @(Get-Content $logPath -ErrorAction SilentlyContinue)
            if ($existingLines.Count -ge 100) {
                $existingLines = $existingLines[-99..-1]
            }
            $existingLines += $logEntry
            $existingLines | Set-Content $logPath -Force
        } else {
            $logEntry | Set-Content $logPath -Force
        }
    } catch {
        # Even logging failed — silently ignore
    }
}

# Always exit 0
exit 0
