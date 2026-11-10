#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

HOOK="$GL_PLUGIN_ROOT/hooks/guard-branch.sh"

guard() {
  local repo=$1 command=$2 rc=0
  jq -n --arg cwd "$repo" --arg c "$command" '{cwd: $cwd, tool_name: "Bash", tool_input: {command: $c}}' \
    | bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

denied() { assert_eq 2 "$(guard "$1" "$2")" "expected denial: $2 (on $(git -C "$1" branch --show-current))"; }
allowed() { assert_eq 0 "$(guard "$1" "$2")" "expected allow: $2 (on $(git -C "$1" branch --show-current))"; }

repo="$(mk_repo)"
allowed "$repo" "git commit -m x"
allowed "$repo" "git push"

write_config "$repo" '{}'
denied "$repo" "git commit -m x"
denied "$repo" "git push"
denied "$repo" "git reset --hard HEAD~1"
denied "$repo" "git rebase origin/main"
denied "$repo" "npm test && git commit -am x"
allowed "$repo" "git status"
allowed "$repo" "git log --oneline"
allowed "$repo" "echo 'git commit'"

err="$(jq -n --arg cwd "$repo" '{cwd: $cwd, tool_input: {command: "git commit -m x"}}' | bash "$HOOK" 2>&1 >/dev/null)"
assert_contains "main" "$err" "the message names the protected branch"

git -C "$repo" checkout -q -b greenlyt/foo
allowed "$repo" "git commit -m x"
allowed "$repo" "git push -u origin greenlyt/foo"
allowed "$repo" "git push"
denied "$repo" "git push origin HEAD:main"
denied "$repo" "git push origin main"
denied "$repo" "git push origin refs/heads/main"
denied "$repo" "git push -u origin greenlyt/foo:develop"
denied "$repo" "git status; git push origin HEAD:master"
denied "$repo" "git push --all origin"
denied "$repo" "git push --mirror origin"
denied "$repo" "git push origin 'main'"
denied "$repo" "git push origin \"main\""
denied "$repo" "(git push origin main)"
denied "$repo" "command git push origin main"
denied "$repo" "env GIT_TRACE=0 git push origin main"
denied "$repo" "bash -c \"git push origin main\""
denied "$repo" "sh -c 'git push origin HEAD:main'"
allowed "$repo" "git push origin HEAD"
allowed "$repo" "bash -c 'npm test'"

git -C "$repo" checkout -q main
denied "$repo" "git push origin HEAD"
other="$(mk_repo)"
git -C "$other" checkout -q -b feature
allowed "$repo" "git -C $other commit -m x"
git -C "$repo" checkout -q greenlyt/foo
git -C "$other" checkout -q main
denied "$repo" "git -C $other commit -m x"

repo="$(mk_repo)"
write_config "$repo" '{"protectedBranches":["release"]}'
allowed "$repo" "git commit -m x"
git -C "$repo" checkout -q -b release
denied "$repo" "git commit -m x"

finish
