#!/usr/bin/env bash
# Toute erreur interne doit laisser Claude s'arrêter : jamais de set -e ici.
set -u

GL_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$GL_LIB/common.sh"
source "$GL_LIB/state.sh"

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"

[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
gl_root >/dev/null || exit 0
gl_has_config || exit 0

runs="$(gl_running_runs)"
[ -n "$runs" ] || exit 0
if [ "$(printf '%s\n' "$runs" | wc -l | tr -d ' ')" -gt 1 ]; then
  printf 'greenlyt: plusieurs runs en cours, le hook Stop ne bloque pas : %s\n' "$(printf '%s' "$runs" | tr '\n' ' ')" >&2
  exit 0
fi
run_id=$runs

if gl_killed; then
  gl_state_update "$run_id" '.status = "aborted"'
  exit 0
fi

attempt="$(gl_state_get "$run_id" .attempt)" || exit 0
max="$(gl_state_get "$run_id" .maxAttempts)" || exit 0
last="$(gl_state_get "$run_id" .lastBlockedAttempt)" || exit 0

[ "$attempt" -ge "$max" ] && exit 0

if [ "$active" = "true" ] && [ "$attempt" = "$last" ]; then
  gl_state_update "$run_id" '.status = "stalled"'
  printf 'greenlyt: run %s bloqué sans progrès, marqué stalled\n' "$run_id" >&2
  exit 0
fi

gl_state_update "$run_id" '.lastBlockedAttempt = .attempt' || exit 0
jq -n --arg reason "Run greenlyt $run_id en cours (tour $attempt/$max) : poursuis le skill run au point où tu t'es arrêté." \
  '{decision: "block", reason: $reason}'
