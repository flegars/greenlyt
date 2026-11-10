#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

setup_repo() {
  local repo
  repo="$(mk_repo)"
  write_config "$repo" '{"testCommand":"exit 0"}'
  printf '.greenlyt/state/\n' > "$repo/.gitignore"
  git -C "$repo" add -A && git -C "$repo" commit -q -m config
  mkdir -p "$repo/docs/greenlyt/specs"
  printf '# Export CSV\n\nStatus: approved\n\n## Acceptance criteria\n- AC-1 : ...\n' > "$repo/docs/greenlyt/specs/export-csv.md"
  printf '%s' "$repo"
}

SPEC=docs/greenlyt/specs/export-csv.md

repo="$(mk_repo)"
cd "$repo"
assert_exit 10 "$GL_BIN" preflight "$SPEC"

repo="$(setup_repo)"
cd "$repo"
touch .greenlyt/STOP
assert_exit 11 "$GL_BIN" preflight "$SPEC"
rm .greenlyt/STOP

write_config "$repo" '{}'
assert_exit 10 "$GL_BIN" preflight "$SPEC"
write_config "$repo" '{"testCommand":"exit 0"}'

sed -i.bak 's/approved/draft/' "$SPEC" && rm "$SPEC.bak"
assert_exit 12 "$GL_BIN" preflight "$SPEC"
assert_exit 12 "$GL_BIN" preflight docs/greenlyt/specs/missing.md
sed -i.bak 's/draft/approved/' "$SPEC" && rm "$SPEC.bak"

echo dirty > README.md
assert_exit 13 "$GL_BIN" preflight "$SPEC"
git checkout -q README.md

"$GL_BIN" state init other >/dev/null
assert_exit 14 "$GL_BIN" preflight "$SPEC"
rm -rf .greenlyt/state

write_config "$repo" '{"testCommand":"exit 1"}'
assert_exit 15 "$GL_BIN" preflight "$SPEC"
assert_eq main "$(git branch --show-current)" "failing tests: back on the starting branch"
assert_exit 1 git rev-parse --verify --quiet greenlyt/export-csv
write_config "$repo" '{"testCommand":"exit 0"}'

git branch greenlyt/export-csv
assert_exit 16 "$GL_BIN" preflight "$SPEC"
git branch -q -D greenlyt/export-csv

git checkout -q -b other-branch
run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq greenlyt/export-csv "$(git branch --show-current)" "work branch created"
assert_eq "$(git rev-parse main)" "$(git rev-parse HEAD~1)" "branch starts from baseBranch"
assert_eq "docs(greenlyt): spec export-csv" "$(git log -1 --format=%s)" "spec committed"
assert_eq "$SPEC" "$(git show --name-only --format= HEAD)" "the commit only contains the spec"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "run initialized"
assert_contains export-csv "$run_id" "run-id contains the slug"

remote="$(mktemp -d)"
git init -q --bare "$remote"
repo="$(setup_repo)"
cd "$repo"
git remote add origin "$remote"
git push -q origin main
git commit -q --allow-empty -m "unpushed local commit"
run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq "$(git rev-parse main)" "$(git rev-parse HEAD~1)" "branch starts from the local base branch, unpushed commits included"

remote="$(mktemp -d)"
git init -q --bare "$remote"
repo="$(mk_repo)"
cd "$repo"
git remote add origin "$remote"
git push -q origin main
write_config "$repo" '{"testCommand":"exit 0"}'
printf '.greenlyt/state/\n' > .gitignore
git add -A && git commit -q -m "config committed but not pushed"
mkdir -p docs/greenlyt/specs
printf '# Export\n\nStatus: approved\n' > "$SPEC"
run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq greenlyt/export-csv "$(git branch --show-current)" "unpushed config: work branch created"
assert_eq .greenlyt/config.json "$(git ls-files .greenlyt/config.json)" "unpushed config: config tracked on the work branch"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "unpushed config: run initialized"

repo="$(mk_repo)"
cd "$repo"
git checkout -q -b feature
write_config "$repo" '{"testCommand":"exit 0"}'
printf '.greenlyt/state/\n' > .gitignore
git add -A && git commit -q -m "config only on feature"
mkdir -p docs/greenlyt/specs
printf '# Export\n\nStatus: approved\n' > "$SPEC"
assert_exit 17 "$GL_BIN" preflight "$SPEC"
assert_eq feature "$(git branch --show-current)" "config missing on base: back on the starting branch"
assert_exit 1 git rev-parse --verify --quiet greenlyt/export-csv

finish
