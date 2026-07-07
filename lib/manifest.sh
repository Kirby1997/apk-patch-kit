#!/usr/bin/env bash
# Parse apps/<app>/sources.toml. Requires python3 (tomllib) + jq.

manifest_to_json() { # <toml-file> -> JSON on stdout; nonzero on invalid TOML
  python3 -c 'import tomllib,json,sys
json.dump(tomllib.load(open(sys.argv[1],"rb")),sys.stdout)' "$1"
}

manifest_get() { # <toml-file> <jq-filter> -> string ("" only if null/absent)
  manifest_to_json "$1" | jq -r "($2) as \$v | if \$v == null then \"\" else \$v end"
}

manifest_validate() { # <toml-file> -> 0 valid; nonzero + stderr on error
  local f="$1" json engine
  json="$(manifest_to_json "$f" 2>/dev/null)" || { echo "manifest: invalid TOML: $f" >&2; return 1; }
  engine="$(printf '%s' "$json" | jq -r '.engine // empty')"
  case "$engine" in morphe|revanced) ;; *) echo "manifest: engine must be morphe|revanced (got '$engine')" >&2; return 1 ;; esac
  [ "$(printf '%s' "$json" | jq '(.bundle // []) | length')" -ge 1 ] || { echo "manifest: need >=1 [[bundle]]" >&2; return 1; }
  if printf '%s' "$json" | jq -e '.bundle[] | select((.type // "") as $t | ($t|IN("github","gitlab","local"))|not)' >/dev/null; then
    echo "manifest: bundle.type must be github|gitlab|local" >&2; return 1; fi
  if printf '%s' "$json" | jq -e '.bundle[] | select(.type=="local")' >/dev/null && [ "$engine" != revanced ]; then
    echo "manifest: type=local requires engine=revanced" >&2; return 1; fi
  return 0
}
