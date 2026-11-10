#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_tests() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt tests lock <run-id> <test-file>... | greenlyt tests check <run-id>"
  local sub=$1
  shift
  cd "$(gl_root)"
  case "$sub" in
    lock) tests_lock "$@" ;;
    check) tests_check "$1" ;;
    *) gl_die "unknown tests subcommand: $sub" ;;
  esac
}

tests_lock() {
  local run_id=$1 file locks='{}'
  shift
  [ $# -ge 1 ] || gl_die "usage: greenlyt tests lock <run-id> <test-file>..."
  for file in "$@"; do
    file="${file#./}"
    [ -f "$file" ] || gl_die "cannot lock a missing file: $file"
    case "$file" in .greenlyt/*) gl_die "cannot lock greenlyt's own files: $file" ;; esac
    locks="$(jq -c --arg f "$file" --arg h "$(git hash-object "$file")" '.[$f] = $h' <<< "$locks")"
  done
  # Existing locks win: re-locking a file never accepts a new version of it.
  gl_state_update "$run_id" '.lockedTests = ($locks + (.lockedTests // {}))' --argjson locks "$locks"
}

tests_check() {
  local file hash config_hash problems=()
  while IFS=$'\t' read -r file hash; do
    [ -n "$file" ] || continue
    if [ ! -f "$file" ]; then
      problems+=("locked test deleted: $file")
    elif [ "$(git hash-object "$file")" != "$hash" ]; then
      problems+=("locked test modified: $file")
    fi
  done <<< "$(gl_state_get "$1" '.lockedTests // {} | to_entries | map("\(.key)\t\(.value)") | join("\n")')"
  config_hash="$(gl_state_get "$1" .configHash)"
  if [ -n "$config_hash" ] && [ "$(git hash-object .greenlyt/config.json 2>/dev/null)" != "$config_hash" ]; then
    problems+=("greenlyt config modified during the run: .greenlyt/config.json")
  fi
  # The verdict is always written so that `greenlyt verdict` can pick it up unconditionally.
  printf '%s\n' "${problems[@]+"${problems[@]}"}" \
    | jq -R -s '{reviewer: "locked-tests",
        objections: (split("\n") | map(select(length > 0)) | map({ref: "locked-tests", severity: "critical",
          detail: (. + ": the developer may not change locked tests or the greenlyt config")})),
        deviations: [], specIssues: []}' > "$(gl_state_dir)/$1.verdict.locked-tests"
  [ "${#problems[@]}" -eq 0 ] && return 0
  printf 'greenlyt: %s\n' "${problems[@]}" >&2
  return 1
}
