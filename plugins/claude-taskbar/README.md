# claude-taskbar

Windows only. While a Claude Code session is running inside Windows Terminal,
the Terminal window hosting it gets its own taskbar button with the Claude logo
and the name "Claude Code". When the session ends the window goes back to the
normal Terminal button.

Windows Terminal cannot do this per profile ([terminal#6556](https://github.com/microsoft/terminal/issues/6556),
[terminal#12218](https://github.com/microsoft/terminal/issues/12218)), so the
plugin sets the shell's per-window AppUserModel properties (ID, relaunch icon,
relaunch name, relaunch command) on the hosting window instead.

## Install

```
/plugin install claude-taskbar@comtel-systems
```

Then start a new `claude` session (or `/clear`). Nothing else to configure.

Because the window gets its own taskbar identity you can right-click the button
and pin it. The pinned item launches `wt.exe -p "Claude Code"`, so a Windows
Terminal profile named **Claude Code** is worth having:

```json
{ "name": "Claude Code", "commandline": "claude", "icon": "🤖" }
```

## How it works

- `hooks/hooks.json` runs `scripts/taskbar-start.ps1` on every `SessionStart`
  (async, so startup is not delayed).
- The launcher walks up the process tree from the hook shell to find
  `claude.exe` and the `WindowsTerminal.exe` hosting it, then starts
  `scripts/taskbar-helper.ps1` hidden. A pid file in
  `%LOCALAPPDATA%\claude-taskbar\` stops duplicate helpers on resume, `/clear`
  and compaction.
- The helper polls every 1.5 s. While `claude.exe` is alive it stamps the
  Terminal window (only the one whose title looks like a Claude session when
  several are open). When `claude.exe` exits it clears the stamp and quits.
- Optional notification-area icon: set `CLAUDE_TASKBAR_TRAY_ICON=1` (for
  example under `env` in `~/.claude/settings.json`).

## Gotchas

- The auto-updater renames the *running* binary to `claude.exe.old.<timestamp>`,
  so the process name is matched with `^claude(\.|$)`, never by equality.
- Requires `powershell.exe` (Windows PowerShell 5.1) for the hook; the helper
  prefers `pwsh` when installed.
- Outside Windows Terminal (VS Code terminal, plain conhost) the helper still
  runs but has nothing to stamp.
- `assets/claude-app.ico` is the Claude desktop app icon, included for
  internal use.
