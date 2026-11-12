#!/usr/bin/env bash

cmd_env() {
  [ $# -ge 1 ] || gl_die "usage: greenlyt env <show|save|forget|up|down|status|id|test-command|run-tests> [file]"
  gl_root >/dev/null || gl_die "not inside a git repository"
  case "$1" in
    show) env_show ;;
    save) env_save "${2:-}" ;;
    forget) rm -f "$(env_recipe_file)" ;;
    up) env_up ;;
    down) env_down ;;
    status) if [ -f "$(gl_env_lock)" ]; then echo up; else echo down; fi ;;
    id) gl_env_id; echo ;;
    test-command) gl_test_command; echo ;;
    run-tests) gl_run_shell "$(gl_test_command)" ;;
    *) gl_die "unknown env subcommand: $1" ;;
  esac
}

env_repository() {
  git remote get-url "$(gl_config_get .forge.remote origin)" 2>/dev/null \
    || git rev-parse --path-format=absolute --git-common-dir
}

env_recipe_file() {
  local home=${GREENLYT_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/greenlyt}
  printf '%s/envs/%s.json' "$home" "$(env_repository | git hash-object --stdin)"
}

env_show() {
  local file
  file="$(env_recipe_file)"
  [ -f "$file" ] || return 1
  cat "$file"
}

env_save() {
  local source=$1 file tmp
  [ -f "$source" ] || gl_die "usage: greenlyt env save <recipe.json>"
  if ! jq -e '
      type == "object" and (.needed | type) == "boolean"
      and (if .needed then
        (.testCommand | type) == "string" and (.testCommand | length) > 0
        and ((.setup // "") | type) == "string" and ((.teardown // "") | type) == "string"
        and (((.setup // "") | length) == 0 or ((.teardown // "") | length) > 0)
      else true end)' "$source" >/dev/null 2>&1; then
    printf 'greenlyt: invalid recipe: needs "needed" (boolean); when needed, a non-empty "testCommand", and a "teardown" for any "setup"\n' >&2
    exit 2
  fi
  file="$(env_recipe_file)"
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "$file.XXXXXX")"
  jq --arg repo "$(env_repository)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '. + {repository: $repo, savedAt: $at}' "$source" > "$tmp" && mv "$tmp" "$file"
}

env_up() {
  local recipe lock out rc=0
  lock="$(gl_env_lock)"
  [ -f "$lock" ] && return 0
  recipe="$(env_show)" || { printf 'greenlyt: no test environment recipe for this repository\n' >&2; return 1; }
  mkdir -p "$(dirname "$lock")"
  if [ "$(jq -r .needed <<< "$recipe")" != "true" ]; then
    jq -n '{needed: false}' > "$lock"
    return 0
  fi
  out="$(mktemp)"
  gl_run_shell "$(jq -r '.setup // ""' <<< "$recipe")" > "$out" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    tail -n 40 "$out" >&2
    gl_run_shell "$(jq -r .teardown <<< "$recipe")" >/dev/null 2>&1 || true
    rm -f "$out"
    printf 'greenlyt: environment setup failed (exit %s), teardown run\n' "$rc" >&2
    return 3
  fi
  rm -f "$out"
  # The lock keeps its own copy of the commands: whatever happens to the recipe, down tears down what up mounted.
  jq --arg id "$(gl_env_id)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{needed: true, id: $id, mountedAt: $at, testCommand: .testCommand, teardown: .teardown}' <<< "$recipe" > "$lock"
}

env_down() {
  local lock out rc=0
  lock="$(gl_env_lock)"
  [ -f "$lock" ] || return 0
  if [ "$(jq -r .needed "$lock" 2>/dev/null)" = "true" ]; then
    out="$(mktemp)"
    gl_run_shell "$(jq -r .teardown "$lock")" > "$out" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
      tail -n 40 "$out" >&2
      rm -f "$out"
      printf 'greenlyt: environment teardown failed (exit %s): resources may still be mounted\n' "$rc" >&2
      return 4
    fi
    rm -f "$out"
  fi
  rm -f "$lock"
}
