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

is_protected() {
  printf '%s\n' "$protected" | grep -qxF -- "$1"
}

deny() {
  printf 'greenlyt: %s blocked: "%s" is a protected branch. Work on a %s branch.\n' \
    "$1" "$2" "$(gl_config_get .branchPrefix)<slug>" >&2
  exit 2
}

branch_of() {
  git -C "$1" branch --show-current 2>/dev/null
}

check_push() {
  local dir=$1 branch positional=() arg ref
  shift
  branch="$(branch_of "$dir")"
  for arg in "$@"; do
    case "$arg" in
      --all|--mirror|--branches)
        [ -n "$protected" ] && deny "git push $arg" "$(printf '%s' "$protected" | head -n 1)" ;;
      -*) ;;
      *) positional+=("$arg") ;;
    esac
  done
  if [ "${#positional[@]}" -le 1 ]; then
    is_protected "$branch" && deny "git push" "$branch"
    return 0
  fi
  for ref in "${positional[@]:1}"; do
    ref="${ref#+}"
    ref="${ref##*:}"
    ref="${ref#refs/heads/}"
    [ "$ref" = "HEAD" ] && ref="$branch"
    is_protected "$ref" && deny "git push to $ref" "$ref"
  done
  return 0
}

check_segment() {
  local words=() sub dir=. branch
  # Quotes and subshell parentheses are stripped so that 'main', "main" and (git ...) are analysed like plain words.
  read -r -a words <<< "$(printf '%s' "$1" | tr -d "\"'()\`{}")"
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in
      command|env|exec|nohup|time|sudo|*=*) words=("${words[@]:1}") ;;
      bash|sh|zsh)
        [ "${words[1]:-}" = "-c" ] || [ "${words[1]:-}" = "-lc" ] || return 0
        check_segment "${words[*]:2}"
        return 0 ;;
      *) break ;;
    esac
  done
  [ "${#words[@]}" -gt 0 ] && [ "${words[0]}" = "git" ] || return 0
  words=("${words[@]:1}")
  while [ "${#words[@]}" -gt 0 ]; do
    case "${words[0]}" in
      -C) dir="${words[1]:-.}"; words=("${words[@]:2}") ;;
      -c) words=("${words[@]:2}") ;;
      -*) words=("${words[@]:1}") ;;
      *) break ;;
    esac
  done
  [ "${#words[@]}" -gt 0 ] || return 0
  sub="${words[0]}"
  branch="$(branch_of "$dir")"
  case "$sub" in
    commit|rebase)
      is_protected "$branch" && deny "git $sub" "$branch" ;;
    reset)
      case " ${words[*]} " in *" --hard "*) is_protected "$branch" && deny "git reset --hard" "$branch" ;; esac ;;
    push)
      check_push "$dir" "${words[@]:1}" ;;
  esac
  return 0
}

segments="$(printf '%s' "$command" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/[;|]/\n/g')"
while IFS= read -r segment; do
  check_segment "$segment"
done <<< "$segments"
exit 0
