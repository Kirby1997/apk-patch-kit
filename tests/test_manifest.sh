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
t_summary
