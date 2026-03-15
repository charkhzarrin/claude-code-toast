# claude-code-toast — Windows Toast Notifications for Claude Code

**Get notified the moment Claude finishes responding — without watching the terminal.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D4?logo=windows)](https://github.com/charkhzarrin/claude-code-toast)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell)](https://github.com/PowerShell/PowerShell)

---

claude-code-toast is a lightweight PowerShell tool that hooks into [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and fires a native Windows toast notification every time Claude finishes a response. Switch to another window while Claude works — you'll know exactly when it's done.

Works with both the **Claude Code CLI** and the **Claude Code VS Code extension**.

---

## What It Does

- Shows a Windows toast notification after each Claude response, including the project name and a preview of the reply
- Displays **"Claude Code"** as the app name with a custom icon
- Provides an **"Open in VS Code"** button that jumps straight back to your project
- Stays on screen until dismissed — no missed notifications
- Runs silently in the background — zero impact on Claude's performance

---

## Installation

Run a single command in PowerShell or Windows Terminal from the project folder:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

That's it. The installer registers the hook in Claude Code's `settings.json` and sets everything up permanently — no need to run anything again.

> **First time you click "Open in VS Code":** VS Code will show a one-time security dialog. Check **"Allow opening local paths without asking"** and click **Yes** — it won't ask again.

### Requirements

| Requirement | Version |
|---|---|
| Windows | 10 or 11 |
| PowerShell | 5.1 or later |
| Claude Code | CLI or VS Code extension |
| BurntToast | Auto-installed during setup |

---

## How It Works

claude-code-toast registers a `Stop` hook in Claude Code's `~/.claude/settings.json`. After every response, Claude Code invokes `hook.ps1`, which:

1. Reads the JSON payload from stdin (`session_id`, `cwd`, `last_assistant_message`)
2. Spawns a detached background process to display the toast — fire-and-forget, so it never blocks Claude
3. Calls the Windows WinRT notification APIs directly — no heavy runtime dependencies

The only time BurntToast is used is during installation for a test notification. Day-to-day operation uses WinRT only.

### File Structure

```
claude-code-toast/
├── install.ps1
├── uninstall.ps1
├── src/
│   ├── hook.ps1              # Main hook script (runs after each response)
│   └── Register-AppId.ps1   # Registers the app AUMID for the custom icon
├── config/
│   └── defaults.json
└── assets/
    └── claude-icon.png
```

---

## Configuration

All settings are optional. To customize, create:

```
%LOCALAPPDATA%\ClaudeCodeToast\config.json
```

```json
{
  "cooldownSeconds": 10,
  "maxPerHour": 30,
  "sound": "Default",
  "silent": false,
  "vscodeVariant": "code"
}
```

| Setting | Default | Description |
|---|---|---|
| `cooldownSeconds` | `10` | Minimum seconds between notifications |
| `maxPerHour` | `30` | Maximum notifications per hour |
| `sound` | `"Default"` | Windows notification sound: `Default`, `Mail`, `Reminder`, `SMS`, etc. |
| `silent` | `false` | Set to `true` to suppress all sounds |
| `vscodeVariant` | `"code"` | VS Code variant for the Open button: `code`, `code-insiders`, or `cursor` |

Changes take effect immediately — no restart required.

---

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

Removes the hook from Claude Code's `settings.json` and cleans up all registered components. Your Claude Code settings and conversations are untouched.

---

## License

MIT — see [LICENSE](LICENSE) for details.
