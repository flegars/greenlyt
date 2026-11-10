#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_verdict() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt verdict <run-id> <verdict-file>..."
  local run_id=$1 file merged
  shift
  for file in "$@"; do
    jq -e '(.reviewer | type == "string")
      and (.objections | type == "array")
      and all(.objections[]; (.severity | IN("critical", "major", "minor")) and (.ref | type == "string"))
      and (.deviations | type == "array")
      and (.specIssues | type == "array")' "$file" >/dev/null 2>&1 \
      || gl_die "invalid verdict $file: expected {reviewer, objections: [{ref, severity: critical|major|minor, detail}], deviations: [], specIssues: []}"
  done
  merged="$(jq -s -c --argjson expected "$(gl_config_get .reviewers)" '
    {
      reviews: .,
      objections: (map(.reviewer as $r | .objections[] | . + {reviewer: $r})),
      deviations: (map(.deviations[])),
      specIssues: (map(.specIssues[])),
      missing: ($expected - map(.reviewer))
    }
    | .blocking = ([.objections[] | select(.severity != "minor")] | length)' "$@")"
  gl_state_update "$run_id" '
    .verdict = ($v | .approved = (.blocking == 0 and (.missing | length) == 0 and $exit == 0))
    | .history += [{
        attempt: .attempt,
        exitCode: .tests.exitCode,
        approved: .verdict.approved,
        blocking: (reduce $v.reviews[] as $r ({}; .[$r.reviewer] = ([$r.objections[] | select(.severity != "minor")] | length))),
        minor: ([$v.objections[] | select(.severity == "minor")] | length),
        deviations: ($v.deviations | length)
      }]' \
    --argjson v "$merged" --argjson exit "$(gl_state_get "$run_id" '.tests.exitCode // -1')"
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
