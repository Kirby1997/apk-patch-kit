#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"; . "$ROOT/lib/fetch.sh"; . "$ROOT/lib/resolve.sh"

# Stub the local builder + gradle so the test is pure.
resolve_local_jar() { printf '%s' "/fake/${1}-patches.jar"; }
J="$(manifest_to_json "$HERE/fixtures/local-only.toml")"
OUTF="$(mktemp)"
resolve_bundles "$J" /fake/appdir "$OUTF"
assert_eq "$(cat "$OUTF")" "/fake/demoapp-patches.jar" "local resolves to built jar"
rm -f "$OUTF"
t_summary
