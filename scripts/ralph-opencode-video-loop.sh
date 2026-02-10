#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ralph-opencode-video-loop.sh <codebase_path> <user_task>

Example:
  ralph-opencode-video-loop.sh "/Users/13point5/projects/rlx" \
    "Create deterministic agent-browser recording script for existing runs and logs"

Environment overrides:
  APP_URL                Default: http://localhost:3000
  CDP_PORT               Default: 9222
  CDP_PROFILE_DIR        Default: $HOME/Library/Application Support/Google/Chrome-RemoteDebug-RLX
  SESSION_NAME           Default: rlx-ralph-loop
  OUTPUT_SCRIPT          Default: scripts/generated-recording.sh
  MAX_ITERS              Default: 12
  MAX_STAGNATION         Default: 3
  SLEEP_SECS             Default: 1
  MODEL                  Optional: provider/model for opencode run
  AGENT                  Optional: named opencode agent
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

CODEBASE="${1:-}"
USER_TASK="${2:-}"

if [[ -z "${CODEBASE}" || -z "${USER_TASK}" ]]; then
  usage
  exit 1
fi

if [[ ! -d "${CODEBASE}" ]]; then
  echo "Error: codebase path does not exist: ${CODEBASE}"
  exit 1
fi

APP_URL="${APP_URL:-http://localhost:3000}"
CDP_PORT="${CDP_PORT:-9222}"
CDP_PROFILE_DIR="${CDP_PROFILE_DIR:-$HOME/Library/Application Support/Google/Chrome-RemoteDebug-RLX}"
SESSION_NAME="${SESSION_NAME:-rlx-ralph-loop}"
OUTPUT_SCRIPT="${OUTPUT_SCRIPT:-scripts/generated-recording.sh}"
MAX_ITERS="${MAX_ITERS:-12}"
MAX_STAGNATION="${MAX_STAGNATION:-3}"
SLEEP_SECS="${SLEEP_SECS:-1}"
MODEL="${MODEL:-}"
AGENT="${AGENT:-}"

RUN_ROOT="${RUN_ROOT:-${CODEBASE}/.opencode-ralph-video-runs}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="${RUN_ROOT}/${RUN_ID}"
PROMPT_FILE="${RUN_DIR}/prompt.txt"

mkdir -p "${RUN_DIR}"

