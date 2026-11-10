#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"testCommand":"exit 0"}'
printf '.greenlyt/state/\n' > .gitignore
git add -A && git commit -q -m base
git checkout -q -b greenlyt/refacto
run_id="$("$GL_BIN" state init refacto)"
echo "green code" > code.txt
git add -A && git commit -q -m "green round"
green="$(git rev-parse HEAD)"

assert_exit 0 "$GL_BIN" refactor start "$run_id"
assert_eq "$green" "$("$GL_BIN" state get "$run_id" .refactor.greenCommit)" "start records the green commit"
assert_eq running "$("$GL_BIN" state get "$run_id" .refactor.status)" "refactoring in progress"

echo "refactored" > code.txt
echo "extracted" > helper.txt
git add code.txt && git commit -q -m "refactor"
echo "uncommitted" >> code.txt
mkdir -p docs/greenlyt/runs && echo keep > docs/greenlyt/runs/report.md

git checkout -q -b elsewhere
assert_exit 1 "$GL_BIN" refactor revert "$run_id"
assert_eq "$(git rev-parse greenlyt/refacto)" "$(git rev-parse HEAD)" "revert refused outside the work branch"
git checkout -q greenlyt/refacto

assert_exit 0 "$GL_BIN" refactor revert "$run_id" "tests went red"
assert_eq "$green" "$(git rev-parse HEAD)" "revert restores the green commit"
assert_eq "green code" "$(cat code.txt)" "revert restores tracked files"
assert_exit 1 test -e helper.txt
assert_exit 0 test -f ".greenlyt/state/$run_id.json"
assert_eq keep "$(cat docs/greenlyt/runs/report.md)" "revert keeps run reports"
assert_eq reverted "$("$GL_BIN" state get "$run_id" .refactor.status)" "status reverted"
assert_eq "tests went red" "$("$GL_BIN" state get "$run_id" .refactor.reason)" "revert reason recorded"

"$GL_BIN" refactor start "$run_id"
assert_exit 0 "$GL_BIN" refactor done "$run_id"
assert_eq applied "$("$GL_BIN" state get "$run_id" .refactor.status)" "status applied"
assert_exit 1 "$GL_BIN" refactor bogus "$run_id"

finish
