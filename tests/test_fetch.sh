#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/fetch.sh"

assert_eq "$(fetch_cache_key github crimera/piko 3.7.0 patches-3.7.0.mpp)" \
  "github_crimera-piko_3.7.0_patches-3.7.0.mpp" "cache key"
assert_eq "$(fetch_gitlab_project_id inotia00/x-shim)" "inotia00%2Fx-shim" "gitlab project id"
t_summary
