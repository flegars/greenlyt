#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

export GREENLYT_HOME
GREENLYT_HOME="$(mktemp -d)"
trace="$(mktemp -d)"

repo="$(mk_repo)"
cd "$repo"
git remote add origin https://example.com/acme/app.git
write_config "$repo" '{"testCommand":"echo config-tests"}'
recipe="$(mktemp)"

assert_exit 1 "$GL_BIN" env show
assert_eq down "$("$GL_BIN" env status)" "nothing mounted at first"
assert_eq "echo config-tests" "$("$GL_BIN" env test-command)" "no environment: the config test command is used"

printf '{"testCommand": "exit 0"}' > "$recipe"
assert_exit 2 "$GL_BIN" env save "$recipe"
printf '{"needed": true, "setup": "true", "teardown": "", "testCommand": "exit 0"}' > "$recipe"
assert_exit 2 "$GL_BIN" env save "$recipe"
printf '{"needed": true, "setup": "true", "teardown": "true"}' > "$recipe"
assert_exit 2 "$GL_BIN" env save "$recipe"
printf 'not json' > "$recipe"
assert_exit 2 "$GL_BIN" env save "$recipe"
assert_exit 1 "$GL_BIN" env show

cat > "$recipe" <<EOF
{
  "needed": true,
  "summary": "disposable container mounting the worktree",
  "setup": "printf '%s %s' \"\$GL_WORKTREE\" \"\$GL_ENV_ID\" > $trace/setup",
  "testCommand": "printf '%s' \"\$GL_ENV_ID\" > $trace/tests; echo env-tests",
  "teardown": "touch $trace/teardown"
}
EOF
assert_exit 0 "$GL_BIN" env save "$recipe"
assert_eq "disposable container mounting the worktree" "$("$GL_BIN" env show | jq -r .summary)" "recipe remembered"
assert_contains "example.com/acme/app" "$("$GL_BIN" env show | jq -r .repository)" "recipe keyed by the repository"
assert_eq down "$("$GL_BIN" env status)" "saving does not mount"

worktree="$(mktemp -d)/wt"
git worktree add -q -b other "$worktree"
assert_eq "disposable container mounting the worktree" "$(cd "$worktree" && "$GL_BIN" env show | jq -r .summary)" "the recipe is shared by every worktree of the repository"

assert_exit 0 "$GL_BIN" env up
assert_eq up "$("$GL_BIN" env status)" "mounted"
read -r seen_root seen_id < "$trace/setup"
assert_eq "$repo" "$seen_root" "setup receives the worktree path"
assert_contains "gl-" "$seen_id" "setup receives an environment id"
assert_eq "env-tests" "$("$GL_BIN" env run-tests)" "run-tests uses the environment test command"
assert_eq "$seen_id" "$(cat "$trace/tests")" "the test command receives the environment id"
assert_contains "echo env-tests" "$("$GL_BIN" env test-command)" "test-command prints the environment test command"

run_id="$("$GL_BIN" state init env-run)"
"$GL_BIN" test "$run_id" >/dev/null
assert_eq 0 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "greenlyt test runs in the environment"
assert_contains env-tests "$("$GL_BIN" state get "$run_id" .tests.tail)" "greenlyt test output comes from the environment"

rm "$trace/setup"
assert_exit 0 "$GL_BIN" env up
assert_exit 1 test -f "$trace/setup"

other_id="$(cd "$worktree" && "$GL_BIN" env id)"
[ "$other_id" != "$seen_id" ] || _fail "each worktree gets its own environment id"

assert_exit 0 "$GL_BIN" env down
assert_exit 0 test -f "$trace/teardown"
assert_eq down "$("$GL_BIN" env status)" "unmounted"
rm "$trace/teardown"
assert_exit 0 "$GL_BIN" env down
assert_exit 1 test -f "$trace/teardown"

cat > "$recipe" <<EOF
{"needed": true, "setup": "exit 7", "testCommand": "exit 0", "teardown": "touch $trace/teardown"}
EOF
"$GL_BIN" env save "$recipe"
assert_exit 3 "$GL_BIN" env up
assert_exit 0 test -f "$trace/teardown"
assert_eq down "$("$GL_BIN" env status)" "failed setup: cleaned up and unmounted"
rm "$trace/teardown"

cat > "$recipe" <<EOF
{"needed": true, "setup": "exit 7", "testCommand": "exit 0", "teardown": "exit 5"}
EOF
"$GL_BIN" env save "$recipe"
assert_exit 3 "$GL_BIN" env up

cat > "$recipe" <<EOF
{"needed": true, "setup": "true", "testCommand": "exit 0", "teardown": "exit 5"}
EOF
"$GL_BIN" env save "$recipe"
"$GL_BIN" env up
assert_exit 4 "$GL_BIN" env down
assert_eq up "$("$GL_BIN" env status)" "failed teardown: still reported as mounted"
cat > "$recipe" <<EOF
{"needed": true, "setup": "true", "testCommand": "exit 0", "teardown": "touch $trace/teardown"}
EOF
"$GL_BIN" env save "$recipe"
assert_exit 4 "$GL_BIN" env down
assert_exit 1 test -f "$trace/teardown"

rm -f .greenlyt/state/env.lock
printf '{"needed": false, "reason": "tests run on the host"}' > "$recipe"
assert_exit 0 "$GL_BIN" env save "$recipe"
assert_exit 0 "$GL_BIN" env up
assert_eq "echo config-tests" "$("$GL_BIN" env test-command)" "environment not needed: the config test command is used"
assert_exit 0 "$GL_BIN" env down

assert_exit 0 "$GL_BIN" env forget
assert_exit 1 "$GL_BIN" env show
assert_exit 1 "$GL_BIN" env up

finish
