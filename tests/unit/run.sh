#!/usr/bin/env bash
set -u

dir="$(cd "$(dirname "$0")" && pwd)"
failed=0
for t in "$dir"/test_*.sh; do
  if (bash "$t" < /dev/null); then
    printf 'PASS %s\n' "$(basename "$t")"
  else
    printf 'FAIL %s\n' "$(basename "$t")"
    failed=$((failed + 1))
  fi
done
[ "$failed" -eq 0 ] && echo "OK" || { echo "$failed failing file(s)"; exit 1; }
