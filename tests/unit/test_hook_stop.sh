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
assert_eq 0 "$HOOK_RC" "sans config : code 0"
assert_eq "" "$HOOK_OUT" "sans config : transparent"

write_config "$repo" '{"maxAttempts":3}'
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "aucun run : transparent"

run_id="$(new_run "$repo" feature)"
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "cas nominal : code 0"
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "cas nominal : bloque"
assert_contains "$run_id" "$(printf '%s' "$HOOK_OUT" | jq -r .reason)" "la raison nomme le run"
assert_eq 1 "$(cd "$repo" && "$GL_BIN" state get "$run_id" .lastBlockedAttempt)" "lastBlockedAttempt mis à jour"

run_hook "$repo" true
assert_eq "" "$HOOK_OUT" "stop_hook_active sans progrès : laisse s'arrêter"
assert_eq stalled "$(status_of "$repo" "$run_id")" "stop_hook_active sans progrès : stalled"

repo="$(mk_repo)"
write_config "$repo" '{"maxAttempts":3}'
run_id="$(new_run "$repo" progres)"
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" true
assert_eq block "$(printf '%s' "$HOOK_OUT" | jq -r .decision)" "stop_hook_active avec progrès : bloque"

(cd "$repo" && "$GL_BIN" state next-attempt "$run_id" >/dev/null)
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "plafond atteint : laisse s'arrêter"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" stop-fichier)"
touch "$repo/.greenlyt/STOP"
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "kill switch fichier : laisse s'arrêter"
assert_eq aborted "$(status_of "$repo" "$run_id")" "kill switch fichier : aborted"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" stop-env)"
HOOK_OUT="$(printf '{"cwd":"%s","stop_hook_active":false}' "$repo" | GREENLYT_DISABLED=1 bash "$HOOK" 2>/dev/null)"
assert_eq "" "$HOOK_OUT" "kill switch env : laisse s'arrêter"
assert_eq aborted "$(status_of "$repo" "$run_id")" "kill switch env : aborted"

repo="$(mk_repo)"
write_config "$repo" '{}'
new_run "$repo" un >/dev/null
sleep 1
new_run "$repo" deux >/dev/null
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "deux runs : code 0"
assert_eq "" "$HOOK_OUT" "deux runs : laisse s'arrêter"

repo="$(mk_repo)"
write_config "$repo" '{}'
mkdir -p "$repo/.greenlyt/state"
printf '{' > "$repo/.greenlyt/state/casse.json"
run_hook "$repo" false
assert_eq 0 "$HOOK_RC" "JSON corrompu : code 0"
assert_eq "" "$HOOK_OUT" "JSON corrompu : laisse s'arrêter"

run_hook /nonexistent false
assert_eq 0 "$HOOK_RC" "cwd invalide : code 0"
assert_eq "" "$HOOK_OUT" "cwd invalide : transparent"

repo="$(mk_repo)"
write_config "$repo" '{}'
run_id="$(new_run "$repo" attente)"
(cd "$repo" && "$GL_BIN" state set-status "$run_id" waiting)
run_hook "$repo" false
assert_eq "" "$HOOK_OUT" "run waiting : laisse s'arrêter"

finish
