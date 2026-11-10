#!/usr/bin/env bash

source "$GL_LIB/state.sh"

cmd_pr() {
  [ $# -eq 2 ] || gl_die "usage: greenlyt pr <run-id> <body-file>"
  local run_id=$1 body=$2 forge remote base branch title
  cd "$(gl_root)"
  forge="$(gl_config_get .forge.type)"
  case "$forge" in
    github|azure-devops) ;;
    *) gl_die "unsupported forge: $forge (expected: github, azure-devops)" ;;
  esac
  [ -f "$body" ] || gl_die "PR body not found: $body"
  remote="$(gl_config_get .forge.remote)"
  base="$(gl_state_get "$run_id" .baseBranch)"
  branch="$(gl_state_get "$run_id" .branch)"
  title="$(grep -m 1 '^# ' "$(gl_state_get "$run_id" .spec)" | sed 's/^# //')"
  [ -n "$title" ] || title="greenlyt: $(gl_state_get "$run_id" .slug)"

  git push -q -u "$remote" "$branch"

  if [ "${GREENLYT_FORGE_DRY_RUN:-}" = "1" ]; then
    jq -n --arg forge "$forge" --arg base "$base" --arg head "$branch" --arg title "$title" --rawfile body "$body" \
      '{forge: $forge, base: $base, head: $head, title: $title, body: $body | rtrimstr("\n"), draft: true}' \
      > "$(gl_state_dir)/$run_id.pr.json"
    printf 'dry-run: %s\n' "$(gl_state_dir)/$run_id.pr.json"
    return 0
  fi

  case "$forge" in
    github)
      gh pr create --draft --base "$base" --head "$branch" --title "$title" --body-file "$body"
      ;;
    azure-devops)
      az repos pr create --draft true \
        --organization "$(gl_config_get .forge.organization)" \
        --project "$(gl_config_get .forge.project)" \
        --repository "$(gl_config_get .forge.repository)" \
        --source-branch "$branch" --target-branch "$base" \
        --title "$title" --description "@$body" --output json \
        | jq -r '"\(.repository.webUrl)/pullrequest/\(.pullRequestId)"'
      ;;
  esac
}
