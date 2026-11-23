#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

HOOK="$GL_PLUGIN_ROOT/hooks/stop.sh"

run_hook() {
  local rc=0
  HOOK_OUT="$(printf '{"cwd":"%s","stop_hook_active":%s,"session_id":"%s"}' "$1" "$2" "${3:-session-a}" | bash "$HOOK" 2>/dev/null)" || rc=$?
  HOOK_RC=$rc
}

status_of() {
  (cd "$1" && "$GL_BIN" state get "$2" .status)
}

new_run() {
  (cd "$1" && "$GL_BIN" state init "$2")
}

repo="$(mk_repo)"
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "no config: exit 0"
assert_eq "" "$HOOK_OUT" "no config: transparent"

write_config "$repo" '{"maxAttempts":3}'
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "no run: transparent"

run_id="$(new_run "$repo" feature)"
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "nominal case: exit 0"
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "nominal case: blocks"
assert_contains "$run_id" "$(printf '%s' "$HOOK_OUT" | jq -r .reason)" "the reason names the run"
assert_eq 1 "$(cd "$repo" && "$GL_BIN" state get "$run_id" .lastBlockedAttempt)" "lastBlockedAttempt updated"

run_hook "$repo" true
assert_eq "" "$HOOK_OUT" "stop_hook_active without progress: lets Claude stop"
assert_eq stalled "$(status_of "$repo" "$run_id")" "stop_hook_active without progress: stalled"

repo="$(mk_repo)"
write_config "$repo" '{"maxAttempts":3}'
run_id="$(new_run "$repo" progress)"
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" true
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "stop_hook_active with progress: blocks"

(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "cap reached while running: blocks once to finalize"
assert_contains "failure report" "$(printf '%s' "$HOOK_OUT" | jq -r .reason)" "cap reached: the reason asks for the failure step"
run_hook "$repo" true
assert_eq "" "$HOOK_OUT" "cap reached, woken again without progress: lets Claude stop"
assert_eq stalled "$(status_of "$repo" "$run_id")" "cap reached, no progress: stalled"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" session)"
run_hook "$repo" false session-a
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "unclaimed run: the first session claims it"
assert_eq session-a "$(cd "$repo" && "$GL_BIN" state get "$run_id" .sessionId)" "the claiming session is recorded"
run_hook "$repo" false session-b
assert_eq 0 "$HOOK_RC" "other session: exit 0"
assert_eq "" "$HOOK_OUT" "other session: transparent"
assert_eq running "$(status_of "$repo" "$run_id")" "other session: run untouched"
(cd "$repo" && "$GL_BIN" state set-status "$run_id" running)
assert_eq "" "$(cd "$repo" && "$GL_BIN" state get "$run_id" .sessionId)" "set-status running releases the session"
run_hook "$repo" false session-b
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "a resumed run is claimed by the new session"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" stop-file)"
touch "$repo/.greenlyt/STOP"
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "file kill switch: lets Claude stop"
assert_eq aborted "$(status_of "$repo" "$run_id")" "file kill switch: aborted"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" stop-env)"
HOOK_OUT="$(printf '{"cwd":"%s","stop_hook_active":false}' "$repo" | GREENLYT_DISABLED=1 bash "$HOOK" 2>/dev/null)"
assert_eq "" "$HOOK_OUT" "env kill switch: lets Claude stop"
assert_eq aborted "$(status_of "$repo" "$run_id")" "env kill switch: aborted"

repo="$(mk_repo)"
write_config "$repo" '{}'
new_run "$repo" one >/dev/null
sleep 1
new_run "$repo" two >/dev/null
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "two runs: exit 0"
assert_eq "" "$HOOK_OUT" "two runs: lets Claude stop"

repo="$(mk_repo)"
write_config "$repo" '{}'
mkdir -p "$repo/.greenlyt/state"
printf '{' > "$repo/.greenlyt/state/broken.json"
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "corrupt JSON: exit 0"
assert_eq "" "$HOOK_OUT" "corrupt JSON: lets Claude stop"

run_hook /nonexistent false
assert_eq 0 "$HOOK_RC" "invalid cwd: exit 0"
assert_eq "" "$HOOK_OUT" "invalid cwd: transparent"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" waiting-run)"
(cd "$repo" && "$GL_BIN" state set-status "$run_id" waiting)
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "waiting run: lets Claude stop"

mount_env() {
  mkdir -p "$1/.greenlyt/state"
  jq -n --arg t "touch $2" '{needed: true, id: "gl-test", testCommand: "exit 0", teardown: $t}' > "$1/.greenlyt/state/env.lock"
}

repo="$(mk_repo)"
write_config "$repo" '{}'
marker="$(mktemp -d)/torn-down"
mount_env "$repo" "$marker"
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "mounted environment, no run: lets Claude stop"
assert_exit 0 test -f "$marker"
assert_exit 1 test -f "$repo/.greenlyt/state/env.lock"

repo="$(mk_repo)"
write_config "$repo" '{"maxAttempts":3}'
marker="$(mktemp -d)/torn-down"
mount_env "$repo" "$marker"
run_id="$(new_run "$repo" busy)"
run_hook "$repo" false
assert_contains block "$HOOK_OUT" "mounted environment, running run: still blocks"
assert_exit 1 test -f "$marker"
touch "$repo/.greenlyt/STOP"
run_hook "$repo" false
assert_exit 0 test -f "$marker"

finish
