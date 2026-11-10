#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_commit_tour() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt commit-tour <run-id>"
  local attempt
  attempt="$(gl_state_get "$1" .attempt)"
  cd "$(gl_root)"
  git add -A -- . ':(exclude).greenlyt/state' ":(exclude)$(gl_config_get .docsDir)/runs"
  if git diff --cached --quiet; then
    echo "greenlyt: rien à commiter pour le tour $attempt"
    return 0
  fi
  git commit -q -m "chore(greenlyt): tour $attempt"
}
