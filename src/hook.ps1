<#
.SYNOPSIS
    Claude Code Stop hook — shows a Windows toast notification when Claude finishes a response.

.DESCRIPTION
    This script is registered as a Stop hook in Claude Code's settings.json.
    It is called automatically after every Claude response.

    Two-phase design:
      Phase 1 (Hook mode): reads JSON payload from stdin, writes it to a temp file,
        spawns Phase 2 as a hidden background process, and exits in ~10ms.
        This ensures Claude Code's UI is never blocked.

      Phase 2 (Background mode): reads the temp file, applies rate limiting,
        builds a Windows toast notification using WinRT APIs, and displays it.

    Safety: this script NEVER throws or exits with a non-zero code.
    A broken notification must never interfere with Claude Code.
#>
param(
    # When set, runs in background mode processing the given temp file.
    # When absent, runs in hook mode (reads stdin).
    [string]$PayloadFile
)

# =============================================================================
# PHASE 1 — Hook mode: read stdin, spawn background process, exit fast
# =============================================================================
if (-not $PayloadFile) {
    try {
        # Force UTF-8 so Persian/CJK/emoji in responses are read correctly
        [Console]::InputEncoding  = [System.Text.Encoding]::UTF8
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        $json = [System.Console]::In.ReadToEnd()
        if ($json -and $json.Trim()) {
            # Write payload to a uniquely named temp file to avoid collisions
            $tmp  = Join-Path $env:TEMP "claude-toast-$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
            [System.IO.File]::WriteAllText($tmp, $json)

            # Spawn background process — WindowStyle Hidden keeps it invisible
            $self = $MyInvocation.MyCommand.Path -replace '/', '\'
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @(
                "-ExecutionPolicy", "Bypass", "-NoProfile", "-NoLogo", "-NonInteractive",
                "-File", "`"$self`"", "-PayloadFile", "`"$tmp`""
            )
        }
    } catch {
        # Silently swallow all errors — hook must never fail visibly
    }
    exit 0
}

