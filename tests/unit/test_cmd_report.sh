#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"testCommand":"echo 1 failure; exit 1","maxAttempts":2}'
run_id="$("$GL_BIN" state init export-csv)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
"$GL_BIN" test "$run_id" >/dev/null || true
tmp="$(mktemp -d)"

review() {
  printf '{"reviewer":"%s","objections":%s,"deviations":%s,"specIssues":%s}' "$1" "${2:-[]}" "${3:-[]}" "${4:-[]}" > "$tmp/$1.json"
  printf '%s' "$tmp/$1.json"
}

"$GL_BIN" verdict "$run_id" \
  "$(review spec '[{"ref":"AC-2","severity":"major","detail":"sorting not tested"}]' '[{"description":"adds a header row","files":["src/Export.php"],"rationale":"readability"}]' '[{"question":"Which separator?","why":"AC-1 and AC-3 contradict each other"}]')" \
  "$(review architecture '[{"ref":"architecture","severity":"minor","detail":"helper could live in Support"}]')" \
  "$(review security '[{"ref":"security","severity":"critical","detail":"path traversal in file name"}]')" \
  "$(review regression)"
"$GL_BIN" state tdd-warning "$run_id" "AC-3 tests were green before implementation"

path="$("$GL_BIN" report "$run_id" failure)"
assert_eq "docs/greenlyt/runs/$run_id.md" "$path" "report path"
report="$(cat "$path")"
assert_contains "Open questions" "$report" "open questions section"
assert_contains "Which separator?" "$report" "question listed"
assert_contains "AC-1 and AC-3 contradict each other" "$report" "rationale listed"
assert_contains "**AC-2** (major, spec): sorting not tested" "$report" "blocking objection listed with severity and reviewer"
assert_contains "(critical, security): path traversal" "$report" "critical objection listed"
assert_contains "| Round | Tests | spec | architecture | security | regression | Minor | Deviations |" "$report" "one column per reviewer"
assert_contains "| 1 | red (1) | 1 | 0 | 1 | 0 | 1 | 1 |" "$report" "per-reviewer blocking counts"
assert_contains "AC-3 tests were green before implementation" "$report" "TDD warnings listed"
assert_contains "1 failure" "$report" "test output"
assert_contains "$run_id" "$report" "run-id"
assert_eq "" "$(grep -o '{{[a-zA-Z]*}}' "$path")" "no unsubstituted placeholder"

write_config "$repo" '{"testCommand":"exit 0","maxAttempts":2}'
"$GL_BIN" test "$run_id" >/dev/null
"$GL_BIN" verdict "$run_id" \
  "$(review spec '[]' '[{"description":"adds a header row","files":["src/Export.php"],"rationale":"readability"}]')" \
  "$(review architecture '[{"ref":"architecture","severity":"minor","detail":"helper could live in Support"}]')" \
  "$(review security)" "$(review regression)"
report="$(cat "$("$GL_BIN" report "$run_id" success)")"
assert_contains "adds a header row" "$report" "deviations listed"
assert_contains "src/Export.php" "$report" "deviation files"
assert_contains "## Non-blocking remarks" "$report" "non-blocking remarks section"
assert_contains "(minor, architecture): helper could live in Support" "$report" "minor objection listed as a remark"
assert_contains "## Refactoring" "$report" "refactoring section"
assert_contains "Not run." "$report" "refactoring not run yet"
assert_eq "" "$(printf '%s' "$report" | grep -o '{{[a-zA-Z]*}}')" "no unsubstituted placeholder (success)"

assert_exit 1 "$GL_BIN" report "$run_id" bogus

acceptance="$(mktemp)"
printf '| AC-1 | tests/ExportTest.php |\n' > "$acceptance"
body_path="$("$GL_BIN" report "$run_id" pr "$acceptance")"
assert_eq ".greenlyt/state/$run_id.pr-body.md" "$body_path" "pull request body outside docs"
body="$(cat "$body_path")"
assert_contains "| AC-1 | tests/ExportTest.php |" "$body" "AC → evidence table"
assert_contains "adds a header row" "$body" "deviations in the pull request"
assert_contains "helper could live in Support" "$body" "non-blocking remarks in the pull request"
assert_contains "## Refactoring" "$body" "refactoring section in the pull request"
assert_eq "" "$(printf '%s' "$body" | grep -o '{{[a-zA-Z]*}}')" "no unsubstituted placeholder (pull request)"
assert_exit 1 "$GL_BIN" report "$run_id" pr

"$GL_BIN" refactor start "$run_id"
"$GL_BIN" verdict "$run_id" "$(review spec)" "$(review architecture)" "$(review security)" "$(review regression)"
"$GL_BIN" refactor done "$run_id"
assert_contains "| 1 (refactor) | green |" "$(cat "$("$GL_BIN" report "$run_id" success)")" "refactoring re-review rows are labelled"

write_config "$repo" '{"testCommand":"exit 0","refactor":false}'
assert_contains "Disabled in the config." "$(cat "$("$GL_BIN" report "$run_id" success)")" "refactoring disabled"

finish
