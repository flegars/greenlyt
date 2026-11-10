#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 0"}'
run_id="$("$GL_BIN" state init verdict)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
tmp="$(mktemp -d)"

printf '{"approved":true,"objections":[],"specIssues":[]}' > "$tmp/sans-deviations.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/sans-deviations.json"
printf '{"approved":"oui","objections":[],"deviations":[],"specIssues":[]}' > "$tmp/approved-texte.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/approved-texte.json"
printf 'pas du json' > "$tmp/invalide.json"
assert_exit 1 "$GL_BIN" verdict "$run_id" "$tmp/invalide.json"

printf '{"approved":false,"objections":[{"ref":"AC-1","detail":"x"}],"deviations":[{"description":"d","files":[],"rationale":"r"}],"specIssues":[]}' > "$tmp/refus.json"
"$GL_BIN" test "$run_id" >/dev/null
assert_exit 0 "$GL_BIN" verdict "$run_id" "$tmp/refus.json"
assert_eq false "$("$GL_BIN" state get "$run_id" .verdict.approved)" "verdict enregistré"
assert_eq '{"attempt":1,"exitCode":0,"approved":false,"objections":1,"deviations":1}' \
  "$("$GL_BIN" state get "$run_id" '.history[0]')" "historique du tour"
assert_eq retry "$("$GL_BIN" decide "$run_id")" "refus avec budget : retry"

printf '{"approved":true,"objections":[],"deviations":[],"specIssues":[]}' > "$tmp/ok.json"
"$GL_BIN" verdict "$run_id" "$tmp/ok.json"
assert_eq success "$("$GL_BIN" decide "$run_id")" "vert et approuvé : success"

write_config "$repo" '{"maxAttempts":2,"testCommand":"exit 1"}'
"$GL_BIN" test "$run_id" >/dev/null
assert_eq retry "$("$GL_BIN" decide "$run_id")" "approuvé mais rouge : retry"

"$GL_BIN" state next-attempt "$run_id" >/dev/null
assert_eq exhausted "$("$GL_BIN" decide "$run_id")" "rouge sans budget : exhausted"

git checkout -q -b greenlyt/verdict
echo change > fichier.txt
mkdir -p docs/greenlyt/runs && echo rapport > docs/greenlyt/runs/echec.md
"$GL_BIN" test "$run_id" >/dev/null || true
assert_exit 0 "$GL_BIN" commit-tour "$run_id"
assert_eq "chore(greenlyt): tour 2" "$(git log -1 --format=%s)" "message du commit de tour"
assert_eq "" "$(git ls-files .greenlyt/state)" "l'état n'est jamais commité"
assert_eq "" "$(git status --porcelain -- fichier.txt)" "les changements sont commités"
assert_eq "" "$(git ls-files docs/greenlyt/runs)" "les rapports ne partent pas dans les commits de tour"
assert_exit 0 "$GL_BIN" commit-tour "$run_id"

finish
