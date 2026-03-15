<#
.SYNOPSIS
    Claude Code Stop hook — shows a Windows toast when Claude finishes a response.
.DESCRIPTION
    Called by Claude Code's Stop hook. Reads JSON from stdin, spawns a background
    process immediately, and exits. The background process shows the toast.

    NEVER throw or exit non-zero — a broken notification must never block Claude Code.
#>
param([string]$PayloadFile)

# --- Hook mode: read stdin, fire-and-forget, exit fast (~10ms) ---
if (-not $PayloadFile) {
    try {
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $json = [System.Console]::In.ReadToEnd()
        if ($json -and $json.Trim()) {
            $tmp = Join-Path $env:TEMP "claude-toast-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
            [System.IO.File]::WriteAllText($tmp, $json)
            $self = $MyInvocation.MyCommand.Path -replace '/', '\'
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                "-ExecutionPolicy", "Bypass", "-NoProfile", "-NoLogo", "-NonInteractive",
                "-File", "`"$self`"", "-PayloadFile", "`"$tmp`""
            )
        }
    } catch {}
    exit 0
}

# --- Background mode: show the toast ---
try {
    if (-not (Test-Path $PayloadFile)) { exit 0 }
    $json = [System.IO.File]::ReadAllText($PayloadFile)
    Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue

    $data   = $json | ConvertFrom-Json
    $cwd    = if ($data.cwd) { $data.cwd } else { "" }
    $msg    = if ($data.last_assistant_message) { $data.last_assistant_message } else { "" }
    $sessId = if ($data.session_id) { $data.session_id.Substring(0, [Math]::Min(8, $data.session_id.Length)) } else { "x" }

    # --- Config ---
    $config = @{
        enabled              = $true
        idleThresholdSeconds = 30
        cooldownSeconds      = 10
        maxPerHour           = 30
        sound                = "Default"
        silent               = $false
        vscodeVariant        = "code"
    }
    $configFiles = @(
        (Join-Path $PSScriptRoot "..\config\defaults.json"),
        (Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\config.json")
    )
    foreach ($cf in $configFiles) {
        if (Test-Path $cf) {
            $override = Get-Content $cf -Raw | ConvertFrom-Json
            foreach ($p in $override.PSObject.Properties) { $config[$p.Name] = $p.Value }
        }
    }
    if (-not $config.enabled) { exit 0 }

    # Idle check removed — always notify

    # --- Rate limit ---
    $ratePath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\last_notify"
    $now = [DateTime]::UtcNow
    if (Test-Path $ratePath) {
        if (($now - (Get-Item $ratePath).LastWriteTimeUtc).TotalSeconds -lt [double]$config.cooldownSeconds) { exit 0 }
        $recent = @(Get-Content $ratePath -ErrorAction SilentlyContinue | Where-Object { $_ -gt $now.AddHours(-1).ToString("o") })
        if ($recent.Count -ge [int]$config.maxPerHour) { exit 0 }
        ($recent + $now.ToString("o")) | Set-Content $ratePath -Force
    } else {
        $dir = Split-Path $ratePath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $now.ToString("o") | Set-Content $ratePath -Force
    }

    # --- Toast content ---
    $project = if ($cwd) { Split-Path $cwd -Leaf } else { "Claude" }

    # Strip markdown and normalize to ASCII-safe preview
    $preview = $msg -replace '(?m)^#{1,6}\s+', '' `
                    -replace '\*{1,2}([^*]+)\*{1,2}', '$1' `
                    -replace '`[^`]+`', '' `
                    -replace '\n+', ' ' `
                    -replace '\s+', ' '
    $preview = $preview.Trim()
    if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 117) + "..." }
    if (-not $preview) { $preview = "Done." }

    # --- Toast via WinRT (no BurntToast — full AppId control) ---
    $null = [Windows.UI.Notifications.ToastNotificationManager,   Windows.UI.Notifications,   ContentType = WindowsRuntime]
    $null = [Windows.UI.Notifications.ToastNotification,          Windows.UI.Notifications,   ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument,                    Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    $iconPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
    $scheme   = if ($config.vscodeVariant -eq "code-insiders") { "vscode-insiders" } else { "vscode" }
    $uri      = "${scheme}://file/$($cwd -replace '\\', '/')"

    # Escape XML special characters
    $safeProject = [System.Security.SecurityElement]::Escape("Claude: $project")
    $safePreview = [System.Security.SecurityElement]::Escape($preview)
    $safeIcon    = [System.Security.SecurityElement]::Escape($iconPath)
    $safeUri     = [System.Security.SecurityElement]::Escape($uri)

    $soundXml = if ($config.silent) {
        '<audio silent="true"/>'
    } elseif ($config.sound) {
        "<audio src='ms-winsoundevent:Notification.$($config.sound)'/>"
    } else { "" }

    $xml = @"
<toast scenario="reminder">
  <visual>
    <binding template="ToastGeneric">
      <text>$safeProject</text>
      <text>$safePreview</text>
      <image placement="appLogoOverride" src="$safeIcon" hint-crop="circle"/>
    </binding>
  </visual>
  <actions>
    <action content="Open in VS Code" arguments="$safeUri" activationType="protocol"/>
    <action content="Dismiss" arguments="dismiss" activationType="system"/>
  </actions>
  $soundXml
</toast>
"@

    $toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $toastXml.LoadXml($xml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
    $toast.Tag   = "claude-stop-$sessId"
    $toast.Group = "claude-stop-$sessId"
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(10)

    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("ClaudeCode.Toast").Show($toast)

} catch {
    try {
        $logDir = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logPath = "$logDir\error.log"
        $lines = if (Test-Path $logPath) { @(Get-Content $logPath)[-99..-1] } else { @() }
        ($lines + "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($_.Exception.Message)") | Set-Content $logPath -Force
    } catch {}
}

exit 0
