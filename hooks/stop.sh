#!/usr/bin/env bash
# Any internal error must let Claude stop: never set -e here.
set -u

GL_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$GL_LIB/common.sh"
source "$GL_LIB/state.sh"

# Safety net: once no run is in progress, nothing greenlyt mounted for the tests may outlive the session.
release_env() {
  [ -f "$(gl_env_lock)" ] || return 0
  "$GL_LIB/../bin/greenlyt" env down >/dev/null 2>&1 \
    || printf 'greenlyt: test environment teardown failed, run "greenlyt env down" by hand\n' >&2
}

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
gl_root >/dev/null || exit 0
gl_has_config || exit 0

runs="$(gl_running_runs)"
[ -n "$runs" ] || { release_env; exit 0; }
if [ "$(printf '%s\n' "$runs" | wc -l | tr -d ' ')" -gt 1 ]; then
  printf 'greenlyt: several runs in progress, Stop hook does not block: %s\n' "$(printf '%s' "$runs" | tr '\n' ' ')" >&2
  exit 0
fi
run_id=$runs

if gl_killed; then
  gl_state_update "$run_id" '.status = "aborted"'
  release_env
  exit 0
fi

owner="$(gl_state_get "$run_id" .sessionId)" || exit 0
# A run belongs to the session that runs the loop: never block another session in the same repo.
[ -n "$owner" ] && [ -n "$session" ] && [ "$owner" != "$session" ] && exit 0

attempt="$(gl_state_get "$run_id" .attempt)" || exit 0
max="$(gl_state_get "$run_id" .maxAttempts)" || exit 0
last="$(gl_state_get "$run_id" .lastBlockedAttempt)" || exit 0

if [ "$active" = "true" ] && [ "$attempt" = "$last" ]; then
  gl_state_update "$run_id" '.status = "stalled"'
  printf 'greenlyt: run %s blocked without progress, marked stalled\n' "$run_id" >&2
  release_env
  exit 0
fi

gl_state_update "$run_id" '.lastBlockedAttempt = .attempt | .sessionId = (if $s == "" then .sessionId else $s end)' \
  --arg s "$session" || exit 0
if [ "$attempt" -ge "$max" ]; then
  reason="greenlyt run $run_id has used its $max rounds: finish step 4 of the run skill (failure report, status failed) before stopping."
else
  reason="greenlyt run $run_id in progress (round $attempt/$max): continue the run skill where you left off."
fi
jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
