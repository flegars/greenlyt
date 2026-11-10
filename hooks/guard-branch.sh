#!/usr/bin/env bash
set -u

GL_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$GL_LIB/common.sh"

input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
command="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"

[ -n "$command" ] || exit 0
[ -n "$cwd" ] && cd "$cwd" 2>/dev/null || exit 0
gl_has_config || exit 0

protected="$(gl_config_get .protectedBranches '[]' | jq -r '.[]')"
current="$(git branch --show-current 2>/dev/null)"

is_protected() {
  printf '%s\n' "$protected" | grep -qxF -- "$1"
}

deny() {
  printf 'greenlyt: %s blocked: "%s" is a protected branch. Work on a %s branch.\n' \
    "$1" "$2" "$(gl_config_get .branchPrefix)<slug>" >&2
  exit 2
}

check_push() {
  local positional=() arg ref
  for arg in "$@"; do
    case "$arg" in -*) ;; *) positional+=("$arg") ;; esac
  done
  if [ "${#positional[@]}" -le 1 ]; then
    is_protected "$current" && deny "git push" "$current"
    return 0
  fi
  for ref in "${positional[@]:1}"; do
    ref="${ref#+}"
    ref="${ref##*:}"
    ref="${ref#refs/heads/}"
    is_protected "$ref" && deny "git push to $ref" "$ref"
  done
  return 0
}

check_segment() {
  local words=() sub
  read -r -a words <<< "$1"
  [ "${#words[@]}" -gt 0 ] && [ "${words[0]}" = "git" ] || return 0
  words=("${words[@]:1}")
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in
      -C|-c) words=("${words[@]:2}") ;;
      -*) words=("${words[@]:1}") ;;
      *) break ;;
    esac
  done
  [ "${#words[@]}" -gt 0 ] || return 0
  sub="${words[0]}"
  case "$sub" in
    commit|rebase)
      is_protected "$current" && deny "git $sub" "$current" ;;
    reset)
      case " ${words[*]} " in *" --hard "*) is_protected "$current" && deny "git reset --hard" "$current" ;; esac ;;
    push)
      check_push "${words[@]:1}" ;;
  esac
  return 0
}

segments="$(printf '%s' "$command" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g')"
while IFS= read -r segment; do
  check_segment "$segment"
done <<< "$segments"
exit 0
