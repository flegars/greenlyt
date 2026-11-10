#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
source "$GL_PLUGIN_ROOT/lib/common.sh"
source "$GL_PLUGIN_ROOT/lib/state.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"maxAttempts":2}'

run_id="$("$GL_BIN" state init ajout-export)"
assert_contains "-ajout-export" "$run_id" "format du run-id"
state_file=".greenlyt/state/$run_id.json"
assert_exit 0 jq -e . "$state_file"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "statut initial"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .attempt)" "tentative initiale"
assert_eq 2 "$("$GL_BIN" state get "$run_id" .maxAttempts)" "plafond repris de la config"
assert_eq greenlyt/ajout-export "$("$GL_BIN" state get "$run_id" .branch)" "branche de travail"
assert_eq docs/greenlyt/specs/ajout-export.md "$("$GL_BIN" state get "$run_id" .spec)" "chemin de la spec"
assert_eq -1 "$("$GL_BIN" state get "$run_id" .lastBlockedAttempt)" "lastBlockedAttempt initial"

assert_eq 1 "$("$GL_BIN" state next-attempt "$run_id")" "1re tentative"
assert_eq 2 "$("$GL_BIN" state next-attempt "$run_id")" "2e tentative"
assert_exit 3 "$GL_BIN" state next-attempt "$run_id"
assert_eq 2 "$("$GL_BIN" state get "$run_id" .attempt)" "le plafond n'est pas dépassé"

assert_exit 1 "$GL_BIN" state set-status "$run_id" bogus
assert_exit 0 "$GL_BIN" state set-status "$run_id" waiting
assert_eq waiting "$("$GL_BIN" state get "$run_id" .status)" "statut waiting"

printf '{' > .greenlyt/state/garbage.json
assert_eq "" "$(gl_running_runs 2>/dev/null)" "aucun run running, JSON corrompu ignoré"
assert_contains garbage "$(gl_running_runs 2>&1 >/dev/null)" "avertissement sur stderr"

assert_eq "$run_id" "$("$GL_BIN" state find ajout-export 2>/dev/null)" "find retrouve le run waiting"
assert_exit 1 "$GL_BIN" state find inconnu

"$GL_BIN" state rebudget "$run_id"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .attempt)" "rebudget remet à zéro"
assert_eq "[2,2]" "$("$GL_BIN" state get "$run_id" .budgets)" "rebudget trace le budget"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "rebudget relance"
assert_eq "$run_id" "$(gl_running_runs 2>/dev/null)" "le run est de nouveau running"

finish
