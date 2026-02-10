#!/usr/bin/env bash

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: $(basename "$0") \"your prompt here\""
  exit 1
fi

user_prompt="$*"
completion_marker="<promise>DONE</promise>"
max_attempts=20
attempts_used=0

loop_instruction="Instruction: Continue working iteratively with a maximum of 20 total runs. Only when complete, end your output exactly with ${completion_marker}."
prompt="${user_prompt}

${loop_instruction}"

if ! command -v opencode >/dev/null 2>&1; then
  echo "Error: opencode CLI not found in PATH." >&2
  exit 1
fi

for attempt in $(seq 1 "$max_attempts"); do
  attempts_used="$attempt"
  output="$(opencode run "$prompt" 2>&1)" || {
    status=$?
    printf "%s\n" "$output"
    printf "[run-opencode-prompt] Failed on attempt %s/%s.\n" "$attempt" "$max_attempts" >&2
    exit "$status"
  }

  printf "%s\n" "$output"

  if printf "%s" "$output" | grep -Eq "${completion_marker}[[:space:]]*$"; then
    printf "[run-opencode-prompt] Completed in %s attempt(s).\n" "$attempts_used" >&2
    exit 0
  fi

  if [[ "$attempt" -lt "$max_attempts" ]]; then
    printf "[run-opencode-prompt] Attempt %s/%s did not end with %s. Retrying...\n" \
      "$attempt" "$max_attempts" "$completion_marker" >&2
  fi
done

printf "[run-opencode-prompt] Reached max attempts (%s) without %s at end of output.\n" \
  "$max_attempts" "$completion_marker" >&2
printf "[run-opencode-prompt] Iterations used: %s.\n" "$attempts_used" >&2
exit 2
