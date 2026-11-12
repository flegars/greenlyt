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
write_config "$repo" '{"testCommand":"exit 0","reviewers":["spec","performance"]}'
assert_exit 10 "$GL_BIN" preflight "$SPEC"
assert_contains performance "$("$GL_BIN" preflight "$SPEC" 2>&1)" "an unknown reviewer is named"
write_config "$repo" '{"testCommand":"exit 0","reviewers":null}'
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
assert_exit 1 git rev-parse --verify --quiet feat/export-csv
write_config "$repo" '{"testCommand":"exit 0"}'

git branch feat/export-csv
assert_exit 16 "$GL_BIN" preflight "$SPEC"
git branch -q -D feat/export-csv

run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq feat/export-csv "$(git branch --show-current)" "protected starting branch: work branch created"
assert_eq feat/export-csv "$("$GL_BIN" state get "$run_id" .branch)" "protected starting branch: work branch recorded"
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
assert_eq feat/export-csv "$(git branch --show-current)" "unpushed config: work branch created"
assert_eq .greenlyt/config.json "$(git ls-files .greenlyt/config.json)" "unpushed config: config tracked on the work branch"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "unpushed config: run initialized"

repo="$(mk_repo)"
cd "$repo"
git checkout -q -b develop
write_config "$repo" '{"testCommand":"exit 0"}'
printf '.greenlyt/state/\n' > .gitignore
git add -A && git commit -q -m "config only on develop"
mkdir -p docs/greenlyt/specs
printf '# Export\n\nStatus: approved\n' > "$SPEC"
assert_exit 17 "$GL_BIN" preflight "$SPEC"
assert_eq develop "$(git branch --show-current)" "config missing on base: back on the starting branch"
assert_exit 1 git rev-parse --verify --quiet feat/export-csv

repo="$(setup_repo)"
worktree="$(mktemp -d)/wt"
git -C "$repo" worktree add -q -b orca/afiesca "$worktree"
cd "$worktree"
mkdir -p docs/greenlyt/specs
cp "$repo/$SPEC" "$SPEC"
start="$(git rev-parse HEAD)"
run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq orca/afiesca "$(git branch --show-current)" "worktree branch: the run stays on the current branch"
assert_eq orca/afiesca "$("$GL_BIN" state get "$run_id" .branch)" "worktree branch: current branch recorded"
assert_eq "$start" "$(git rev-parse HEAD~1)" "worktree branch: spec committed on top of the current branch"
assert_exit 1 git rev-parse --verify --quiet feat/export-csv
assert_eq main "$(git -C "$repo" branch --show-current)" "worktree branch: the main clone is left alone"
assert_eq "$start" "$(git -C "$repo" rev-parse HEAD)" "worktree branch: the main clone has no new commit"
assert_exit 0 test -f "$worktree/.greenlyt/state/$run_id.json"

repo="$(mk_repo)"
printf '.greenlyt/\n' > "$repo/.gitignore"
git -C "$repo" add -A && git -C "$repo" commit -q -m "greenlyt ignored"
worktree="$(mktemp -d)/wt"
git -C "$repo" worktree add -q -b orca/ignored "$worktree"
cd "$worktree"
write_config "$worktree" '{"testCommand":"exit 0"}'
mkdir -p docs/greenlyt/specs
printf '# Export\n\nStatus: approved\n' > "$SPEC"
run_id="$("$GL_BIN" preflight "$SPEC")"
assert_eq orca/ignored "$(git branch --show-current)" "untracked config: the run stays on the current branch"
assert_eq running "$("$GL_BIN" state get "$run_id" .status)" "untracked config: run initialized"

repo="$(setup_repo)"
cd "$repo"
git checkout -q -b feature
start="$(git rev-parse HEAD)"
write_config "$repo" '{"testCommand":"exit 1"}'
assert_exit 15 "$GL_BIN" preflight "$SPEC"
assert_eq feature "$(git branch --show-current)" "current branch, failing tests: still on the branch"
assert_eq "$start" "$(git rev-parse HEAD)" "current branch, failing tests: nothing committed"
assert_exit 0 git diff --cached --quiet

finish
