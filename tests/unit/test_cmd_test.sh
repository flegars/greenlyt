#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"

repo="$(mk_repo)"
cd "$repo"

write_config "$repo" '{"testCommand":"echo ok && exit 0"}'
run_id="$("$GL_BIN" state init green)"
assert_exit 0 "$GL_BIN" test "$run_id"
assert_eq 0 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "green exitCode"
assert_contains ok "$("$GL_BIN" state get "$run_id" .tests.tail)" "output captured"

write_config "$repo" '{"testCommand":"echo boom >&2; exit 7"}'
assert_exit 7 "$GL_BIN" test "$run_id"
assert_eq 7 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "red exitCode"
assert_contains boom "$("$GL_BIN" state get "$run_id" .tests.tail)" "stderr captured"

write_config "$repo" '{"testCommand":"seq 1 5000"}'
"$GL_BIN" test "$run_id" >/dev/null
tail_text="$(jq -r .tests.tail ".greenlyt/state/$run_id.json")"
assert_eq 200 "$(printf '%s\n' "$tail_text" | wc -l | tr -d ' ')" "200 lines kept"
assert_eq 5000 "$(printf '%s\n' "$tail_text" | tail -n 1)" "last line kept"

write_config "$repo" '{"testCommand":"exit 0"}'
"$GL_BIN" test "$run_id" >/dev/null
write_config "$repo" '{"testCommand":"printf %01500000d 0; echo; exit 4"}'
assert_exit 4 "$GL_BIN" test "$run_id"
assert_eq 4 "$("$GL_BIN" state get "$run_id" .tests.exitCode)" "huge single-line output: red exit code recorded"
size="$(jq -r .tests.tail ".greenlyt/state/$run_id.json" | wc -c | tr -d ' ')"
[ "$size" -le 65537 ] || _fail "huge single-line output: tail capped at 64 KiB (got $size bytes)"

mkdir -p sub
write_config "$repo" '{"testCommand":"test -f README.md"}'
assert_exit 0 bash -c "cd sub && '$GL_BIN' test '$run_id'"

write_config "$repo" '{}'
assert_exit 1 "$GL_BIN" test "$run_id"

finish