# =============================================================================
# PHASE 2 — Background mode: show the toast
# =============================================================================
try {
    # --- Read and clean up temp file ---
    if (-not (Test-Path $PayloadFile)) { exit 0 }
    $json = [System.IO.File]::ReadAllText($PayloadFile)
    Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue

    # --- Parse Claude Code's Stop hook payload ---
    $data   = $json | ConvertFrom-Json
    $cwd    = if ($data.cwd)                    { $data.cwd }                    else { "" }
    $msg    = if ($data.last_assistant_message) { $data.last_assistant_message } else { "" }
    $sessId = if ($data.session_id)             { $data.session_id.Substring(0, [Math]::Min(8, $data.session_id.Length)) } else { "x" }

    # --- Load configuration (hardcoded defaults -> defaults.json -> user config.json) ---
    $config = @{
        enabled         = $true    # Set to false to disable all notifications
        cooldownSeconds = 10       # Minimum seconds between notifications
        maxPerHour      = 30       # Maximum notifications per hour
        sound           = "Default" # Windows sound: Default, IM, Mail, Reminder, SMS, or silent
        silent          = $false   # Set to true to suppress sound entirely
        vscodeVariant   = "code"   # "code", "code-insiders", or "cursor"
    }
    foreach ($cf in @(
        (Join-Path $PSScriptRoot "..\config\defaults.json"),
        (Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\config.json")
    )) {
        if (Test-Path $cf) {
            $override = Get-Content $cf -Raw | ConvertFrom-Json
            foreach ($p in $override.PSObject.Properties) { $config[$p.Name] = $p.Value }
        }
    }
    if (-not $config.enabled) { exit 0 }

    # --- Rate limiting ---
    # Uses file timestamps instead of JSON parsing for minimal overhead.
    # The file stores one ISO-8601 timestamp per line (one per notification).
    $ratePath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\last_notify"
    $now      = [DateTime]::UtcNow

    if (Test-Path $ratePath) {
        # Enforce cooldown between consecutive notifications
        if (($now - (Get-Item $ratePath).LastWriteTimeUtc).TotalSeconds -lt [double]$config.cooldownSeconds) { exit 0 }

        # Enforce hourly cap — prune entries older than 1 hour and count what remains
        $recent = @(Get-Content $ratePath -ErrorAction SilentlyContinue | Where-Object { $_ -gt $now.AddHours(-1).ToString("o") })
        if ($recent.Count -ge [int]$config.maxPerHour) { exit 0 }
        ($recent + $now.ToString("o")) | Set-Content $ratePath -Force
    } else {
        $dir = Split-Path $ratePath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $now.ToString("o") | Set-Content $ratePath -Force
    }

    # --- Build toast content ---
    # Title: the project folder name (last segment of cwd)
    $project = if ($cwd) { Split-Path $cwd -Leaf } else { "Claude" }

    # Body: strip common markdown syntax, collapse whitespace, truncate
    $preview = $msg -replace '(?m)^#{1,6}\s+', '' `
                    -replace '\*{1,2}([^*]+)\*{1,2}', '$1' `
                    -replace '`[^`]+`', '' `
                    -replace '\n+', ' ' `
                    -replace '\s+', ' '
    $preview = $preview.Trim()
    if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 117) + "..." }
    if (-not $preview) { $preview = "Done." }

    # --- Load WinRT types ---
    # Using WinRT directly (not BurntToast) so we can specify our own AppId,
    # which controls the app name shown at the top of the notification.
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications,        ContentType = WindowsRuntime]
    $null = [Windows.UI.Notifications.ToastNotification,        Windows.UI.Notifications,        ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument,                  Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    # --- Build deep-link URI for the "Open in VS Code" button ---
    $scheme = if ($config.vscodeVariant -eq "code-insiders") { "vscode-insiders" } else { "vscode" }
    $uri    = "${scheme}://file/$($cwd -replace '\\', '/')"

    # --- Escape all user-supplied values before embedding in XML ---
    $safeProject = [System.Security.SecurityElement]::Escape($project)
    $safePreview = [System.Security.SecurityElement]::Escape($preview)
    $safeIcon    = [System.Security.SecurityElement]::Escape((Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"))
    $safeUri     = [System.Security.SecurityElement]::Escape($uri)
    $safeSound   = [System.Security.SecurityElement]::Escape([string]$config.sound)

    $soundXml = if ($config.silent) {
        '<audio silent="true"/>'
    } elseif ($config.sound) {
        "<audio src='ms-winsoundevent:Notification.$safeSound'/>"
    } else { "" }

    # scenario="reminder" keeps the toast on screen until the user explicitly
    # clicks a button or the X — it does not auto-dismiss after a few seconds.
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
    <action content="Dismiss"         arguments="dismiss"  activationType="system"/>
  </actions>
  $soundXml
</toast>
"@

    $toastXml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    $toastXml.LoadXml($xml)

    $toast               = [Windows.UI.Notifications.ToastNotification]::new($toastXml)
    $toast.Tag           = "claude-stop-$sessId"
    $toast.Group         = "claude-stop-$sessId"
    $toast.ExpirationTime = [DateTimeOffset]::Now.AddMinutes(10)

    # CreateToastNotifier("ClaudeCode.Toast") uses the AUMID registered by
    # Register-AppId.ps1, which makes Windows show "Claude Code" as the app name.
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("ClaudeCode.Toast").Show($toast)

} catch {
    # Log errors silently — never surface them to the user or Claude Code
    try {
        $logDir  = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast"
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        $logPath = "$logDir\error.log"
        $lines   = if (Test-Path $logPath) { @(Get-Content $logPath)[-99..-1] } else { @() }
        ($lines + "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($_.Exception.Message)") | Set-Content $logPath -Force
    } catch {}
}

exit 0
