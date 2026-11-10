#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_verdict() {
  [ $# -eq 2 ] || gl_die "usage: greenlyt verdict <run-id> <fichier-json>"
  local run_id=$1 file=$2
  jq -e '(.approved | type == "boolean")
    and (.objections | type == "array")
    and (.deviations | type == "array")
    and (.specIssues | type == "array")' "$file" >/dev/null 2>&1 \
    || gl_die "verdict invalide : attendu {approved: bool, objections: [], deviations: [], specIssues: []}"
  gl_state_update "$run_id" \
    '.verdict = $v | .history += [{attempt: .attempt, exitCode: .tests.exitCode, approved: $v.approved,
      objections: ($v.objections | length), deviations: ($v.deviations | length)}]' \
    --argjson v "$(jq -c . "$file")"
}

cmd_decide() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt decide <run-id>"
  local exit_code approved attempt max
  exit_code="$(gl_state_get "$1" .tests.exitCode)"
  approved="$(gl_state_get "$1" '.verdict.approved // false')"
  attempt="$(gl_state_get "$1" .attempt)"
  max="$(gl_state_get "$1" .maxAttempts)"
  if [ "$exit_code" = "0" ] && [ "$approved" = "true" ]; then
    echo success
  elif [ "$attempt" -lt "$max" ]; then
    echo retry
  else
    echo exhausted
  fi
}
