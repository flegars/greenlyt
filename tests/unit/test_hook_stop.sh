#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

HOOK="$GL_PLUGIN_ROOT/hooks/stop.sh"

run_hook() {
  local rc=0
  HOOK_OUT="$(printf '{"cwd":"%s","stop_hook_active":%s}' "$1" "$2" | bash "$HOOK" 2>/dev/null)" || rc=$?
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
assert_eq "" "$HOOK_OUT" "cap reached: lets Claude stop"

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

finish
