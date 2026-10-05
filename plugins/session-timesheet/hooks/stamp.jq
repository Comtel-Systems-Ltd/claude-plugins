# MessageDisplay: prefix the reply with the local time, on screen only.
# Lives in a file so no shell has to survive quoting it.
{
  hookSpecificOutput: {
    hookEventName: "MessageDisplay",
    displayContent: ("[" + (now | strflocaltime("%H:%M:%S")) + "] " + .content)
  }
}
