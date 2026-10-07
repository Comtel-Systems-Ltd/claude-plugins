# session-timesheet

For billing client time without keeping notes by hand:

- **On screen** — each prompt shows when it was sent, in the right margin on its last line,
  and each reply when it finished, right-aligned on its own line under the reply. Prompts
  grey, replies a muted Claude orange.
- **In context** — Claude is told when the session and each prompt started, so it can
  answer "how long did that take" directly.
- **After the fact** — a report that rebuilds the timeline of a past session: prompt
  sent, reply finished, minutes between, and a total.

## Install

```
/plugin install session-timesheet@comtel-systems
```

Then restart Claude Code. Needs:

- **jq** on PATH for the context hooks — `winget install jqlang.jq`, `brew install jq`,
  `apt install jq`. Restart after installing so the new PATH is picked up.
- **Python** for the report script only.

## On-screen stamps — `hooks/prompt-times.tsx`

A function-hook module, run in-process, so a redraw costs no process spawn.

- `prompt.submit` records when each prompt you typed was sent.
- `turn.complete` records when each main-loop turn finished, keyed by its final answer.
- `ui.render` on `UserMessage` wraps the engine's own row in a row Box with the time at
  the right.
- `ui.render` on `AssistantMessage` wraps it in a column Box with the time on a
  right-aligned line underneath: beside the row the time would take the reply's width, and
  full-width tables would wrap. The reply's time goes on its final text block, the one the
  turn's answer opens.

Rows carry no timestamp, so a row is matched to its record by the first 40 characters of
its text. That is what lets a prompt with a paste still match: the stored text has the
paste expanded while the row shows it as typed. Two messages opening identically share
the newer time. Messages from before the plugin loaded have no record and draw unstamped.

The engine refuses its row inside a Box that sizes it — `width` included — and draws its
own instead. That is why the layouts use flex direction and justification only
(`space-between` + `alignItems="flex-end"` for prompts, a column with a `flex-end` line
for replies) and never a width. The tests stand in for the engine with a real
engine node, so they catch that refusal:

```
claude plugin test plugins/session-timesheet
```

**Early access.** Claude Code marks the function-hook API as subject to change between
releases. If an update breaks it, the engine draws its plain rows and the transcript shows
a dim `session-timesheet: …` line; nothing else is affected.

## Context hooks — `hooks/context.json`

Two classic hooks, each one jq process in exec form (no shell, so quoting is the same on
every platform):

| Event | Filter | Adds to Claude's context |
| :- | :- | :- |
| `UserPromptSubmit` | `hooks/prompt-time.jq` | When the prompt was sent |
| `SessionStart` | `hooks/session-time.jq` | When the session started |

There is no install-time check for jq: `plugin.json`'s `dependencies` is for other
plugins, not binaries. A missing jq shows as a `hook error` notice in the transcript and
the session carries on.

## Report for past sessions — `scripts/session-times.py`

Session transcripts carry timestamps, so history works even where the plugin was never
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
elapsed figure in brackets is wall clock from first prompt to last reply and includes your
thinking time between turns. Which one you bill is your call.

Slash commands, their output and interrupted turns are left out, so `/clear` is never
counted as billable work.
