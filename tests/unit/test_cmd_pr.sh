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
  printf '# CSV export of cases\n\nStatus: approved\n' > "$repo/docs/greenlyt/specs/export-csv.md"
  git -C "$repo" checkout -q -b feat/export-csv
  git -C "$repo" add -A
  git -C "$repo" commit -q -m spec
  printf '%s %s' "$repo" "$remote"
}

body="$(mktemp)"
echo "Pull request body" > "$body"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"github"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
url="$("$GL_BIN" pr "$run_id" "$body")"
assert_eq "https://github.com/acme/app/pull/42" "$url" "GitHub URL printed"
assert_eq "$(git rev-parse HEAD)" "$(git -C "$remote" rev-parse feat/export-csv)" "branch pushed"
line="$(cat "$calls")"
assert_contains "pr create --draft" "$line" "GitHub draft pull request"
assert_contains "--base main" "$line" "GitHub base"
assert_contains "--head feat/export-csv" "$line" "GitHub head"
assert_contains "--title CSV export of cases" "$line" "title taken from the spec"
assert_contains "--body-file $body" "$line" "pull request body"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"azure-devops","baseBranch":"develop","organization":"https://dev.azure.com/acme","project":"app","repository":"app-api"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
url="$("$GL_BIN" pr "$run_id" "$body")"
assert_eq "https://dev.azure.com/acme/app/_git/app/pullrequest/7" "$url" "Azure DevOps URL printed"
line="$(cat "$calls")"
assert_contains "repos pr create --draft true" "$line" "Azure draft pull request"
assert_contains "--target-branch develop" "$line" "Azure base"
assert_contains "--source-branch feat/export-csv" "$line" "Azure source"
assert_contains "--organization https://dev.azure.com/acme --project app --repository app-api" "$line" "Azure coordinates"
assert_contains "--description @$body" "$line" "Azure body"

read -r repo remote <<< "$(setup '{"testCommand":"exit 0","forge":{"type":"github"}}')"
cd "$repo"
run_id="$("$GL_BIN" state init export-csv)"
: > "$calls"
GREENLYT_FORGE_DRY_RUN=1 "$GL_BIN" pr "$run_id" "$body" >/dev/null
assert_eq "" "$(cat "$calls")" "dry-run: no forge called"
request=".greenlyt/state/$run_id.pr.json"
assert_eq github "$(jq -r .forge "$request")" "dry-run: forge"
assert_eq main "$(jq -r .base "$request")" "dry-run: base"
assert_eq feat/export-csv "$(jq -r .head "$request")" "dry-run: head"
assert_eq "CSV export of cases" "$(jq -r .title "$request")" "dry-run: title"
assert_eq "Pull request body" "$(jq -r .body "$request")" "dry-run: body"
assert_eq true "$(jq -r .draft "$request")" "dry-run: draft"
assert_eq "$(git rev-parse HEAD)" "$(git -C "$remote" rev-parse feat/export-csv)" "dry-run: branch pushed"

write_config "$repo" '{"testCommand":"exit 0","forge":{"type":"gitlab"}}'
assert_exit 1 "$GL_BIN" pr "$run_id" "$body"

finish
