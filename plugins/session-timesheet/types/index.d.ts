// Epoch ms per message, keyed by the message's normalised opening text.
export type SentAt = Record<string, number>

declare module 'claude-code' {
  interface PluginState {
    'session-timesheet': { sentAt: SentAt; answeredAt: SentAt }
  }
}
