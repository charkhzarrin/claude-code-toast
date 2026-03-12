<#
.SYNOPSIS
    Main dispatcher for Claude Code toast notifications.
.DESCRIPTION
    This script is the hook entry point called by Claude Code's Notification hook.
    It reads JSON from stdin, routes to the appropriate notification builder,
    and handles rate limiting and error logging.

    IMPORTANT: This script must NEVER throw an error or return a non-zero exit code.
    A broken notification must never block Claude Code.
#>

try {
    # Read JSON payload from stdin
    $jsonInput = $input | Out-String

    if (-not $jsonInput -or $jsonInput.Trim().Length -eq 0) {
        exit 0
    }

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

    # --- Rate Limiting ---
    $historyPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\history.json"
    $now = [DateTime]::UtcNow
    $timestamps = @()

    if (Test-Path $historyPath) {
        try {
            $history = Get-Content $historyPath -Raw | ConvertFrom-Json
            if ($history.timestamps) {
                $timestamps = @($history.timestamps | ForEach-Object {
                    [DateTime]::Parse($_)
                } | Where-Object {
                    ($now - $_).TotalMinutes -le 60
                })
            }
        } catch {
            $timestamps = @()
        }
    }

    # Check max per hour
    $maxPerHour = if ($config.rateLimit -and $config.rateLimit.maxPerHour) { $config.rateLimit.maxPerHour } else { 10 }
    if ($timestamps.Count -ge $maxPerHour) { exit 0 }

    # Check cooldown
    $cooldownSeconds = if ($config.rateLimit -and $config.rateLimit.cooldownSeconds) { $config.rateLimit.cooldownSeconds } else { 5 }
    if ($timestamps.Count -gt 0) {
        $lastTimestamp = $timestamps | Sort-Object | Select-Object -Last 1
        if (($now - $lastTimestamp).TotalSeconds -lt $cooldownSeconds) { exit 0 }
    }

    # Record this notification
    $timestamps += $now
    $historyDir = Split-Path $historyPath -Parent
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }
    $historyData = @{ timestamps = @($timestamps | ForEach-Object { $_.ToString("o") }) }
    $historyData | ConvertTo-Json -Depth 5 | Set-Content $historyPath -Force

    # --- Ensure BurntToast is available ---
    if (-not (Get-Module -ListAvailable -Name BurntToast)) {
        exit 0
    }
    Import-Module BurntToast -ErrorAction SilentlyContinue

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
