#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/fetch.sh"

assert_eq "$(fetch_cache_key github crimera/piko 3.7.0 patches-3.7.0.mpp)" \
  "github_crimera-piko_3.7.0_patches-3.7.0.mpp" "cache key"
assert_eq "$(fetch_gitlab_project_id inotia00/x-shim)" "inotia00%2Fx-shim" "gitlab project id"
assert_eq "$(engine_cli_key morphe 1.9.1)" "morphe-cli-1.9.1.jar" "cli key morphe versioned"
assert_eq "$(fetch_url_key https://api.revanced.app/v5/patches.rvp)" \
  "url_$(printf %s https://api.revanced.app/v5/patches.rvp | sha256sum | cut -c1-16)_patches.rvp" "url key"
t_summary
