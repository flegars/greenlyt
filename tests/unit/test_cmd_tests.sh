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
verdict=".greenlyt/state/$run_id.verdict.locked-tests"

assert_exit 1 "$GL_BIN" tests lock "$run_id"
assert_exit 1 "$GL_BIN" tests lock "$run_id" tests/Missing.php
assert_exit 1 "$GL_BIN" tests lock "$run_id" .greenlyt/config.json

echo "new test" > tests/ExportTest.php
echo "changed" >> tests/OldTest.php
echo "generated" > .phpunit.result.cache
assert_exit 0 "$GL_BIN" tests lock "$run_id" tests/ExportTest.php tests/OldTest.php
assert_eq '["tests/ExportTest.php","tests/OldTest.php"]' \
  "$("$GL_BIN" state get "$run_id" '.lockedTests | keys')" "only the declared files are locked"
assert_exit 0 "$GL_BIN" tests check "$run_id"
assert_eq '{"reviewer":"locked-tests","objections":[],"deviations":[],"specIssues":[]}' "$(jq -c . "$verdict")" "check writes an empty verdict when nothing changed"

echo "implementation" > src/Export.php
echo "regenerated" > .phpunit.result.cache
assert_exit 0 "$GL_BIN" tests check "$run_id"

echo "weakened" > tests/ExportTest.php
assert_exit 1 "$GL_BIN" tests check "$run_id"
assert_contains "tests/ExportTest.php" "$("$GL_BIN" tests check "$run_id" 2>&1)" "a modified locked file is named"
assert_eq critical "$(jq -r '.objections[0].severity' "$verdict")" "a modified locked test is a critical objection"
assert_contains "tests/ExportTest.php" "$(jq -r '.objections[0].detail' "$verdict")" "the objection names the file"
assert_exit 0 "$GL_BIN" tests lock "$run_id" tests/ExportTest.php
assert_exit 1 "$GL_BIN" tests check "$run_id"
echo "new test" > tests/ExportTest.php
assert_exit 0 "$GL_BIN" tests check "$run_id"

echo "coverage test" > tests/SortTest.php
assert_exit 0 "$GL_BIN" tests lock "$run_id" tests/SortTest.php
assert_eq '["tests/ExportTest.php","tests/OldTest.php","tests/SortTest.php"]' \
  "$("$GL_BIN" state get "$run_id" '.lockedTests | keys')" "successive locks are merged"

rm tests/OldTest.php
assert_exit 1 "$GL_BIN" tests check "$run_id"
assert_contains "tests/OldTest.php" "$("$GL_BIN" tests check "$run_id" 2>&1)" "a deleted locked file is named"
git checkout -q tests/OldTest.php
echo "changed" >> tests/OldTest.php

write_config "$repo" '{"testCommand":"true"}'
assert_exit 1 "$GL_BIN" tests check "$run_id"
assert_contains ".greenlyt/config.json" "$(jq -r '.objections[].detail' "$verdict")" "a config change during the run is a critical objection"
write_config "$repo" '{"testCommand":"exit 0"}'
assert_exit 0 "$GL_BIN" tests check "$run_id"

assert_exit 1 "$GL_BIN" tests bogus "$run_id"

finish
