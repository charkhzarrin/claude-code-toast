# Claude Code Toast

Rich Windows 11 toast notifications for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) — never miss a permission prompt or task completion again.

![Windows 11](https://img.shields.io/badge/Windows%2011-0078D6?logo=windows11&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

| Event | Notification Style | Description |
|-------|-------------------|-------------|
| **Permission Prompt** | Urgent (breaks DND) | Claude needs your permission to run a command |
| **Task Complete** | Default with chime | Claude finished working and is waiting for input |
| **Auth Success** | Silent, auto-dismiss | Authentication completed successfully |
| **Input Needed** | Persistent reminder | Claude is asking you a question |

- Custom Claude branding (icon + app identity)
- **"Open Claude" button** — click to jump back to VS Code
- **Smart rate limiting** — no notification spam (configurable)
- **Tag-based replacement** — new notifications update old ones instead of stacking
- **Per-type configuration** — enable/disable, change sounds, adjust expiration
- **Deep linking** — `vscode://` protocol integration
- **Error-safe** — notifications never block Claude Code

## Quick Start

### Prerequisites

- Windows 10/11
- PowerShell 5.1+ (pre-installed on Windows)
- Claude Code (CLI or VS Code extension)

### Install

```powershell
git clone https://github.com/YOUR_USERNAME/claude-code-toast.git
cd claude-code-toast
powershell -ExecutionPolicy Bypass -File install.ps1
```

That's it. The installer handles everything:
1. Installs [BurntToast](https://github.com/Windos/BurntToast) module (user scope, no admin)
2. Registers Windows App ID for branded notifications
3. Copies scripts to `%LOCALAPPDATA%\ClaudeCodeToast\`
4. Adds the notification hook to Claude Code's `settings.json`
5. Sends a test notification to confirm it works

### Uninstall

```powershell
cd claude-code-toast
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

## Configuration

Create `%LOCALAPPDATA%\ClaudeCodeToast\config.json` to override defaults. You only need to specify the settings you want to change:

```json
{
  "rateLimit": {
    "maxPerHour": 20,
    "cooldownSeconds": 3
  },
  "notifications": {
    "auth_success": {
      "enabled": false
    },
    "permission_prompt": {
      "silent": true
    }
  }
}
```

### All Configuration Options

| Setting | Default | Description |
|---------|---------|-------------|
| `enabled` | `true` | Global on/off switch |
| `deepLink.mode` | `"vscode"` | Button action: `"vscode"`, `"terminal"`, or `"none"` |
| `deepLink.vscodeVariant` | `"code"` | VS Code variant: `"code"` or `"code-insiders"` |
| `rateLimit.maxPerHour` | `10` | Maximum notifications per hour |
| `rateLimit.cooldownSeconds` | `5` | Minimum seconds between notifications |

### Per-Notification Settings

Each notification type (`permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`) supports:

| Setting | Description |
|---------|-------------|
| `enabled` | Enable/disable this notification type |
| `scenario` | Windows toast scenario: `Default`, `Reminder`, `Urgent` |
| `sound` | Windows sound URI (e.g., `ms-winsoundevent:Notification.Default`) |
| `silent` | `true` to suppress sound |
| `expirationMinutes` | How long the notification stays in Action Center |
| `showButton` | Show the "Open Claude" action button |
| `buttonText` | Custom button label |

## Testing

### Preview all notification styles

```powershell
powershell -ExecutionPolicy Bypass -File tests\Test-Toast.ps1
```

### Simulate full Claude Code integration

```powershell
powershell -ExecutionPolicy Bypass -File tests\Test-Integration.ps1
```

## How It Works

Claude Code has a [hook system](https://docs.anthropic.com/en/docs/claude-code/hooks) that fires events during operation. This tool registers a `Notification` hook that:

1. Receives JSON payload from Claude Code via stdin
2. Parses the notification type and message
3. Applies rate limiting to prevent spam
4. Routes to the appropriate notification builder
5. Displays a rich Windows toast notification via BurntToast

```
Claude Code fires Notification event
  → stdin JSON → Send-ClaudeToast.ps1
    → Config.ps1 (load settings)
    → Rate limiter (check history)
    → PermissionPrompt.ps1 / IdlePrompt.ps1 / ...
      → BurntToast → Windows Toast Notification
```

## Project Structure

```
claude-code-toast/
├── install.ps1                      # One-command installer
├── uninstall.ps1                    # Clean removal
├── assets/
│   └── claude-icon.png              # App icon (64x64)
├── src/
│   ├── Send-ClaudeToast.ps1         # Main dispatcher (hook entry point)
│   ├── Config.ps1                   # Configuration loader
│   ├── Register-AppId.ps1           # Windows AUMID registration
│   └── notifications/
│       ├── PermissionPrompt.ps1     # Urgent — permission needed
│       ├── IdlePrompt.ps1           # Default — task complete
│       ├── AuthSuccess.ps1          # Silent — auth OK
│       └── ElicitationDialog.ps1    # Reminder — input needed
├── config/
│   └── defaults.json                # Default configuration
└── tests/
    ├── Test-Toast.ps1               # Visual test
    └── Test-Integration.ps1         # Full integration test
```

## Troubleshooting

### Notifications don't appear

1. Check BurntToast is installed: `Get-Module -ListAvailable BurntToast`
2. Check Windows notification settings: Settings → System → Notifications
3. Check error log: `%LOCALAPPDATA%\ClaudeCodeToast\error.log`
4. Run the test: `powershell -ExecutionPolicy Bypass -File tests\Test-Toast.ps1`

### "Open Claude" button doesn't work

- Ensure VS Code is installed and `vscode://` protocol is registered
- Try setting `deepLink.mode` to `"none"` in your config

### Too many / too few notifications

Adjust rate limiting in your config:
```json
{
  "rateLimit": {
    "maxPerHour": 20,
    "cooldownSeconds": 2
  }
}
```

### Hook not firing

Check `~/.claude/settings.json` contains the Notification hook entry. Re-run `install.ps1` if needed.

## License

MIT — see [LICENSE](LICENSE).
