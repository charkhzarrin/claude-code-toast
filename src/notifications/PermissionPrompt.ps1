<#
.SYNOPSIS
    Builds and displays an Urgent toast notification for permission prompts.
.DESCRIPTION
    Called when Claude Code needs user permission to execute a tool.
    Uses the Urgent scenario to break through Do Not Disturb.
#>
param(
    [hashtable]$HookData,
    [hashtable]$Config,
    [hashtable]$NotifConfig
)

$title = "Claude Code — Permission Required"
$message = if ($HookData.message) { $HookData.message } else { "Claude needs your permission to proceed." }
$cwd = if ($HookData.cwd) { $HookData.cwd } else { "" }
$body = if ($cwd) { "$message`n$cwd" } else { $message }
$sessionId = if ($HookData.session_id) { $HookData.session_id.Substring(0, [Math]::Min(8, $HookData.session_id.Length)) } else { "default" }

$toastParams = @{
    Text        = $title, $message, $cwd
    AppLogo     = $Config.iconPath
    UniqueIdentifier = "claude-permission-$sessionId"
}

# Action button
if ($NotifConfig.showButton) {
    $buttonText = if ($NotifConfig.buttonText) { $NotifConfig.buttonText } else { "Open Claude" }
    if ($Config.deepLink.mode -eq "vscode") {
        $variant = if ($Config.deepLink.vscodeVariant) { $Config.deepLink.vscodeVariant } else { "code" }
        $encodedCwd = if ($cwd) { [Uri]::EscapeDataString($cwd) } else { "" }
        $scheme = switch ($variant) { "code" { "vscode" } "code-insiders" { "vscode-insiders" } default { $variant } }
        $launchUri = "${scheme}://file/${encodedCwd}"
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
