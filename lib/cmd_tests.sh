#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_tests() {
  [ $# -eq 2 ] || gl_die "usage: greenlyt tests <lock|check> <run-id>"
  cd "$(gl_root)"
  case "$1" in
    lock) tests_lock "$2" ;;
    check) tests_check "$2" ;;
    *) gl_die "unknown tests subcommand: $1" ;;
  esac
}

# Everything the test writer changed since the last commit is a test file: it may write nothing else.
tests_changed_files() {
  { git diff --name-only HEAD; git ls-files --others --exclude-standard; } \
    | grep -v -e '^\.greenlyt/' -e "^$(gl_config_get .docsDir)/" | sort -u
}

tests_lock() {
  local file locks='{}'
  while IFS= read -r file; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    locks="$(jq -c --arg f "$file" --arg h "$(git hash-object "$file")" '.[$f] = $h' <<< "$locks")"
  done <<< "$(tests_changed_files)"
  gl_state_update "$1" '.lockedTests = ((.lockedTests // {}) + $locks)' --argjson locks "$locks"
  jq -r 'keys[]' <<< "$locks"
}

tests_check() {
  local file hash problems=()
  while IFS=$'\t' read -r file hash; do
    [ -n "$file" ] || continue
    if [ ! -f "$file" ]; then
      problems+=("locked test deleted: $file")
    elif [ "$(git hash-object "$file")" != "$hash" ]; then
      problems+=("locked test modified: $file")
    fi
  done <<< "$(gl_state_get "$1" '.lockedTests // {} | to_entries | map("\(.key)\t\(.value)") | join("\n")')"
  # The verdict is always written so that the loop can pass it to `greenlyt verdict` unconditionally.
  printf '%s\n' "${problems[@]+"${problems[@]}"}" \
    | jq -R -s '{reviewer: "locked-tests",
        objections: (split("\n") | map(select(length > 0)) | map({ref: "locked-tests", severity: "critical",
          detail: (. + ": the developer may not change tests written by the test writer")})),
        deviations: [], specIssues: []}' > "$(gl_state_dir)/$1.verdict.locked-tests"
  [ "${#problems[@]}" -eq 0 ] && return 0
  printf 'greenlyt: %s\n' "${problems[@]}" >&2
  return 1
}
