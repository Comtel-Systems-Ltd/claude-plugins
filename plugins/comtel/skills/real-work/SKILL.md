---
name: real-work
description: Use when planning a multi-step task or working in plan mode and you need to capture the plan as a durable, resumable artifact — breaking work into phases with per-item checkboxes, completion tracking, autonomous verification, and a handoff summary so a future agent can pick up where you left off. Use when user wants to create or design a plan or mentioned "real work".
---

# Real Work

Turn planning into a durable, resumable artifact. The plan file — not the
conversation — is the source of truth: it records what to do, what's done, how it
was verified, and how to deploy. Any future agent can resume from it with zero
prior context.

**Use when** planning multi-step / multi-session work that may outlive the current
session. Skip for trivial single-session tasks.

## 1. Reach complete understanding first

Do **not** write the plan until scope is fully understood. Relentlessly ask the
user questions until you both share a complete understanding with **no gaps** —
treat an unasked question as a future bug.

- Don't stop at the first round; keep going until no ambiguity, assumption, or
  open decision remains. Probe edges: scope boundaries (in/out), dependencies,
  constraints, success criteria, data, environments, deployment, failure cases.
- Surface every assumption for the user to confirm. If an answer opens a new
  unknown, ask the follow-up — drill down recursively.
- Use `AskUserQuestion` for concrete choices. When done, summarize the full scope
  back and only proceed once the user confirms nothing is missing.

## 2. Write the plan

Save to `plans/<descriptive-name>.md` in the **repository root** (create `plans/`
if needed). Use this self-documenting template:

```markdown
# <Work Title>

<1-2 sentence goal and scope.>

## For Future Agents
Execute **one phase per turn — never more**. As work proceeds: mark checkboxes
`- [x]` as items complete; when a phase is done, set its status to `Complete` and
write its **Phase Summary** (what was done, key decisions, anything needed to
continue with zero context); run the phase's **Verification Plan** and record the
result. Then **stop**: do not start the next phase, and do not run `git commit`.
Instead, suggest a commit message for the completed phase and wait for the user to
either approve the commit or commit it themselves. Only continue to the next phase
after the user says to. Exception: if the user explicitly grants permission to run
multiple phases and/or commit per phase, follow that grant exactly as scoped — but
never assume it. When all phases are done, fill in **Final Recap** and
**Deployment Plan**.

## Phase 1: <Title>
Status: Not started   <!-- Not started | In progress | Complete -->

- [ ] <concrete, actionable item>
- [ ] <concrete, actionable item>

### Verification Plan
- <command/check the agent can run autonomously, with expected result>

### Phase Summary
_(write when phase completes)_

## Phase 2: <Title>
Status: Not started
- [ ] <actionable item>
### Verification Plan
- <autonomous check>
### Phase Summary
_(write when phase completes)_

## Final Recap
_(write when all phases complete: summary of the entire piece of work)_

## Deployment Plan
_(write when all phases complete: step-by-step deployment instructions)_
```

## 3. Execute one phase at a time

Execution is **gated per phase**. After completing a phase (items checked,
verification run, Phase Summary written):

1. **Stop.** Do not begin the next phase in the same turn, even if it looks quick
   or obvious.
2. **Do not commit.** Never run `git commit` (or `git add` + commit) on your own.
3. **Suggest a commit message** for the phase's changes and present it to the
   user.
4. **Wait.** The user will either tell you to commit (then use the suggested
   message unless they change it) or commit themselves. Only proceed to the next
   phase after explicit user go-ahead.

This applies to every phase, including the last one.

**Explicit override only:** the user may grant permission to run multiple phases
in one go and/or commit after each phase (e.g. "do phases 2–4 and commit each").
Honor it exactly as scoped — it covers only the phases named and only the current
session. Never infer this permission from tone, urgency, or past sessions; without
an explicit grant, the per-phase gate above stays in force.

## Common mistakes

- **Vague items** — each checkbox is a concrete task ("Add retry logic to
  `PaymentClient.Charge`"), not a theme ("improve payments").
- **Non-autonomous verification** — give runnable commands with expected output,
  not "test it manually".
- **Wrong location** — always the repo-root `plans/` folder.
- **Pre-filling summaries** — phase summaries, recap, and deployment plan stay as
  placeholders until that work actually completes.
- **Running ahead** — executing multiple phases in one turn instead of stopping
  after each phase for user review.
- **Auto-committing** — committing after a phase instead of suggesting a commit
  message and waiting for the user.
