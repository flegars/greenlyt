#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_verdict() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt verdict <run-id> <verdict-file>..."
  local run_id=$1 file merged expected locked_verdict
  shift
  locked_verdict="$(gl_state_dir)/$run_id.verdict.locked-tests"
  # The locked-tests verdict is picked up here so that the orchestrator cannot forget it.
  if [ -f "$locked_verdict" ]; then
    case " $* " in *" $locked_verdict "*) ;; *) set -- "$@" "$locked_verdict" ;; esac
  fi
  for file in "$@"; do
    jq -e '(.reviewer | type == "string")
      and (.objections | type == "array")
      and all(.objections[]; (.severity | IN("critical", "major", "minor")) and (.ref | type == "string"))
      and (.deviations | type == "array")
      and all(.deviations[]; (.description | type == "string") and (.files | type == "array") and (.rationale | type == "string"))
      and (.specIssues | type == "array")
      and all(.specIssues[]; (.question | type == "string") and (.why | type == "string"))' "$file" >/dev/null 2>&1 \
      || gl_die "invalid verdict $file: expected {reviewer, objections: [{ref, severity: critical|major|minor, detail}], deviations: [{description, files: [], rationale}], specIssues: [{question, why}]}"
  done
  expected="$(jq -c --argjson locked "$(gl_state_get "$run_id" '(.lockedTests // {}) | length')" \
    '. + (if $locked > 0 then ["locked-tests"] else [] end)' <<< "$(gl_config_get .reviewers)")"
  merged="$(jq -s -c --argjson expected "$expected" '
    {
      reviews: .,
      objections: (map(.reviewer as $r | .objections[] | . + {reviewer: $r})),
      deviations: (map(.deviations[]) | unique_by(.description)),
      specIssues: (map(.specIssues[]) | unique_by(.question)),
      missing: ($expected - map(.reviewer))
    }
    | .blocking = ([.objections[] | select(.severity != "minor")] | length)' "$@")"
  gl_state_update "$run_id" '
    .verdict = ($v | .approved = (.blocking == 0 and (.missing | length) == 0 and $exit == 0))
    | .history += [{
        attempt: .attempt,
        phase: (if .refactor.status == "running" then "refactor" else "round" end),
        exitCode: .tests.exitCode,
        approved: .verdict.approved,
        blocking: (reduce $v.reviews[] as $r ({}; .[$r.reviewer] = ([$r.objections[] | select(.severity != "minor")] | length))),
        minor: ([$v.objections[] | select(.severity == "minor")] | length),
        deviations: ($v.deviations | length)
      }]' \
    --argjson v "$merged" --argjson exit "$(gl_state_get "$run_id" '.tests.exitCode // -1')"
  # Consumed verdicts are removed: a reviewer that fails next round must not be counted with a stale approval.
  rm -f -- "$@"
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
