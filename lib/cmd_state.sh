#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_state() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt state <init|get|set-status|next-attempt|find|rebudget|tdd-warning> <arg> [...]"
  local sub=$1
  shift
  case "$sub" in
    init) state_init "$@" ;;
    get) gl_state_get "$1" "$2" ;;
    set-status) state_set_status "$@" ;;
    next-attempt) state_next_attempt "$1" ;;
    find) state_find "$1" ;;
    rebudget) state_rebudget "$1" ;;
    tdd-warning) gl_state_update "$1" '.tddWarnings += [$m]' --arg m "${2:?usage: greenlyt state tdd-warning <run-id> <message>}" ;;
    *) gl_die "unknown state subcommand: $sub" ;;
  esac
}

state_init() {
  local slug=$1 run_id max dir
  case "$slug" in */*|"") gl_die "invalid slug: $slug" ;; esac
  run_id="$(date +%Y%m%d-%H%M%S)-$slug"
  max="$(gl_config_get .maxAttempts)"
  dir="$(gl_state_dir)"
  mkdir -p "$dir"
  jq -n \
    --arg runId "$run_id" \
    --arg slug "$slug" \
    --arg spec "$(gl_config_get .docsDir)/specs/$slug.md" \
    --arg branch "$(gl_config_get .branchPrefix)$slug" \
    --arg base "$(gl_config_get .forge.baseBranch)" \
    --argjson max "$max" \
    --arg configHash "$(git hash-object "$(gl_config_file)" 2>/dev/null)" \
    '{runId: $runId, slug: $slug, spec: $spec, branch: $branch, baseBranch: $base,
      status: "running", attempt: 0, maxAttempts: $max, budgets: [$max],
      lastBlockedAttempt: -1, sessionId: null, configHash: (if $configHash == "" then null else $configHash end), tddWarnings: [], lockedTests: {}, refactor: null, tests: {exitCode: null, tail: ""}, verdict: null, history: []}' \
    > "$dir/$run_id.json"
  printf '%s\n' "$run_id"
}

state_set_status() {
  case " $GL_STATUSES " in
    *" $2 "*) gl_state_update "$1" '.status = $s | if $s == "running" then .sessionId = null else . end' --arg s "$2" ;;
    *) gl_die "invalid status: $2 (expected: $GL_STATUSES)" ;;
  esac
}

state_next_attempt() {
  local attempt max
  attempt="$(gl_state_get "$1" .attempt)"
  max="$(gl_state_get "$1" .maxAttempts)"
  if [ "$attempt" -ge "$max" ]; then
    printf 'greenlyt: attempt cap of %s reached\n' "$max" >&2
    exit 3
  fi
  gl_state_update "$1" '.attempt += 1'
  gl_state_get "$1" .attempt
  echo
}

state_find() {
  local found
  found="$( { local status; for status in running stalled waiting failed; do gl_state_ids_with_status "$status"; done; } \
    | grep -E -- "^[0-9]{8}-[0-9]{6}-$1\$" | sort | tail -n 1)"
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

state_rebudget() {
  gl_state_update "$1" '.attempt = 0 | .budgets += [.maxAttempts] | .lastBlockedAttempt = -1 | .sessionId = null | .status = "running"'
}
