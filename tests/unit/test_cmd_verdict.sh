#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 0"}'
run_id="$("$GL_BIN" state init verdict)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
tmp="$(mktemp -d)"

printf '{"approved":true,"objections":[],"specIssues":[]}' > "$tmp/no-deviations.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/no-deviations.json"
printf '{"approved":"oui","objections":[],"deviations":[],"specIssues":[]}' > "$tmp/approved-string.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/approved-string.json"
printf 'not json' > "$tmp/invalid.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/invalid.json"

printf '{"approved":false,"objections":[{"ref":"AC-1","detail":"x"}],"deviations":[{"description":"d","files":[],"rationale":"r"}],"specIssues":[]}' > "$tmp/rejected.json"
"$GL_BIN" test "$run_id" >/dev/null
assert_exit 0 "$GL_BIN" verdict "$run_id" "$tmp/rejected.json"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "verdict recorded"
assert_eq '{"attempt":1,"exitCode":0,"approved":false,"objections":1,"deviations":1}' \
  "$("$GL_BIN" state get "$run_id" '.history[0]')" "round history"
assert_eq retry "$("$GL_BIN" decide "$run_id")" "rejected with budget left: retry"

printf '{"approved":true,"objections":[],"deviations":[],"specIssues":[]}' > "$tmp/ok.json"
"$GL_BIN" verdict "$run_id" "$tmp/ok.json"
assert_eq success "$("$GL_BIN" decide "$run_id")" "green and approved: success"

write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 1"}'
"$GL_BIN" test "$run_id" >/dev/null
assert_eq retry "$("$GL_BIN" decide "$run_id")" "approved but red: retry"

"$GL_BIN" state next-attempt "$run_id" >/dev/null
assert_eq exhausted "$("$GL_BIN" decide "$run_id")" "red with no budget: exhausted"

git checkout -q -b greenlyt/verdict
echo change > file.txt
mkdir -p docs/greenlyt/runs && echo report > docs/greenlyt/runs/failure.md
"$GL_BIN" test "$run_id" >/dev/null || true
assert_exit 0 "$GL_BIN" commit-tour "$run_id"
assert_eq "chore(greenlyt): round 2" "$(git log -1 --format=%s)" "round commit message"
assert_eq "" "$(git ls-files .greenlyt/state)" "state is never committed"
assert_eq "" "$(git status --porcelain -- file.txt)" "changes are committed"
assert_eq "" "$(git ls-files docs/greenlyt/runs)" "reports never go into round commits"
assert_exit 0 "$GL_BIN" commit-tour "$run_id"

finish
