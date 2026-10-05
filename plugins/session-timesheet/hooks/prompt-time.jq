# UserPromptSubmit: tell Claude when the prompt was sent, so it can answer questions
# about elapsed time. Context only - nothing is shown in the chat.
{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("Prompt sent at " + (now | strflocaltime("%Y-%m-%d %H:%M:%S %Z")) + ".")
  }
}
