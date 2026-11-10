#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 0"}'
run_id="$("$GL_BIN" state init verdict)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
tmp="$(mktemp -d)"

review() {
  local name=$1 objections=${2:-[]} deviations=${3:-[]}
  printf '{"reviewer":"%s","objections":%s,"deviations":%s,"specIssues":[]}' "$name" "$objections" "$deviations" > "$tmp/$name.json"
  printf '%s' "$tmp/$name.json"
}

all_clean() {
  printf '%s %s %s %s' "$(review spec)" "$(review architecture)" "$(review security)" "$(review regression)"
}

printf '{"objections":[],"specIssues":[]}' > "$tmp/no-reviewer.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/no-reviewer.json"
printf 'not json' > "$tmp/invalid.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/invalid.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$(review security '[{"ref":"security","severity":"blocker","detail":"x"}]')"
assert_exit 1 "$GL_BIN" verdict "$run_id"

"$GL_BIN" test "$run_id" >/dev/null
read -r -a files <<< "$(all_clean)"
files[0]="$(review spec '[{"ref":"AC-1","severity":"minor","detail":"naming"}]' '[{"description":"d","files":[],"rationale":"r"}]')"
assert_exit 0 "$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq true "$("$GL_BIN" state get "$run_id" .verdict.approved)" "a minor objection alone does not block"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .verdict.blocking)" "no blocking objection"
assert_eq 4 "$("$GL_BIN" state get "$run_id" '.verdict.reviews | length')" "four reviews merged"
assert_eq 1 "$("$GL_BIN" state get "$run_id" '.verdict.objections | length')" "minor objections are kept"
assert_eq 1 "$("$GL_BIN" state get "$run_id" '.verdict.deviations | length')" "deviations are merged"
assert_eq success "$("$GL_BIN" decide "$run_id")" "green, no blocking objection: success"

read -r -a files <<< "$(all_clean)"
files[0]="$(review spec '[{"ref":"AC-1","severity":"minor","detail":"naming"}]')"
files[2]="$(review security '[{"ref":"security","severity":"major","detail":"SQL built by concatenation"}]')"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "a major objection blocks"
assert_eq retry "$("$GL_BIN" decide "$run_id")" "blocking objection with budget left: retry"
assert_eq '{"spec":0,"architecture":0,"security":1,"regression":0}' \
  "$("$GL_BIN" state get "$run_id" '.history[1].blocking')" "history keeps blocking counts per reviewer"
assert_eq 1 "$("$GL_BIN" state get "$run_id" '.history[1].minor')" "history keeps the minor count"
assert_eq 1 "$("$GL_BIN" state get "$run_id" '.history[1].attempt')" "history keeps the attempt"

"$GL_BIN" verdict "$run_id" "$(review spec)" "$(review architecture)" "$(review security)"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "a missing expected reviewer blocks"
assert_contains regression "$("$GL_BIN" state get "$run_id" .verdict.missing)" "the missing reviewer is named"

write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 0","reviewers":["spec","architecture","security"]}'
"$GL_BIN" verdict "$run_id" "$(review spec)" "$(review architecture)" "$(review security)"
assert_eq true "$("$GL_BIN" state get "$run_id" .verdict.approved)" "a reviewer removed from the config is not required"

read -r -a files <<< "$(all_clean)"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_exit 1 test -e "${files[0]}"
assert_exit 1 test -e "${files[3]}"

read -r -a files <<< "$(all_clean)"
dup='[{"description":"adds a header row","files":["a"],"rationale":"r"}]'
files[0]="$(review spec '[]' "$dup")"
files[1]="$(review architecture '[]' "$dup")"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq 1 "$("$GL_BIN" state get "$run_id" '.verdict.deviations | length')" "duplicate deviations are merged once"

assert_exit 1 "$GL_BIN" verdict "$run_id" "$(review spec '[]' '[{"description":"no files"}]')"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$(review spec '[]' '[{"description":"d","files":"a.php","rationale":"r"}]')"
printf '{"reviewer":"spec","objections":[],"deviations":[],"specIssues":[{"why":"no question"}]}' > "$tmp/bad-issue.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/bad-issue.json"

"$GL_BIN" state get "$run_id" .runId >/dev/null
jq '.lockedTests = {"tests/ATest.php": "abc"}' ".greenlyt/state/$run_id.json" > tmp.json && mv tmp.json ".greenlyt/state/$run_id.json"
read -r -a files <<< "$(all_clean)"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "locked tests without a locked-tests verdict: not approved"
assert_contains locked-tests "$("$GL_BIN" state get "$run_id" .verdict.missing)" "the locked-tests check is named as missing"
printf '{"reviewer":"locked-tests","objections":[],"deviations":[],"specIssues":[]}' > ".greenlyt/state/$run_id.verdict.locked-tests"
read -r -a files <<< "$(all_clean)"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq true "$("$GL_BIN" state get "$run_id" .verdict.approved)" "the locked-tests verdict is picked up from the state dir"
assert_eq round "$("$GL_BIN" state get "$run_id" '.history[-1].phase')" "history rows carry their phase"
"$GL_BIN" refactor start "$run_id"
read -r -a files <<< "$(all_clean)"
printf '{"reviewer":"locked-tests","objections":[],"deviations":[],"specIssues":[]}' > ".greenlyt/state/$run_id.verdict.locked-tests"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq refactor "$("$GL_BIN" state get "$run_id" '.history[-1].phase')" "re-review during refactoring is tagged"
jq '.lockedTests = {} | .refactor = null' ".greenlyt/state/$run_id.json" > tmp.json && mv tmp.json ".greenlyt/state/$run_id.json"

write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 1"}'
"$GL_BIN" test "$run_id" >/dev/null
read -r -a files <<< "$(all_clean)"
"$GL_BIN" verdict "$run_id" "${files[@]}"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "red tests are never approved"
assert_eq retry "$("$GL_BIN" decide "$run_id")" "red with budget left: retry"

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
