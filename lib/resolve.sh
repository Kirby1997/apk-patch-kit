#!/usr/bin/env bash
# Resolve every [[bundle]] to a local file path, preserving order.
# resolve_local_jar <project> -> path (overridable in tests); default builds via gradle.
resolve_local_jar() { # project
  local proj="$1" root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  ( cd "$root" && ./gradlew ":patches:$proj:build" -q ) 1>&2 || return 1
  local jar; jar="$(ls -t "$root/patches/$proj/build/libs/"*.jar 2>/dev/null | head -1)"
  [ -n "$jar" ] || { echo "resolve: no jar built for $proj" >&2; return 1; }
  printf '%s' "$jar"
}

resolve_bundles() { # json app_dir out_file
  local json="$1" out="$3"; : > "$out"
  local n i type; n="$(printf '%s' "$json" | jq '.bundle | length')"
  for ((i=0; i<n; i++)); do
    type="$(printf '%s' "$json" | jq -r ".bundle[$i].type")"
    case "$type" in
      local)
        local proj; proj="$(printf '%s' "$json" | jq -r ".bundle[$i].project")"
        resolve_local_jar "$proj" >> "$out" || return 1; echo >> "$out" ;;
      github|gitlab)
        local repo ver asset sha
        repo="$(printf '%s' "$json" | jq -r ".bundle[$i].repo")"
        ver="$(printf '%s' "$json" | jq -r ".bundle[$i].version")"
        asset="$(printf '%s' "$json" | jq -r ".bundle[$i].asset // empty")"
        sha="$(printf '%s' "$json" | jq -r ".bundle[$i].sha256 // \"-\"")"
        [ -n "$asset" ] || asset="$(_resolve_default_asset "$type" "$repo" "$ver")" || return 1
        fetch_asset "$type" "$repo" "$ver" "$asset" "$sha" >> "$out" || return 1; echo >> "$out" ;;
      *) echo "resolve: bad bundle type $type" >&2; return 1 ;;
    esac
  done
}

_resolve_default_asset() { # type repo ver -> first *.mpp/*.rvp asset name
  local type="$1" repo="$2" ver="$3" name
  case "$type" in
    github) name="$(gh api "repos/$repo/releases/tags/$ver" --jq '.assets[].name' | grep -Ei '\.(mpp|rvp)$' | head -1)" ;;
    gitlab) name="$(curl -s "https://gitlab.com/api/v4/projects/$(fetch_gitlab_project_id "$repo")/releases/$ver" | jq -r '.assets.links[].name' | grep -Ei '\.(mpp|rvp)$' | head -1)" ;;
  esac
  [ -n "$name" ] || { echo "resolve: no .mpp/.rvp asset in $repo $ver" >&2; return 1; }
  printf '%s' "$name"
}
