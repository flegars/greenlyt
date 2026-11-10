#!/usr/bin/env bash

source "$GL_LIB/state.sh"

GL_TEMPLATES="$GL_LIB/../skills/run/templates"

gl_render() {
  local template=$1 run_id=$2 extra=${3:-'{}'}
  jq -n -r --rawfile tpl "$template" --slurpfile s "$(gl_state_file "$run_id")" \
    --arg date "$(date '+%Y-%m-%d %H:%M')" --argjson extra "$extra" \
    --argjson reviewers "$(gl_config_get .reviewers)" --arg refactorEnabled "$(gl_config_get .refactor)" '
    def bullets(f): if length == 0 then "_None._" else map("- " + f) | join("\n") end;
    def objection: "**\(.ref)** (\(.severity), \(.reviewer)): \(.detail)";
    $s[0] as $st
    | ($st.verdict // {objections: [], deviations: [], specIssues: []}) as $v
    | {
        runId: $st.runId, slug: $st.slug, spec: $st.spec, branch: $st.branch,
        baseBranch: $st.baseBranch, attempt: ($st.attempt | tostring),
        maxAttempts: ($st.maxAttempts | tostring), date: $date,
        exitCode: ($st.tests.exitCode | tostring), testsTail: $st.tests.tail,
        history: (if ($st.history | length) == 0 then "_No rounds._" else
          (["| Round | Tests | " + ($reviewers | join(" | ")) + " | Minor | Deviations |",
            "|---|---|" + ($reviewers | map("---|") | join("")) + "---|---|"]
           + ($st.history | map(. as $h
               | "| \($h.attempt) | \(if $h.exitCode == 0 then "green" else "red (\($h.exitCode))" end) | "
                 + ($reviewers | map(($h.blocking[.] // "-") | tostring) | join(" | "))
                 + " | \($h.minor) | \($h.deviations) |"))
          | join("\n")) end),
        objections: ([$v.objections[] | select(.severity != "minor")] | bullets(objection)),
        remarks: ([$v.objections[] | select(.severity == "minor")] | bullets(objection)),
        deviations: ($v.deviations | bullets("\(.description) — files: \(.files | join(", ")) — rationale: \(.rationale)")),
        specIssues: ($v.specIssues | bullets("\(.question) _(\(.why))_")),
        tddWarnings: (($st.tddWarnings // []) | bullets(.)),
        refactoring: (if $refactorEnabled != "true" then "Disabled in the config."
          elif $st.refactor == null then "Not run."
          elif $st.refactor.status == "applied" then "Applied after the green round, tests and reviews still green."
          elif $st.refactor.status == "reverted" then "Attempted, then reverted to the green commit `\($st.refactor.greenCommit[0:7])`: \($st.refactor.reason // "it broke tests or reviews")."
          else "In progress." end)
      } + $extra
    | to_entries
    | reduce .[] as $e ($tpl; split("{{" + $e.key + "}}") | join($e.value))'
}

cmd_report() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt report <run-id> success|failure|pr [acceptance-file]"
  local run_id=$1 kind=$2 dir path
  case "$kind" in
    success|failure)
      dir="$(gl_config_get .docsDir)/runs"
      path="$dir/$run_id.md"
      mkdir -p "$(gl_root)/$dir"
      gl_render "$GL_TEMPLATES/report-$kind.md" "$run_id" > "$(gl_root)/$path"
      ;;
    pr)
      [ $# -eq 3 ] && [ -f "$3" ] || gl_die "usage: greenlyt report <run-id> pr <acceptance-file>"
      path=".greenlyt/state/$run_id.pr-body.md"
      gl_render "$GL_TEMPLATES/pr.md" "$run_id" "$(jq -n --rawfile a "$3" '{acceptance: ($a | rtrimstr("\n"))}')" \
        > "$(gl_root)/$path"
      ;;
    *) gl_die "unknown report type: $kind" ;;
  esac
  printf '%s\n' "$path"
}
