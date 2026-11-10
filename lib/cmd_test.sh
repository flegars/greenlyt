#!/usr/bin/env bash

source "$GL_LIB/state.sh"

GL_TAIL_LINES=200
GL_TAIL_BYTES=65536

cmd_test() {
  [ $# -eq 1 ] || gl_die "usage: greenlyt test <run-id>"
  local run_id=$1 command out tail_file rc=0
  command="$(gl_config_get .testCommand)"
  [ -n "$command" ] || gl_die "testCommand missing from .greenlyt/config.json"
  # Reset first: if recording the result fails, no stale green result may survive.
  gl_state_update "$run_id" '.tests = {exitCode: null, tail: ""}'
  out="$(mktemp)"
  tail_file="$(mktemp)"
  (cd "$(gl_root)" && bash -c "$command") > "$out" 2>&1 || rc=$?
  tail -n "$GL_TAIL_LINES" "$out" | tail -c "$GL_TAIL_BYTES" > "$tail_file"
  gl_state_update "$run_id" '.tests = {exitCode: $rc, tail: ($tail | rtrimstr("\n"))}' \
    --argjson rc "$rc" --rawfile tail "$tail_file"
  tail -n 20 "$out" | tail -c 4096
  rm -f "$out" "$tail_file"
  return "$rc"
}
