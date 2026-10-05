import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { SentAt } from '../types'

const sentAt = atom({ plugin: 'session-timesheet', key: 'sentAt' } as const, {} as SentAt)
const answeredAt = atom({ plugin: 'session-timesheet', key: 'answeredAt' } as const, {} as SentAt)

// Rows carry no timestamp, so messages are matched by their opening text.
// Submitted text has pastes expanded while the row shows them as typed, so only the head is compared.
const KEY_LENGTH = 40
const MAX_ENTRIES = 500

const PROMPT_STYLE = { dimColor: true }
// Claude's orange (#D97757) muted toward grey, so it stays quiet on a dark background.
const REPLY_STYLE = { color: '#A9826D' }

function keyOf(text: string): string {
  return text.replace(/\s+/g, ' ').trim().slice(0, KEY_LENGTH)
}

function clock(ms: number): string {
  const d = new Date(ms)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

function remember(map: SentAt | undefined, key: string, at: number): SentAt {
  // Drop the oldest once full; a repeat moves to the newest slot.
  const kept = Object.entries(map ?? {}).filter(([k]) => k !== key).slice(-(MAX_ENTRIES - 1))

  return Object.fromEntries([...kept, [key, at]])
}

export const register: Register = on => {
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'composer') {
      const now = await $.clock.now()
      await update($, sentAt, map => remember(map, keyOf(e.text), now))
    }

    return next(e)
  })

  // The final text of a turn opens its last text block, so the finish time lands on that block.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && e.answer.trim() !== '') {
      const now = await $.clock.now()
      await update($, answeredAt, map => remember(map, keyOf(e.answer), now))
    }

    return next(e)
  })

  // The engine's row is an opaque node and is refused under a Box that sizes it, so no width here.
  // flex-end puts the time on the row's last line rather than its first.
  on('ui.render', { component: 'UserMessage' }, async ($, e, next) => {
    const row = await next(e)

    if (e.props.origin.kind !== 'composer') {
      return row
    }

    // Messages from before the mod loaded have no record and draw unchanged.
    const at = (await read($, sentAt))[keyOf(e.props.text)]
    if (at === undefined) {
      return row
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="row" justifyContent="space-between" alignItems="flex-end">
        {row}
        <Text {...PROMPT_STYLE}>{clock(at)}</Text>
      </Box>
    )
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const row = await next(e)

    const at = (await read($, answeredAt))[keyOf(e.props.text)]
    if (at === undefined) {
      return row
    }

    const { Box, Text } = $.ui.resolve(e)

    return (
      <Box flexDirection="row" justifyContent="space-between" alignItems="flex-end">
        {row}
        <Text {...REPLY_STYLE}>{clock(at)}</Text>
      </Box>
    )
  })
}
