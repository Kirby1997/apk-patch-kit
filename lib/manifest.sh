#!/usr/bin/env bash
# Parse apps/<app>/sources.toml. Requires python3 (tomllib) + jq.

manifest_to_json() { # <toml-file> -> JSON on stdout; nonzero on invalid TOML
  python3 -c 'import tomllib,json,sys
json.dump(tomllib.load(open(sys.argv[1],"rb")),sys.stdout)' "$1"
}

manifest_get() { # <toml-file> <jq-filter> -> string ("" if null/absent)
  manifest_to_json "$1" | jq -r "$2 // empty"
}