if [[ "${OUTPUT_SCRIPT}" = /* ]]; then
  OUTPUT_SCRIPT_ABS="${OUTPUT_SCRIPT}"
else
  OUTPUT_SCRIPT_ABS="${CODEBASE}/${OUTPUT_SCRIPT}"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1"
    exit 1
  fi
}

require_cmd opencode
require_cmd perl
require_cmd shasum
require_cmd grep

APP_UP="unknown"
if command -v curl >/dev/null 2>&1 && curl -fsS "${APP_URL}" >/dev/null 2>&1; then
  APP_UP="true"
else
  APP_UP="false"
fi

CDP_UP="unknown"
if command -v curl >/dev/null 2>&1 && curl -fsS "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  CDP_UP="true"
else
  CDP_UP="false"
fi

cat > "${PROMPT_FILE}" <<EOF
You are running in a Ralph loop to generate deterministic UI-test video automation.

Inputs:
- Codebase root: ${CODEBASE}
- User goal: ${USER_TASK}
- App URL: ${APP_URL}
- CDP port: ${CDP_PORT}
- Session name: ${SESSION_NAME}
- Output script path: ${OUTPUT_SCRIPT}

Critical context:
- The app uses Clerk auth.
- Plain ephemeral agent-browser sessions are not reliable for auth persistence.
- You must use CDP + persistent Chrome profile workflow.

Reference scripts to copy patterns from:
- /Users/13point5/projects/video-pr-review/scripts/record-existing-runs-demo.sh
- /Users/13point5/projects/video-pr-review/scripts/relaunch-chrome-cdp.sh

MANDATORY FIRST STEPS:
1) Load and use the browser skill:
   - skill name: dev-browser
   - explicitly mention skill loaded in your response
2) Validate agent-browser CLI:
   - command -v agent-browser
   - agent-browser --help
   - agent-browser record --help
3) Validate CDP and auth strategy:
   - check http://localhost:${CDP_PORT}/json/version
   - use persistent profile directory: ${CDP_PROFILE_DIR}
   - use either:
     a) agent-browser --session ${SESSION_NAME} connect ${CDP_PORT} (once), then --session commands
     b) agent-browser --session ${SESSION_NAME} --cdp ${CDP_PORT} ... for each command

Mission:
1) Inspect codebase for relevant screens/routes/actions from the user goal.
2) Probe interactions with agent-browser commands to identify deterministic clicks/types/waits.
3) Write a deterministic shell script at ${OUTPUT_SCRIPT}.
4) The script must:
   - include set -euo pipefail
   - include preflight checks for agent-browser/curl/CDP/app readiness
   - include explicit non-destructive behavior (no "new run" actions)
   - use stable selectors or URL-pattern matching
   - record start/stop cleanly and emit final artifact path
   - include CDP-oriented instructions for Clerk auth persistence

Output protocol every iteration (required):
- short progress report
- <skill_loaded>true|false</skill_loaded>
- <cli_validated>true|false</cli_validated>
- <cdp_mode>true|false</cdp_mode>
- if blocked by missing secret/login only: <promise>BLOCKED</promise> with exact blocker
- if still working: <promise>CONTINUE</promise>
- only when fully complete and ${OUTPUT_SCRIPT} exists + runnable: <promise>DONE</promise>

Important:
- Do not claim DONE unless file exists at ${OUTPUT_SCRIPT} and contains agent-browser CDP usage.
EOF

cat <<EOF
Starting Ralph loop
- run_dir: ${RUN_DIR}
- app_up: ${APP_UP}
- cdp_up: ${CDP_UP}
- output_script: ${OUTPUT_SCRIPT_ABS}
EOF

if [[ "${CDP_UP}" != "true" ]]; then
  cat <<EOF
CDP endpoint is currently not reachable.
To launch Chrome with persistent CDP profile, you can run:
  /Users/13point5/projects/video-pr-review/scripts/relaunch-chrome-cdp.sh
EOF
fi

pushd "${CODEBASE}" >/dev/null

last_hash=""
stagnation=0

for ((i = 1; i <= MAX_ITERS; i++)); do
  echo "=== Iteration ${i}/${MAX_ITERS} ==="

  raw_log="${RUN_DIR}/iter-${i}.log"
  clean_log="${RUN_DIR}/iter-${i}.clean.log"
  prompt_text="$(<"${PROMPT_FILE}")"

  cmd=(opencode run --format default)
  if [[ -n "${MODEL}" ]]; then
    cmd+=(--model "${MODEL}")
  fi
  if [[ -n "${AGENT}" ]]; then
    cmd+=(--agent "${AGENT}")
  fi
  if (( i > 1 )); then
    cmd+=(--continue)
  fi
  cmd+=("${prompt_text}")

  "${cmd[@]}" 2>&1 | tee "${raw_log}"

  perl -pe 's/\e\[[0-9;]*[A-Za-z]//g' "${raw_log}" > "${clean_log}"

  if grep -Eqi '<promise>\s*BLOCKED\s*</promise>' "${clean_log}"; then
    echo "Blocked by missing prerequisite. See ${clean_log}"
    popd >/dev/null
    exit 2
  fi

  if grep -Eqi '<promise>\s*DONE\s*</promise>' "${clean_log}"; then
    if [[ -s "${OUTPUT_SCRIPT_ABS}" ]] \
      && grep -q 'agent-browser' "${OUTPUT_SCRIPT_ABS}" \
      && grep -Eq -- '--cdp| connect ' "${OUTPUT_SCRIPT_ABS}" \
      && grep -Eqi '<skill_loaded>\s*true\s*</skill_loaded>' "${clean_log}" \
      && grep -Eqi '<cli_validated>\s*true\s*</cli_validated>' "${clean_log}" \
      && grep -Eqi '<cdp_mode>\s*true\s*</cdp_mode>' "${clean_log}"; then
      echo "DONE. Generated deterministic script: ${OUTPUT_SCRIPT_ABS}"
      echo "Logs: ${RUN_DIR}"
      popd >/dev/null
      exit 0
    fi

    echo "DONE tag found, but checks failed. Continuing loop."
  fi

  cur_hash="$(shasum -a 256 "${clean_log}" | awk '{print $1}')"
  if [[ "${cur_hash}" == "${last_hash}" ]]; then
    stagnation=$((stagnation + 1))
  else
    stagnation=0
  fi
  last_hash="${cur_hash}"

  if (( stagnation >= MAX_STAGNATION )); then
    echo "Stopped due to stagnation (${MAX_STAGNATION} identical iterations)."
    echo "Logs: ${RUN_DIR}"
    popd >/dev/null
    exit 3
  fi

  sleep "${SLEEP_SECS}"
done

echo "Max iterations reached without DONE."
echo "Logs: ${RUN_DIR}"

popd >/dev/null
exit 4
