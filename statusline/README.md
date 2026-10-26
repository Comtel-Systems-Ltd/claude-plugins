# Claude Code statusline

Custom statusline for Claude Code on Windows.

Segments: model · context usage · effort · path · git branch/status · caveman badge.

```
Opus 5  |  ctx 71k/1M 7%  |  effort high  |  D:/GIT/Comtel/claude-plugins  |  git:main*  |  [CAVEMAN]
```

- Context window, usage and effort come from the statusline stdin JSON (`context_window`, `effort`; Claude Code 2.1+). Coloured green/yellow/red by fill.
- Older Claude Code versions don't send those: the script then reads the session transcript tail (last 1 MB only, lines over 256 kB skipped — `Get-Content -Tail` in Windows PowerShell 5.1 took minutes on transcripts holding images and pinned a core on every refresh) and infers the window from the model id (`1m` tag or any `fable` model → 1M), or from usage (> 200k → 1M), else 200k. `CLAUDE_CTX_WINDOW` overrides the inference.
- Git segment shows the branch (or short SHA on detached HEAD) with `*` when dirty.
- Caveman badge appears when `~/.claude/.caveman-active` holds a valid mode.
- Fails soft: any error prints what it has and exits 0, so the prompt never breaks.

## Install on a new machine

```powershell
.\statusline\install.ps1
```

Copies `statusline.ps1` to `~/.claude/` and sets `statusLine` in `~/.claude/settings.json`,
preserving other keys and writing a `settings.json.bak` backup. Pass `-Force` to replace an
existing statusLine entry without prompting.

Restart Claude Code afterwards.

## Manual install

Copy `statusline.ps1` to `~/.claude/statusline.ps1`, then in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -NoProfile -ExecutionPolicy Bypass -Command \"& ([Environment]::GetFolderPath('UserProfile') + '/.claude/statusline.ps1')\""
  }
}
```

The home directory is resolved by .NET, not by the shell, so the same settings.json works on
any Windows machine regardless of user name. Verified under both `cmd.exe` and bash.

## Test without restarting

```bash
echo '{"model":{"display_name":"Opus 5","id":"claude-opus-5[1m]"},"cwd":"D:/GIT/Comtel/claude-plugins"}' \
  | powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/statusline.ps1
```

## Updating

Edit `statusline/statusline.ps1` here, commit, push, then re-run `install.ps1` on each machine.
