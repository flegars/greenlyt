#!/usr/bin/env bash
set -u
source "$(dirname "$0")/../unit/helpers.sh"

work=$1
remote=$2
cd "$work"

state="$(ls .greenlyt/state/*-budget.json 2>/dev/null | grep -v '\.pr\.json$' | head -n 1)"
assert_eq failed "$( [ -n "$state" ] && jq -r .status "$state")" "run failed"
report="$(ls docs/greenlyt/runs/*-budget.md 2>/dev/null | head -n 1)"
assert_contains "Open questions" "$( [ -n "$report" ] && cat "$report")" "failure report with open questions"
assert_eq "" "$(ls .greenlyt/state/*.pr.json 2>/dev/null)" "no pull request request"
assert_exit 1 git -C "$remote" rev-parse --verify --quiet feat/budget
assert_eq "$(git -C "$remote" rev-list --count main)" 1 "no commit added to main on the remote"

assert_exit 1 test -f .greenlyt/state/env.lock

finish || { echo "log: $work/.e2e-claude.log" >&2; exit 1; }
