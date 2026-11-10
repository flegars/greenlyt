#!/usr/bin/env bash

source "$GL_LIB/state.sh"

preflight_fail() {
  printf 'greenlyt: %s\n' "$2" >&2
  exit "$1"
}

preflight_rollback() {
  git reset -q
  git checkout -q "$1"
  git branch -q -D "$2"
}

cmd_preflight() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt preflight <spec-path>"
  local spec=$1 root slug branch base remote start previous command
  root="$(gl_root)" || gl_die "not inside a git repository"
  cd "$root"

  gl_has_config || preflight_fail 10 "no config: run /greenlyt:init"
  [ -n "$(gl_config_get .testCommand)" ] || preflight_fail 10 "testCommand missing from .greenlyt/config.json"
  local known unknown
  known="$(cd "$GL_LIB/../agents" && ls -- *-reviewer.md | sed 's/-reviewer\.md$//' | jq -R . | jq -s -c .)"
  unknown="$(jq -r --argjson known "$known" 'if type == "array" and length > 0 then (. - $known | join(", ")) else "<reviewers must be a non-empty array>" end' \
    <<< "$(gl_config_get .reviewers null)")"
  [ -z "$unknown" ] || preflight_fail 10 "unknown reviewers in .greenlyt/config.json: $unknown (known: $(jq -r 'join(", ")' <<< "$known"))"
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
  if ! git rev-parse --verify --quiet "refs/heads/$base" >/dev/null; then
    git fetch -q "$remote" "$base" 2>/dev/null || true
    start="$remote/$base"
  fi
  previous="$(git branch --show-current)"
  git checkout -q -b "$branch" "$start" || preflight_fail 16 "cannot create branch $branch from $start"

  if ! gl_has_config || [ -z "$(gl_config_get .testCommand)" ] || [ ! -f "$spec" ]; then
    preflight_rollback "$previous" "$branch"
    preflight_fail 17 "the config or the spec is missing from $start: commit .greenlyt/config.json on $base"
  fi

  command="$(gl_config_get .testCommand)"
  if ! bash -c "$command" >/dev/null 2>&1; then
    preflight_rollback "$previous" "$branch"
    preflight_fail 15 "the test suite already fails on $start: fix it before running greenlyt"
  fi

  git add -- "$spec" && { git diff --cached --quiet || git commit -q -m "docs(greenlyt): spec $slug"; } || {
    preflight_rollback "$previous" "$branch"
    gl_die "cannot commit the spec $spec"
  }
  source "$GL_LIB/cmd_state.sh"
  state_init "$slug"
}
