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

    # --- Idle check: skip only if editor is focused AND user was recently active ---
    Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class WinIdle {
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    public static string FgProcess() {
        IntPtr h = GetForegroundWindow(); if (h == IntPtr.Zero) return "";
        uint pid; GetWindowThreadProcessId(h, out pid);
        try { return System.Diagnostics.Process.GetProcessById((int)pid).ProcessName.ToLower(); } catch { return ""; }
    }
    public static double IdleSecs() {
        LASTINPUTINFO i = new LASTINPUTINFO(); i.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(i);
        return GetLastInputInfo(ref i) ? (Environment.TickCount - i.dwTime) / 1000.0 : 9999;
    }
}
"@ -ErrorAction SilentlyContinue

    try {
        $editors = @("code", "cursor", "code - insiders", "windsurf")
        $fg = [WinIdle]::FgProcess()
        if ($fg -in $editors -and [WinIdle]::IdleSecs() -lt [double]$config.idleThresholdSeconds) { exit 0 }
    } catch {}

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
    $preview = ($msg -replace '(?m)^#{1,6}\s+', '' -replace '\*{1,2}([^*]+)\*{1,2}', '$1' -replace '`[^`]+`', '' -replace '\n+', ' ' -replace '\s+', ' ').Trim()
    if ($preview.Length -gt 120) { $preview = $preview.Substring(0, 117) + "..." }
    if (-not $preview) { $preview = "Done." }

    # --- BurntToast ---
    Import-Module BurntToast -ErrorAction Stop

    $iconPath = Join-Path $env:LOCALAPPDATA "ClaudeCodeToast\claude-icon.png"
    $scheme   = if ($config.vscodeVariant -eq "code-insiders") { "vscode-insiders" } else { "vscode" }
    $uri      = "${scheme}://file/$($cwd -replace '\\', '/')"
    $button   = New-BTButton -Content "Open in VS Code" -Arguments $uri -ActivationType Protocol

    $params = @{
        Text             = "Claude: $project", $preview
        AppLogo          = $iconPath
        UniqueIdentifier = "claude-stop-$sessId"
        Button           = $button
        ExpirationTime   = [DateTime]::Now.AddMinutes(10)
    }
    if ($config.silent)      { $params["Silent"] = $true }
    elseif ($config.sound)   { $params["Sound"]  = $config.sound }

    New-BurntToastNotification @params

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
