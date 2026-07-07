#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"
FX="$HERE/fixtures"

assert_eq "$(manifest_get "$FX/twitter.toml" '.engine')" "morphe" "twitter engine"
assert_eq "$(manifest_get "$FX/twitter.toml" '.package')" "com.twitter.android" "twitter package"
assert_eq "$(manifest_get "$FX/twitter.toml" '.bundle | length')" "2" "twitter bundle count"
assert_eq "$(manifest_get "$FX/twitter.toml" '.bundle[0].repo')" "crimera/piko" "twitter bundle0 repo"
assert_eq "$(manifest_get "$FX/hidratespark.toml" '.bundle[0].type')" "local" "hs bundle type"
assert_eq "$(manifest_get "$FX/twitter.toml" '.patches.exclusive')" "false" "present false preserved"
assert_eq "$(manifest_get "$FX/twitter.toml" '.patches.nonexistent')" "" "absent field empty"

assert_eq "$(manifest_validate "$FX/twitter.toml" >/dev/null 2>&1; echo $?)" "0" "twitter valid"
assert_eq "$(manifest_validate "$FX/hidratespark.toml" >/dev/null 2>&1; echo $?)" "0" "hs valid"
assert_nonzero manifest_validate "$FX/bad-engine.toml"
assert_nonzero manifest_validate "$FX/bad-local-morphe.toml"
assert_nonzero manifest_validate "$FX/bad-nobundle.toml"
assert_nonzero manifest_validate "$FX/bad-type.toml"
assert_eq "$(manifest_validate "$FX/url-ok.toml" >/dev/null 2>&1; echo $?)" "0" "url bundle valid"

t_summary
