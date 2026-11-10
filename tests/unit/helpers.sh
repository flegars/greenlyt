#!/usr/bin/env bash

GL_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GL_BIN="$GL_PLUGIN_ROOT/bin/greenlyt"
GL_FAILURES=0

mk_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email test@greenlyt.local
  git -C "$dir" config user.name greenlyt-test
  git -C "$dir" config commit.gpgsign false
  echo init > "$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -q -m init
  (cd "$dir" && pwd -P)
}

write_config() {
  mkdir -p "$1/.greenlyt"
  printf '%s\n' "$2" > "$1/.greenlyt/config.json"
}

_fail() {
  GL_FAILURES=$((GL_FAILURES + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

assert_eq() {
  [ "$1" = "$2" ] || _fail "$3 (expected: [$1], got: [$2])"
}

assert_exit() {
  local expected=$1 rc=0
  shift
  "$@" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq "$expected" ] || _fail "exit code $rc instead of $expected: $*"
}

assert_contains() {
  case "$2" in
    *"$1"*) ;;
    *) _fail "$3 ([$1] not found in [$2])" ;;
  esac
}

finish() {
  [ "$GL_FAILURES" -eq 0 ]
}
