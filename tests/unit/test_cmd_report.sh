#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"
write_config "$repo" '{"testCommand":"echo 1 failure; exit 1","maxAttempts":2}'
run_id="$("$GL_BIN" state init export-csv)"
"$GL_BIN" state next-attempt "$run_id" >/dev/null
"$GL_BIN" test "$run_id" >/dev/null || true
verdict="$(mktemp)"
printf '%s' '{"approved":false,"objections":[{"ref":"AC-2","detail":"tri non testé"}],"deviations":[{"description":"ajout d un en-tête","files":["src/Export.php"],"rationale":"lisibilité"}],"specIssues":[{"question":"Quel séparateur ?","why":"AC-1 et AC-3 se contredisent"}]}' > "$verdict"
"$GL_BIN" verdict "$run_id" "$verdict"

path="$("$GL_BIN" report "$run_id" failure)"
assert_eq "docs/greenlyt/runs/$run_id.md" "$path" "chemin du rapport"
report="$(cat "$path")"
assert_contains "Questions ouvertes" "$report" "section questions ouvertes"
assert_contains "Quel séparateur ?" "$report" "question listée"
assert_contains "AC-1 et AC-3 se contredisent" "$report" "justification listée"
assert_contains "AC-2" "$report" "objection listée"
assert_contains "1 failure" "$report" "sortie des tests"
assert_contains "$run_id" "$report" "run-id"
assert_eq "" "$(grep -o '{{[a-zA-Z]*}}' "$path")" "aucun gabarit non substitué"

printf '%s' '{"approved":true,"objections":[],"deviations":[{"description":"ajout d un en-tête","files":["src/Export.php"],"rationale":"lisibilité"}],"specIssues":[]}' > "$verdict"
"$GL_BIN" verdict "$run_id" "$verdict"
report="$(cat "$("$GL_BIN" report "$run_id" success)")"
assert_contains "ajout d un en-tête" "$report" "libertés listées"
assert_contains "src/Export.php" "$report" "fichiers de la liberté"
assert_eq "" "$(printf '%s' "$report" | grep -o '{{[a-zA-Z]*}}')" "aucun gabarit non substitué (succès)"

assert_exit 1 "$GL_BIN" report "$run_id" bof

acceptance="$(mktemp)"
printf '| AC-1 | tests/ExportTest.php |\n' > "$acceptance"
body_path="$("$GL_BIN" report "$run_id" pr "$acceptance")"
assert_eq ".greenlyt/state/$run_id.pr-body.md" "$body_path" "corps de PR hors docs"
body="$(cat "$body_path")"
assert_contains "| AC-1 | tests/ExportTest.php |" "$body" "tableau AC → preuve"
assert_contains "ajout d un en-tête" "$body" "libertés dans la PR"
assert_eq "" "$(printf '%s' "$body" | grep -o '{{[a-zA-Z]*}}')" "aucun gabarit non substitué (PR)"
assert_exit 1 "$GL_BIN" report "$run_id" pr

finish
