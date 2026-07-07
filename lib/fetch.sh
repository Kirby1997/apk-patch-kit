#!/usr/bin/env bash
# Resolve + download GitHub/GitLab release assets into a verified local cache.
FETCH_CACHE="${FETCH_CACHE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.cache/bundles}"

fetch_cache_key() { # host repo version asset
  printf '%s_%s_%s_%s' "$1" "$(printf '%s' "$2" | tr '/' '-')" "$3" "$4"
}

fetch_gitlab_project_id() { # repo (group/name) -> URL-encoded path
  printf '%s' "$1" | sed 's#/#%2F#g'
}

# fetch_asset host repo version asset sha256|- -> prints cached path; downloads if absent.
fetch_asset() {
  local host="$1" repo="$2" ver="$3" asset="$4" sha="$5"
  mkdir -p "$FETCH_CACHE"
  local key path url; key="$(fetch_cache_key "$host" "$repo" "$ver" "$asset")"; path="$FETCH_CACHE/$key"
  if [ ! -f "$path" ]; then
    case "$host" in
      github) url="$(gh api "repos/$repo/releases/tags/$ver" \
                 --jq ".assets[]|select(.name==\"$asset\")|.browser_download_url")" ;;
      gitlab) url="$(curl -s "https://gitlab.com/api/v4/projects/$(fetch_gitlab_project_id "$repo")/releases/$ver" \
                 | jq -r ".assets.links[]|select(.name==\"$asset\")|.url")" ;;
      *) echo "fetch: unknown host $host" >&2; return 1 ;;
    esac
    [ -n "$url" ] && [ "$url" != null ] || { echo "fetch: asset not found: $host $repo $ver $asset" >&2; return 1; }
    curl -sL -o "$path" "$url" || { rm -f "$path"; echo "fetch: download failed: $url" >&2; return 1; }
  fi
  if [ "$sha" != "-" ]; then
    local got; got="$(sha256sum "$path" | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || { echo "fetch: sha256 mismatch for $key (got $got want $sha)" >&2; return 1; }
  else
    echo "fetch: $key sha256=$(sha256sum "$path" | cut -d' ' -f1) (pin this in sources.toml)" >&2
  fi
  printf '%s' "$path"
}
