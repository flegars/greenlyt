#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"

write_config "$repo" '{"testCommand":"echo ok && exit 0"}'
run_id="$("$GL_BIN" state init vert)"
assert_exit 0 "$GL_BIN" test "$run_id"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "exitCode vert"
assert_contains ok "$("$GL_BIN" state get "$run_id" .tests.tail)" "sortie capturée"

write_config "$repo" '{"testCommand":"echo boom >&2; exit 7"}'
assert_exit 7 "$GL_BIN" test "$run_id"
assert_eq 7 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "exitCode rouge"
assert_contains boom "$("$GL_BIN" state get "$run_id" .tests.tail)" "stderr capturé"

write_config "$repo" '{"testCommand":"seq 1 5000"}'
"$GL_BIN" test "$run_id" >/dev/null
tail_text="$(jq -r .tests.tail ".greenlyt/state/$run_id.json")"
assert_eq 200 "$(printf '%s\n' "$tail_text" | wc -l | tr -d ' ')" "200 lignes conservées"
assert_eq 5000 "$(printf '%s\n' "$tail_text" | tail -n 1)" "dernière ligne conservée"

mkdir -p sub
write_config "$repo" '{"testCommand":"test -f README.md"}'
assert_exit 0 bash -c "cd sub && '$GL_BIN' test '$run_id'"

write_config "$repo" '{}'
assert_exit 1 "$GL_BIN" test "$run_id"

finish
