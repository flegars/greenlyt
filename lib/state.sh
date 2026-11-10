#!/usr/bin/env bash

GL_STATUSES="running waiting succeeded failed aborted stalled"

gl_state_dir() {
  printf '%s/.greenlyt/state' "$(gl_root)"
}

gl_state_file() {
  printf '%s/%s.json' "$(gl_state_dir)" "$1"
}

gl_state_ids_with_status() {
  local dir file
  dir="$(gl_state_dir)"
  [ -d "$dir" ] || return 0
  for file in "$dir"/*.json; do
    [ -f "$file" ] || continue
    case "$file" in *.pr.json) continue ;; esac
    if ! jq -e . "$file" >/dev/null 2>&1; then
      printf 'greenlyt: état illisible ignoré : %s\n' "$file" >&2
      continue
    fi
    if jq -e --arg s "$1" '.status == $s' "$file" >/dev/null; then
      basename "$file" .json
    fi
  done
}

gl_running_runs() {
  gl_state_ids_with_status running
}

gl_state_get() {
  local file value
  file="$(gl_state_file "$1")"
  [ -f "$file" ] || gl_die "run introuvable : $1"
  value="$(jq -c "$2" "$file")"
  value="${value#\"}"
  printf '%s' "${value%\"}"
}

gl_state_update() {
  local run_id=$1 filter=$2 file tmp
  shift 2
  file="$(gl_state_file "$run_id")"
  [ -f "$file" ] || gl_die "run introuvable : $run_id"
  tmp="$(mktemp "$file.XXXXXX")"
  if jq "$@" "$filter" "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    gl_die "mise à jour de l'état impossible : $run_id"
  fi
}
