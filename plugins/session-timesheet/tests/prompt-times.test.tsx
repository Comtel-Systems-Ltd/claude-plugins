import { expect, mock, test } from 'claude-code/testing'

const TIME = /^\d\d:\d\d:\d\d$/
const SENT = Date.UTC(2026, 9, 4, 21, 55, 35)

const composer = { kind: 'composer' } as const

// What the engine answers from next(e): an opaque node, not a tree.
const ENGINE_ROW = { type: 'engine', ref: 0 } as const

function row(text: string) {
  return { text, origin: composer, isExpanded: true }
}

test('a submitted prompt shows its send time; others draw unchanged', async ($, on) => {
  mock.clock(on, { now: SENT })

  // Stand in for the engine beneath the plugin.
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  on('ui.render', { component: 'UserMessage' }, () => ENGINE_ROW)

  await $.prompt.submit({ text: "What's next in the plan?", wait: false, origin: composer })

  for (const surface of ['terminal', 'desktop'] as const) {
    const stamped = await $.ui.mount({
      plugin: 'session-timesheet',
      surface,
      component: 'UserMessage',
      props: row("What's next in the plan?"),
    })
    const time = await stamped.find({ type: 'Text', text: TIME })
    expect(time).toBeDefined()
    expect(time?.text).toBe(new Date(SENT).toTimeString().slice(0, 8))
    // The engine's own row is kept, not replaced.
    expect(await stamped.find({ type: 'engine' })).toBeDefined()
    await stamped.unmount()

    const unknown = await $.ui.mount({
      plugin: 'session-timesheet',
      surface,
      component: 'UserMessage',
      props: row('Never submitted while the mod was loaded'),
    })
    expect(await unknown.find({ type: 'Text', text: TIME })).toBeUndefined()
    await unknown.unmount()
  }
})

test('a paste expanded on submit still matches the row as typed', async ($, on) => {
  mock.clock(on, { now: SENT })
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  on('ui.render', { component: 'UserMessage' }, () => ENGINE_ROW)

  const head = 'Can you check the firmware for the stall we saw at page 2048 '
  await $.prompt.submit({ text: head + 'PASTED LOG LINES '.repeat(50), wait: false, origin: composer })

  const ui = await $.ui.mount({
    plugin: 'session-timesheet',
    surface: 'terminal',
    component: 'UserMessage',
    props: row(head + '[Pasted text #1 +50 lines]'),
  })
  expect(await ui.find({ type: 'Text', text: TIME })).toBeDefined()
  await ui.unmount()
})

test('notifications and other senders are never stamped', async ($, on) => {
  mock.clock(on, { now: SENT })
  on('prompt.submit', (_$, e) => ({ text: e.text }))
  on('ui.render', { component: 'UserMessage' }, () => ENGINE_ROW)

  await $.prompt.submit({ text: 'Background task finished', wait: false, origin: composer })

  const ui = await $.ui.mount({
    plugin: 'session-timesheet',
    surface: 'terminal',
    component: 'UserMessage',
    props: { text: 'Background task finished', origin: { kind: 'task-notification' }, isExpanded: true },
  })
  expect(await ui.find({ type: 'Text', text: TIME })).toBeUndefined()
  await ui.unmount()
})

test('a reply shows when its turn finished, on its final block only', async ($, on) => {
  mock.clock(on, { now: SENT })
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('ui.render', { component: 'AssistantMessage' }, () => ENGINE_ROW)

  await $.turn.complete({
    answer: 'Fixed, and it reloads when this turn ends.',
    durationMs: 4200,
    isAborted: false,
    turnId: 'turn-1',
    reason: 'answer',
  })

  for (const surface of ['terminal', 'desktop'] as const) {
    const last = await $.ui.mount({
      plugin: 'session-timesheet',
      surface,
      component: 'AssistantMessage',
      props: { text: 'Fixed, and it reloads when this turn ends.', isFirstOfReply: false },
    })
    const time = await last.find({ type: 'Text', text: TIME })
    expect(time?.text).toBe(new Date(SENT).toTimeString().slice(0, 8))
    expect(time?.props.color).toBe('#A9826D')
    expect(await last.find({ type: 'engine' })).toBeDefined()
    // On the block's last line, not its first.
    expect((await last.find({ type: 'Box' }))?.props.alignItems).toBe('flex-end')
    await last.unmount()

    const earlier = await $.ui.mount({
      plugin: 'session-timesheet',
      surface,
      component: 'AssistantMessage',
      props: { text: 'Checking the log before I change anything.', isFirstOfReply: true },
    })
    expect(await earlier.find({ type: 'Text', text: TIME })).toBeUndefined()
    await earlier.unmount()
  }
})

test("a subagent's turn and an empty answer stamp nothing", async ($, on) => {
  mock.clock(on, { now: SENT })
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  on('ui.render', { component: 'AssistantMessage' }, () => ENGINE_ROW)

  await $.turn.complete({ answer: 'Subagent summary text', durationMs: 1, isAborted: false, turnId: 't-2', reason: 'answer', agentId: 'agent-7' })
  await $.turn.complete({ answer: '   ', durationMs: 1, isAborted: false, turnId: 't-3', reason: 'answer' })

  const ui = await $.ui.mount({
    plugin: 'session-timesheet',
    surface: 'terminal',
    component: 'AssistantMessage',
    props: { text: 'Subagent summary text', isFirstOfReply: true },
  })
  expect(await ui.find({ type: 'Text', text: TIME })).toBeUndefined()
  await ui.unmount()
})
