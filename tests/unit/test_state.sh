#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
source "$GL_PLUGIN_ROOT/lib/common.sh"
source "$GL_PLUGIN_ROOT/lib/state.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"maxAttempts":2}'

run_id="$("$GL_BIN" state init ajout-export)"
assert_contains "-ajout-export" "$run_id" "run-id format"
state_file=".greenlyt/state/$run_id.json"
assert_exit 0 jq -e . "$state_file"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "initial status"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .attempt)" "initial attempt"
assert_eq 2 "$("$GL_BIN" state get "$run_id" .maxAttempts)" "cap taken from config"
assert_eq greenlyt/ajout-export "$("$GL_BIN" state get "$run_id" .branch)" "work branch"
assert_eq docs/greenlyt/specs/ajout-export.md "$("$GL_BIN" state get "$run_id" .spec)" "spec path"
assert_eq -1 "$("$GL_BIN" state get "$run_id" .lastBlockedAttempt)" "initial lastBlockedAttempt"

assert_eq 1 "$("$GL_BIN" state next-attempt "$run_id")" "1st attempt"
assert_eq 2 "$("$GL_BIN" state next-attempt "$run_id")" "2nd attempt"
assert_exit 3 "$GL_BIN" state next-attempt "$run_id"
assert_eq 2 "$("$GL_BIN" state get "$run_id" .attempt)" "the cap is not exceeded"

assert_exit 1 "$GL_BIN" state set-status "$run_id" bogus
assert_exit 0 "$GL_BIN" state set-status "$run_id" waiting
assert_eq waiting "$("$GL_BIN" state get "$run_id" .status)" "waiting status"

printf '{' > .greenlyt/state/garbage.json
assert_eq "" "$(gl_running_runs 2>/dev/null)" "no running run, corrupt JSON skipped"
assert_contains garbage "$(gl_running_runs 2>&1 >/dev/null)" "warning on stderr"

assert_eq "$run_id" "$("$GL_BIN" state find ajout-export 2>/dev/null)" "find returns the waiting run"
assert_exit 1 "$GL_BIN" state find unknown

"$GL_BIN" state rebudget "$run_id"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .attempt)" "rebudget resets the counter"
assert_eq "[2,2]" "$("$GL_BIN" state get "$run_id" .budgets)" "rebudget records the budget"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "rebudget restarts the run"
assert_eq "$run_id" "$(gl_running_runs 2>/dev/null)" "the run is running again"

finish
