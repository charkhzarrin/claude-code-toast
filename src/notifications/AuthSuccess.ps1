<#
.SYNOPSIS
    Builds and displays a silent toast notification for successful authentication.
.DESCRIPTION
    Called when Claude Code authentication completes successfully.
    Brief, silent notification that auto-dismisses quickly.
#>
param(
    [hashtable]$HookData,
    [hashtable]$Config,
    [hashtable]$NotifConfig
)

$title = "Claude Code"
$message = if ($HookData.message) { $HookData.message } else { "Authentication successful." }

$toastParams = @{
    Text             = $title, $message
    AppLogo          = $Config.iconPath
    UniqueIdentifier = "claude-auth"
}

# Usually silent for auth
if ($NotifConfig.silent) {
    $toastParams["Silent"] = $true
} elseif ($NotifConfig.sound) {
    $toastParams["Sound"] = $NotifConfig.sound
}

# Short expiration
if ($NotifConfig.expirationMinutes) {
    $toastParams["ExpirationTime"] = [DateTime]::Now.AddMinutes($NotifConfig.expirationMinutes)
}

New-BurntToastNotification @toastParams
