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
    curl -fsL -o "$path" "$url" || { rm -f "$path"; echo "fetch: download failed: $url" >&2; return 1; }
  fi
  if [ "$sha" != "-" ]; then
    local got; got="$(sha256sum "$path" | cut -d' ' -f1)"
    [ "$got" = "$sha" ] || { rm -f "$path"; echo "fetch: sha256 mismatch for $key (got $got want $sha)" >&2; return 1; }
  else
    echo "fetch: $key sha256=$(sha256sum "$path" | cut -d' ' -f1) (pin this in sources.toml)" >&2
  fi
  printf '%s' "$path"
}

ENGINES_TOML="${ENGINES_TOML:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/engines.toml}"
BIN_DIR="${BIN_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin}"

engine_cli_key() { printf '%s-cli.jar' "$1"; }   # morphe -> morphe-cli.jar

engine_cli_path() { # engine (morphe|revanced) -> path to jar in bin/, fetching if absent
  local engine="$1" ver dst
  ver="$(python3 -c 'import tomllib,sys;print(tomllib.load(open(sys.argv[1],"rb"))[sys.argv[2]]["version"])' "$ENGINES_TOML" "$engine")" \
    || { echo "engine: no version pinned for $engine in $ENGINES_TOML" >&2; return 1; }
  mkdir -p "$BIN_DIR"; dst="$BIN_DIR/$(engine_cli_key "$engine")"
  if [ ! -f "$dst" ]; then
    local src
    case "$engine" in
      morphe)   src="$(fetch_asset github MorpheApp/morphe-cli "v$ver" "morphe-cli-$ver-all.jar" -)" ;;
      revanced) src="$(fetch_asset github ReVanced/revanced-cli "v$ver" "revanced-cli-$ver-all.jar" -)" ;;
      *) echo "engine: unknown engine $engine" >&2; return 1 ;;
    esac || return 1
    cp "$src" "$dst"
  fi
  printf '%s' "$dst"
}
