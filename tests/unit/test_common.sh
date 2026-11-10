#!/usr/bin/env bash
source "$(dirname "$0")/helpers.sh"
source "$GL_PLUGIN_ROOT/lib/common.sh"

repo="$(mk_repo)"
cd "$repo"

assert_eq 5 "$(gl_config_get .maxAttempts)" "default maxAttempts"
assert_eq docs/greenlyt "$(gl_config_get .docsDir)" "default docsDir"
assert_eq main "$(gl_config_get .forge.baseBranch)" "default baseBranch"
assert_exit 1 gl_has_config

write_config "$repo" '{"maxAttempts":3,"forge":{"type":"github"}}'
assert_eq 3 "$(gl_config_get .maxAttempts)" "overridden maxAttempts"
assert_eq origin "$(gl_config_get .forge.remote)" "deep merge of defaults"
assert_eq fallback "$(gl_config_get .absent fallback)" "fallback value"
assert_exit 0 gl_has_config

write_config "$repo" '{"testCommand":"printf \"%s\\n\" \"a b\"","maxAttempts":3,"protectedBranches":["main"],"flag":false}'
assert_eq 'printf "%s\n" "a b"' "$(gl_config_get .testCommand)" "quoted command is unescaped"
assert_eq "a b" "$(bash -c "$(gl_config_get .testCommand)")" "quoted command runs as written"
assert_eq '["main"]' "$(gl_config_get .protectedBranches)" "arrays stay JSON"
assert_eq false "$(gl_config_get .flag)" "false is a value, not a missing key"
write_config "$repo" '{"maxAttempts":3,"forge":{"type":"github"}}'
assert_eq "$repo" "$(gl_root)" "git root"

assert_exit 1 gl_killed
touch .greenlyt/STOP
assert_exit 0 gl_killed
rm .greenlyt/STOP
GREENLYT_DISABLED=1 assert_exit 0 gl_killed

assert_exit 2 "$GL_BIN" nope
assert_eq docs/greenlyt "$("$GL_BIN" config .docsDir)" "config CLI: default"
assert_eq 3 "$("$GL_BIN" config .maxAttempts)" "config CLI: override"

finish
