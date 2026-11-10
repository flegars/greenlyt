#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_test() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt test <run-id>"
  local run_id=$1 command out rc=0
  command="$(gl_config_get .testCommand)"
  [ -n "$command" ] || gl_die "testCommand absent de .greenlyt/config.json"
  out="$(mktemp)"
  (cd "$(gl_root)" && bash -c "$command") > "$out" 2>&1 || rc=$?
  gl_state_update "$run_id" '.tests = {exitCode: $rc, tail: $tail}' \
    --argjson rc "$rc" --arg tail "$(tail -n 200 "$out")"
  tail -n 20 "$out"
  rm -f "$out"
  return "$rc"
}
