<#
.SYNOPSIS
    Builds and displays a Default toast notification when Claude finishes a task.
.DESCRIPTION
    Called when Claude Code is idle and waiting for user input.
    Uses Default scenario with a gentle notification sound.
#>
param(
    [hashtable]$HookData,
    [hashtable]$Config,
    [hashtable]$NotifConfig
)

$title = "Claude Code — Task Complete"
$message = if ($HookData.message) { $HookData.message } else { "Claude has finished and is waiting for your input." }
$cwd = if ($HookData.cwd) { $HookData.cwd } else { "" }
$sessionId = if ($HookData.session_id) { $HookData.session_id.Substring(0, [Math]::Min(8, $HookData.session_id.Length)) } else { "default" }

$toastParams = @{
    Text             = $title, $message, $cwd
    AppLogo          = $Config.iconPath
    UniqueIdentifier = "claude-idle-$sessionId"
}

# Action button
if ($NotifConfig.showButton) {
    $buttonText = if ($NotifConfig.buttonText) { $NotifConfig.buttonText } else { "Open Claude" }
    if ($Config.deepLink.mode -eq "vscode") {
        $variant = if ($Config.deepLink.vscodeVariant) { $Config.deepLink.vscodeVariant } else { "code" }
        $encodedCwd = if ($cwd) { [Uri]::EscapeDataString($cwd) } else { "" }
        $launchUri = "${variant}://file/${encodedCwd}"
        $button = New-BTButton -Content $buttonText -Arguments $launchUri -ActivationType Protocol
    } else {
        $button = New-BTButton -Content $buttonText -Arguments "dismiss" -ActivationType System
    }
    $toastParams["Button"] = $button
}

# Sound
if (-not $NotifConfig.silent -and $NotifConfig.sound) {
    $toastParams["Sound"] = $NotifConfig.sound
} elseif ($NotifConfig.silent) {
    $toastParams["Silent"] = $true
}

# Expiration
if ($NotifConfig.expirationMinutes) {
    $toastParams["ExpirationTime"] = [DateTime]::Now.AddMinutes($NotifConfig.expirationMinutes)
}

New-BurntToastNotification @toastParams
