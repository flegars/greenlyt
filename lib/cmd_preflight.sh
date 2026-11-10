#!/usr/bin/env bash

source "$GL_LIB/state.sh"

preflight_fail() {
  printf 'greenlyt: %s\n' "$2" >&2
  exit "$1"
}

cmd_preflight() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt preflight <spec-path>"
  local spec=$1 root slug branch base remote start previous command
  root="$(gl_root)" || gl_die "not inside a git repository"
  cd "$root"

  gl_has_config || preflight_fail 10 "no config: run /greenlyt:init"
  [ -n "$(gl_config_get .testCommand)" ] || preflight_fail 10 "testCommand missing from .greenlyt/config.json"
  gl_killed && preflight_fail 11 "kill switch is on (.greenlyt/STOP or GREENLYT_DISABLED=1)"
  [ -f "$spec" ] && grep -Eq '^Status[[:space:]]*:[[:space:]]*approved[[:space:]]*$' "$spec" \
    || preflight_fail 12 "spec $spec does not exist or is not approved (Status: approved)"
  [ -z "$(git status --porcelain --untracked-files=all -- . ':(exclude).greenlyt' ":(exclude)$spec")" ] \
    || preflight_fail 13 "the working tree has uncommitted changes"
  [ -z "$(gl_running_runs)" ] || preflight_fail 14 "a run is already in progress: $(gl_running_runs | tr '\n' ' ')"

  slug="$(basename "$spec" .md)"
  branch="$(gl_config_get .branchPrefix)$slug"
  base="$(gl_config_get .forge.baseBranch)"
  remote="$(gl_config_get .forge.remote)"
  git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null \
    && preflight_fail 16 "branch $branch already exists: resume the run or delete the branch"

  start="$base"
  if git remote get-url "$remote" >/dev/null 2>&1 && git fetch -q "$remote" "$base" 2>/dev/null; then
    start="$remote/$base"
  fi
  previous="$(git branch --show-current)"
  git checkout -q -b "$branch" "$start"

  command="$(gl_config_get .testCommand)"
  if ! bash -c "$command" >/dev/null 2>&1; then
    git checkout -q "$previous"
    git branch -q -D "$branch"
    preflight_fail 15 "the test suite already fails on $start: fix it before running greenlyt"
  fi

  git add -- "$spec"
  git diff --cached --quiet || git commit -q -m "docs(greenlyt): spec $slug"
  source "$GL_LIB/cmd_state.sh"
  state_init "$slug"
}
