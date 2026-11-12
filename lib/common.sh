#!/usr/bin/env bash

GL_DEFAULT_CONFIG='{
  "docsDir": "docs/greenlyt",
  "maxAttempts": 5,
  "protectedBranches": ["main", "master", "develop"],
  "branchPrefix": "feat/",
  "deviations": "ask",
  "reviewers": ["spec", "architecture", "security", "regression"],
  "refactor": true,
  "forge": {"type": "github", "remote": "origin", "baseBranch": "main"}
}'

gl_die() {
  printf 'greenlyt: %s\n' "$*" >&2
  exit 1
}

gl_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

gl_config_file() {
  printf '%s/.greenlyt/config.json' "$(gl_root)"
}

gl_has_config() {
  local root
  root="$(gl_root)" || return 1
  [ -f "$root/.greenlyt/config.json" ]
}

gl_config_json() {
  if gl_has_config; then
    jq -s '.[0] * .[1]' <(printf '%s' "$GL_DEFAULT_CONFIG") "$(gl_config_file)"
  else
    printf '%s' "$GL_DEFAULT_CONFIG"
  fi
}

gl_jq_value() {
  printf '(%s) as $v | if $v == null then empty elif ($v | type) == "array" or ($v | type) == "object" then ($v | tojson) else ($v | tostring) end' "$1"
}

gl_config_get() {
  local value
  value="$(gl_config_json | jq -r "$(gl_jq_value "$1")")" || return 1
  if [ -z "$value" ]; then
    printf '%s' "${2:-}"
  else
    printf '%s' "$value"
  fi
}

gl_killed() {
  [ "${GREENLYT_DISABLED:-}" = "1" ] && return 0
  local root
  root="$(gl_root)" || return 1
  [ -f "$root/.greenlyt/STOP" ]
}

gl_env_lock() {
  printf '%s/.greenlyt/state/env.lock' "$(gl_root)"
}

gl_env_id() {
  printf 'gl-%s' "$(gl_root | git hash-object --stdin | cut -c1-10)"
}

gl_test_command() {
  local lock
  lock="$(gl_env_lock)"
  if [ -f "$lock" ] && jq -e '.testCommand | type == "string" and length > 0' "$lock" >/dev/null 2>&1; then
    jq -r .testCommand "$lock"
  else
    gl_config_get .testCommand
  fi
}

# Environment recipes are shared by every worktree: they get the worktree path and a per-worktree id instead of hard-coded paths and names.
gl_run_shell() {
  local root
  root="$(gl_root)"
  (cd "$root" && GL_WORKTREE="$root" GL_ENV_ID="$(gl_env_id)" bash -c "$1")
}
