#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"testCommand":"exit 0"}'
printf '.greenlyt/state/\n' > .gitignore
mkdir -p tests src
echo "old test" > tests/OldTest.php
git add -A && git commit -q -m base
run_id="$("$GL_BIN" state init locks)"

echo "new test" > tests/ExportTest.php
echo "changed" >> tests/OldTest.php
assert_exit 0 "$GL_BIN" tests lock "$run_id"
assert_eq '["tests/ExportTest.php","tests/OldTest.php"]' \
  "$("$GL_BIN" state get "$run_id" '.lockedTests | keys')" "lock records added and modified files"
assert_eq "" "$("$GL_BIN" state get "$run_id" '.lockedTests["src/Export.php"]')" "only changed files are locked"
assert_exit 0 "$GL_BIN" tests check "$run_id"

echo "implementation" > src/Export.php
assert_exit 0 "$GL_BIN" tests check "$run_id"

verdict=".greenlyt/state/$run_id.verdict.locked-tests"
assert_eq '{"reviewer":"locked-tests","objections":[],"deviations":[],"specIssues":[]}' "$(jq -c . "$verdict")" "check writes an empty verdict when nothing changed"

echo "weakened" > tests/ExportTest.php
assert_exit 1 "$GL_BIN" tests check "$run_id"
assert_contains "tests/ExportTest.php" "$("$GL_BIN" tests check "$run_id" 2>&1)" "a modified locked file is named"
assert_eq critical "$(jq -r '.objections[0].severity' "$verdict")" "a modified locked test is a critical objection"
assert_contains "tests/ExportTest.php" "$(jq -r '.objections[0].detail' "$verdict")" "the objection names the file"
assert_exit 0 "$GL_BIN" verdict "$run_id" "$verdict"
echo "new test" > tests/ExportTest.php

git add -A && git commit -q -m "round 1"
assert_exit 0 "$GL_BIN" tests check "$run_id"
echo "coverage test" > tests/SortTest.php
assert_exit 0 "$GL_BIN" tests lock "$run_id"
assert_eq '["tests/ExportTest.php","tests/OldTest.php","tests/SortTest.php"]' \
  "$("$GL_BIN" state get "$run_id" '.lockedTests | keys')" "successive locks are merged"

rm tests/OldTest.php
assert_exit 1 "$GL_BIN" tests check "$run_id"
assert_contains "tests/OldTest.php" "$("$GL_BIN" tests check "$run_id" 2>&1)" "a deleted locked file is named"

assert_exit 1 "$GL_BIN" tests bogus "$run_id"

finish
