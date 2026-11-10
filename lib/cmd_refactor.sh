#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_refactor() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt refactor <start|done|revert> <run-id> [reason]"
  cd "$(gl_root)"
  case "$1" in
    start) gl_state_update "$2" '.refactor = {greenCommit: $c, status: "running"}' --arg c "$(git rev-parse HEAD)" ;;
    done) gl_state_update "$2" '.refactor.status = "applied"' ;;
    revert) refactor_revert "$2" "${3:-}" ;;
    *) gl_die "unknown refactor subcommand: $1" ;;
  esac
}

refactor_revert() {
  local run_id=$1 reason=$2 branch green
  branch="$(gl_state_get "$run_id" .branch)"
  green="$(gl_state_get "$run_id" .refactor.greenCommit)"
  [ -n "$green" ] || gl_die "no refactoring in progress for $run_id"
  [ "$(git branch --show-current)" = "$branch" ] \
    || gl_die "refusing to revert: the current branch is not the run's work branch ($branch)"
  git reset -q --hard "$green"
  git clean -q -fd -e .greenlyt/ -e "$(gl_config_get .docsDir)/runs/"
  gl_state_update "$run_id" '.refactor.status = "reverted" | .refactor.reason = (if $r == "" then null else $r end)' --arg r "$reason"
}
