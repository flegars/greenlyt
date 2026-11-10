#!/usr/bin/env bash
set -u
source "$(dirname "$0")/../unit/helpers.sh"

work=$1
remote=$2
cd "$work"

state="$(ls .greenlyt/state/*-budget.json 2>/dev/null | grep -v '\.pr\.json$' | head -n 1)"
assert_eq failed "$( [ -n "$state" ] && jq -r .status "$state")" "run failed"
report="$(ls docs/greenlyt/runs/*-budget.md 2>/dev/null | head -n 1)"
assert_contains "Questions ouvertes" "$( [ -n "$report" ] && cat "$report")" "rapport d'échec avec questions ouvertes"
assert_eq "" "$(ls .greenlyt/state/*.pr.json 2>/dev/null)" "aucune requête de PR"
assert_exit 1 git -C "$remote" rev-parse --verify --quiet greenlyt/budget
assert_eq "$(git -C "$remote" rev-list --count main)" 1 "aucun commit ajouté sur main dans le remote"

finish || { echo "journal : $work/.e2e-claude.log" >&2; exit 1; }
