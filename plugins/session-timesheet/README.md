# session-timesheet

Two things, for billing client time without keeping notes by hand:

- **On screen** — every assistant reply is prefixed with the local time it finished.
- **In context** — Claude is told when the session and each prompt started, so it can
  answer "how long did that take" without being asked to check anything.
- **After the fact** — a report that rebuilds the timeline of a past session: prompt
  sent, reply finished, minutes between, and a total.

## Install

```
/plugin marketplace add D:/GIT/Comtel/claude-plugins
/plugin install session-timesheet@comtel-systems
```

Needs `jq` on PATH, then a Claude Code restart so the new PATH is picked up:

| Platform | Install |
| :- | :- |
| Windows | `winget install jqlang.jq` |
| macOS | `brew install jq` |
| Linux | `apt install jq` (or the distro equivalent) |

The report script needs Python, and no jq.

## Hooks

Three, all one jq process, all in exec form — `command` is the binary and `args` is the
argument vector, so no shell is involved and nothing can mangle quoting on any platform.

| Event | Filter | Effect |
| :- | :- | :- |
| `MessageDisplay` | `hooks/stamp.jq` | Prefixes `[HH:MM:SS]` to the reply, on screen only |
| `UserPromptSubmit` | `hooks/prompt-time.jq` | Adds the prompt's send time to Claude's context |
| `SessionStart` | `hooks/session-time.jq` | Adds the session start time to Claude's context |

`MessageDisplay` rewrites only what is displayed — the transcript and what Claude sees
keep the original text. Its `content` is the message so far, so the prefix lands once at
the front and its clock settles at the moment streaming ended, which is the number worth
billing. The other two touch context only and never appear in the chat.

### Why jq rather than PowerShell or bash

`MessageDisplay` fires repeatedly per reply as text streams, so process startup is the
whole cost. Measured on Windows: jq ~24 ms per invocation (including the test harness's
own pipe), PowerShell ~162 ms — about seven times worse for identical output. Keeping
the filters in `.jq` files means one process per invocation; wrapping jq in bash, as
`zoharbabin/claude-code-message-timestamps` does, costs two.

### When jq is missing

There is no install-time check to add: `plugin.json`'s `dependencies` field is for other
plugins, not binaries, and there is no postinstall step. It fails visibly anyway — a hook
whose binary won't start is a non-blocking error, so the transcript shows a
`MessageDisplay hook error` notice and the session carries on untimestamped. No separate
dependency-warning hook is needed to surface it.

`strflocaltime` is not present in every jq build. Where it is missing the filters error
out the same way, which is a visible notice rather than a broken session.

## Report for past sessions

Session transcripts carry timestamps, so history works even where the hooks were never
installed:

```
python scripts/session-times.py                   # newest session for this folder
python scripts/session-times.py --csv             # for a spreadsheet
python scripts/session-times.py --all             # every session, newest first
python scripts/session-times.py --project <dir>   # another project folder
python scripts/session-times.py <session-id>
```

```
Date       Sent   Done     Mins  Prompt
2026-10-04 21:55  21:57     2.1  What's next in the bluetooth release plan?
TOTAL working               34.6  (27 prompts, 100.7 min elapsed)
```

`TOTAL working` adds the prompt-to-reply spans — time Claude was actually working. The
elapsed figure in brackets is wall clock from first prompt to last reply and includes
your thinking time between turns. The two are usually far apart; which one you bill is
your call.

Slash commands, their output, and interrupted turns are left out, so `/clear` is never
counted as billable work.
