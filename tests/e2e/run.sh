#!/usr/bin/env bash
# Usage: tests/e2e/run.sh <js|php-phpunit> <success|budget>
# Makes real model calls: run manually or nightly, never on every push.
set -euo pipefail

fixture=${1:?fixture expected (js|php-phpunit)}
scenario=${2:?scenario expected (success|budget)}
root="$(cd "$(dirname "$0")/../.." && pwd)"
[ -d "$root/tests/fixtures/$fixture" ] || { echo "unknown fixture: $fixture" >&2; exit 2; }
[ -f "$root/tests/e2e/scenario_$scenario.sh" ] || { echo "unknown scenario: $scenario" >&2; exit 2; }

prepare() {
  local work remote
  work="$(mktemp -d)"
  remote="$(mktemp -d)"
  cp -R "$root/tests/fixtures/$fixture/." "$work"
  git init -q --bare "$remote"
  (
    cd "$work"
    if [ "$scenario" = budget ]; then
      jq '.maxAttempts = 2' .greenlyt/config.json > .greenlyt/config.tmp && mv .greenlyt/config.tmp .greenlyt/config.json
    fi
    [ -f composer.json ] && composer install -q --no-interaction
    git init -q -b main
    git config user.email e2e@greenlyt.local
    git config user.name greenlyt-e2e
    git add -A
    git commit -q -m "fixture"
    git remote add origin "$remote"
    git push -q origin main
    mkdir -p docs/greenlyt/specs
    cp "$root/tests/e2e/specs/$scenario.md" "docs/greenlyt/specs/$scenario.md"
  )
  printf '%s %s' "$work" "$remote"
}

attempt_once() {
  local work remote
  read -r work remote <<< "$(prepare)"
  echo "e2e: $fixture/$scenario in $work (remote $remote)"
  (
    cd "$work"
    GREENLYT_HOME="$(mktemp -d)" GREENLYT_FORGE_DRY_RUN=1 claude -p "/greenlyt:run $scenario" \
      --plugin-dir "$root" \
      --dangerously-skip-permissions \
      --output-format text > "$work/.e2e-claude.log" 2>&1 || true
  )
  bash "$root/tests/e2e/scenario_$scenario.sh" "$work" "$remote"
}

if attempt_once; then
  echo "e2e: $fixture/$scenario OK"
  exit 0
fi

# The model is not deterministic: the success scenario gets a second try.
if [ "$scenario" = success ]; then
  echo "e2e: first try failed, retrying" >&2
  attempt_once && { echo "e2e: $fixture/$scenario OK (2nd try)"; exit 0; }
fi
echo "e2e: $fixture/$scenario FAILED" >&2
exit 1
