# SessionStart: note when the session began, for elapsed-time questions later.
{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: ("Session started " + (now | strflocaltime("%Y-%m-%d %H:%M:%S %Z")) + ".")
  }
}
