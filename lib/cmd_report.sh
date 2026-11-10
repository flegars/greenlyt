#!/usr/bin/env bash

source "$GL_LIB/state.sh"

GL_TEMPLATES="$GL_LIB/../skills/run/templates"

gl_render() {
  local template=$1 run_id=$2 extra=${3:-'{}'}
  jq -n -r --rawfile tpl "$template" --slurpfile s "$(gl_state_file "$run_id")" \
    --arg date "$(date '+%Y-%m-%d %H:%M')" --argjson extra "$extra" '
    def bullets(f): if length == 0 then "_Aucune._" else map("- " + f) | join("\n") end;
    $s[0] as $st
    | ($st.verdict // {objections: [], deviations: [], specIssues: []}) as $v
    | {
        runId: $st.runId, slug: $st.slug, spec: $st.spec, branch: $st.branch,
        baseBranch: $st.baseBranch, attempt: ($st.attempt | tostring),
        maxAttempts: ($st.maxAttempts | tostring), date: $date,
        exitCode: ($st.tests.exitCode | tostring), testsTail: $st.tests.tail,
        history: (if ($st.history | length) == 0 then "_Aucun tour._" else
          (["| Tour | Tests | Relecteur | Objections | Libertés |", "|---|---|---|---|---|"]
           + ($st.history | map("| \(.attempt) | \(if .exitCode == 0 then "verts" else "rouges (\(.exitCode))" end) | \(if .approved then "approuvé" else "refusé" end) | \(.objections) | \(.deviations) |"))
          | join("\n")) end),
        objections: ($v.objections | bullets("**\(.ref)** : \(.detail)")),
        deviations: ($v.deviations | bullets("\(.description) — fichiers : \(.files | join(", ")) — justification : \(.rationale)")),
        specIssues: ($v.specIssues | bullets("\(.question) _(\(.why))_"))
      } + $extra
    | to_entries
    | reduce .[] as $e ($tpl; split("{{" + $e.key + "}}") | join($e.value))'
}

cmd_report() {
  [ $# -ge 2 ] || gl_die "usage: greenlyt report <run-id> success|failure|pr [fichier-ac]"
  local run_id=$1 kind=$2 dir path
  case "$kind" in
    success|failure)
      dir="$(gl_config_get .docsDir)/runs"
      path="$dir/$run_id.md"
      mkdir -p "$(gl_root)/$dir"
      gl_render "$GL_TEMPLATES/report-$kind.md" "$run_id" > "$(gl_root)/$path"
      ;;
    pr)
      [ $# -eq 3 ] && [ -f "$3" ] || gl_die "usage: greenlyt report <run-id> pr <fichier-ac>"
      path=".greenlyt/state/$run_id.pr-body.md"
      gl_render "$GL_TEMPLATES/pr.md" "$run_id" "$(jq -n --rawfile a "$3" '{acceptance: ($a | rtrimstr("\n"))}')" \
        > "$(gl_root)/$path"
      ;;
    *) gl_die "type de rapport inconnu : $kind" ;;
  esac
  printf '%s\n' "$path"
}
