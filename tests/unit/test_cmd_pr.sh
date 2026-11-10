#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

stubs="$(mktemp -d)"
calls="$stubs/calls.log"
cat > "$stubs/gh" <<STUB
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >> "$calls"
echo "https://github.com/acme/app/pull/42"
STUB
cat > "$stubs/az" <<STUB
#!/usr/bin/env bash
printf 'az %s\n' "\$*" >> "$calls"
echo '{"pullRequestId": 7, "repository": {"webUrl": "https://dev.azure.com/acme/app/_git/app"}}'
STUB
chmod +x "$stubs/gh" "$stubs/az"
export PATH="$stubs:$PATH"

setup() {
  local remote repo
  remote="$(mktemp -d)"
  git init -q --bare "$remote"
  repo="$(mk_repo)"
  git -C "$repo" remote add origin "$remote"
  write_config "$repo" "$1"
  mkdir -p "$repo/docs/greenlyt/specs"
  printf '# Export CSV des dossiers\n\nStatut : validée\n' > "$repo/docs/greenlyt/specs/export-csv.md"
  git -C "$repo" checkout -q -b greenlyt/export-csv
  git -C "$repo" add -A
  git -C "$repo" commit -q -m spec
  printf '%s %s' "$repo" "$remote"
}

body="$(mktemp)"
echo "Corps de la PR" > "$body"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"github"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
url="$("$GL_BIN" pr "$run_id" "$body")"
assert_eq "https://github.com/acme/app/pull/42" "$url" "URL GitHub affichée"
assert_eq "$(git rev-parse HEAD)" "$(git -C "$remote" rev-parse greenlyt/export-csv)" "branche poussée"
line="$(cat "$calls")"
assert_contains "pr create --draft" "$line" "PR GitHub en draft"
assert_contains "--base main" "$line" "base GitHub"
assert_contains "--head greenlyt/export-csv" "$line" "head GitHub"
assert_contains "--title Export CSV des dossiers" "$line" "titre tiré de la spec"
assert_contains "--body-file $body" "$line" "corps de la PR"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"azure-devops","baseBranch":"develop","organization":"https://dev.azure.com/acme","project":"app","repository":"app-api"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
url="$("$GL_BIN" pr "$run_id" "$body")"
assert_eq "https://dev.azure.com/acme/app/_git/app/pullrequest/7" "$url" "URL Azure DevOps affichée"
line="$(cat "$calls")"
assert_contains "repos pr create --draft true" "$line" "PR Azure en draft"
assert_contains "--target-branch develop" "$line" "base Azure"
assert_contains "--source-branch greenlyt/export-csv" "$line" "source Azure"
assert_contains "--organization https://dev.azure.com/acme --project app --repository app-api" "$line" "coordonnées Azure"
assert_contains "--description @$body" "$line" "corps Azure"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"github"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
GREENLYT_FORGE_DRY_RUN=1 "$GL_BIN" pr "$run_id" "$body" >/dev/null
assert_eq "" "$(cat "$calls")" "dry-run : aucune forge appelée"
request=".greenlyt/state/$run_id.pr.json"
assert_eq github "$(jq -r .forge "$request")" "dry-run : forge"
assert_eq main "$(jq -r .base "$request")" "dry-run : base"
assert_eq greenlyt/export-csv "$(jq -r .head "$request")" "dry-run : head"
assert_eq "Export CSV des dossiers" "$(jq -r .title "$request")" "dry-run : titre"
assert_eq "Corps de la PR" "$(jq -r .body "$request")" "dry-run : corps"
assert_eq true "$(jq -r .draft "$request")" "dry-run : draft"
assert_eq "$(git rev-parse HEAD)" "$(git -C "$remote" rev-parse greenlyt/export-csv)" "dry-run : branche poussée"

write_config "$repo" '{"testCommand":"exit 0","forge":{"type":"gitlab"}}'
assert_exit 1 "$GL_BIN" pr "$run_id" "$body"

finish
