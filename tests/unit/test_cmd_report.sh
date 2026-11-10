#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"testCommand":"echo 1 failure; exit 1","maxAttempts":2}'
run_id="$("$GL_BIN" state init export-csv)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
"$GL_BIN" test "$run_id" >/dev/null || true
verdict="$(mktemp)"
printf '%s' '{"approved":false,"objections":[{"ref":"AC-2","detail":"sorting not tested"}],"deviations":[{"description":"adds a header row","files":["src/Export.php"],"rationale":"readability"}],"specIssues":[{"question":"Which separator?","why":"AC-1 and AC-3 contradict each other"}]}' > "$verdict"
"$GL_BIN" verdict "$run_id" "$verdict"

path="$("$GL_BIN" report "$run_id" failure)"
assert_eq "docs/greenlyt/runs/$run_id.md" "$path" "report path"
report="$(cat "$path")"
assert_contains "Open questions" "$report" "open questions section"
assert_contains "Which separator?" "$report" "question listed"
assert_contains "AC-1 and AC-3 contradict each other" "$report" "rationale listed"
assert_contains "AC-2" "$report" "objection listed"
assert_contains "1 failure" "$report" "test output"
assert_contains "$run_id" "$report" "run-id"
assert_eq "" "$(grep -o '{{[a-zA-Z]*}}' "$path")" "no unsubstituted placeholder"

printf '%s' '{"approved":true,"objections":[],"deviations":[{"description":"adds a header row","files":["src/Export.php"],"rationale":"readability"}],"specIssues":[]}' > "$verdict"
"$GL_BIN" verdict "$run_id" "$verdict"
report="$(cat "$("$GL_BIN" report "$run_id" success)")"
assert_contains "adds a header row" "$report" "deviations listed"
assert_contains "src/Export.php" "$report" "deviation files"
assert_eq "" "$(printf '%s' "$report" | grep -o '{{[a-zA-Z]*}}')" "no unsubstituted placeholder (success)"

assert_exit 1 "$GL_BIN" report "$run_id" bogus

acceptance="$(mktemp)"
printf '| AC-1 | tests/ExportTest.php |\n' > "$acceptance"
body_path="$("$GL_BIN" report "$run_id" pr "$acceptance")"
assert_eq ".greenlyt/state/$run_id.pr-body.md" "$body_path" "pull request body outside docs"
body="$(cat "$body_path")"
assert_contains "| AC-1 | tests/ExportTest.php |" "$body" "AC → evidence table"
assert_contains "adds a header row" "$body" "deviations in the pull request"
assert_eq "" "$(printf '%s' "$body" | grep -o '{{[a-zA-Z]*}}')" "no unsubstituted placeholder (pull request)"
assert_exit 1 "$GL_BIN" report "$run_id" pr

finish
