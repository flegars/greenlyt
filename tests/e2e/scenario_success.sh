#!/usr/bin/env bash
set -u
source "$(dirname "$0")/../unit/helpers.sh"

work=$1
remote=$2
cd "$work"

state="$(ls .greenlyt/state/*-success.json 2>/dev/null | grep -v '\.pr\.json$' | head -n 1)"
assert_eq succeeded "$( [ -n "$state" ] && jq -r .status "$state")" "run succeeded"
request="$(ls .greenlyt/state/*.pr.json 2>/dev/null | head -n 1)"
assert_eq main "$( [ -n "$request" ] && jq -r .base "$request")" "draft pull request request targeting main"
assert_eq true "$( [ -n "$request" ] && jq -r .draft "$request")" "draft pull request"
assert_eq "$(git -C "$remote" rev-list --count main)" 1 "no commit added to main on the remote"
assert_exit 0 git -C "$remote" rev-parse --verify --quiet feat/success

assert_exit 1 test -f .greenlyt/state/env.lock

finish || { echo "log: $work/.e2e-claude.log" >&2; exit 1; }
