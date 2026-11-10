#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_refactor() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt refactor <start|done|revert> <run-id> [reason]"
  cd "$(gl_root)"
  case "$1" in
    start) refactor_start "$2" ;;
    done) refactor_done "$2" ;;
    revert) refactor_revert "$2" "${3:-}" ;;
    *) gl_die "unknown refactor subcommand: $1" ;;
  esac
}

refactor_start() {
  gl_state_update "$1" '.refactor = {greenCommit: $c, status: "running", green: {tests: .tests, verdict: .verdict}}' \
    --arg c "$(git rev-parse HEAD)"
}

refactor_done() {
  local green
  green="$(gl_state_get "$1" .refactor.greenCommit)"
  if [ "$(git rev-parse HEAD)" = "$green" ]; then
    gl_state_update "$1" '.refactor.status = "unchanged"'
  else
    gl_state_update "$1" '.refactor.status = "applied"'
  fi
}

refactor_revert() {
  local run_id=$1 reason=$2 branch green
  branch="$(gl_state_get "$run_id" .branch)"
  green="$(gl_state_get "$run_id" .refactor.greenCommit)"
  [ -n "$green" ] || gl_die "no refactoring in progress for $run_id"
  [ "$(git branch --show-current)" = "$branch" ] \
    || gl_die "refusing to revert: the current branch is not the run's work branch ($branch)"
  # Leftovers are stashed rather than deleted, so nothing the user may need is destroyed.
  if [ -n "$(git status --porcelain -- . ':(exclude).greenlyt' ":(exclude)$(gl_config_get .docsDir)/runs")" ]; then
    git stash push -q --include-untracked -m "greenlyt-refactor-$run_id" -- . ':(exclude).greenlyt' ":(exclude)$(gl_config_get .docsDir)/runs"
  fi
  git reset -q --hard "$green"
  # The verdict and test result of the green commit are restored: no re-review is needed after a revert.
  gl_state_update "$run_id" '.refactor.status = "reverted"
    | .refactor.reason = (if $r == "" then null else $r end)
    | .tests = .refactor.green.tests
    | .verdict = .refactor.green.verdict' --arg r "$reason"
}
