#!/usr/bin/env bash
# Build a morphe-cli `patch` argument list (one arg per line, excl. `java -jar`).

# Shared: emit -e/-d/--exclusive lines from [patches]. Morphe + revanced use identical flags.
# jq emits "-e\nNAME" per enabled patch so each token lands on its own line.
_engine_selection_lines() { # json -> lines
  local json="$1"
  printf '%s' "$json" | jq -r '
    ((.patches.enable  // []) | map("-e\n\(.)")) +
    ((.patches.disable // []) | map("-d\n\(.)")) +
    (if (.patches.exclusive // false) then ["--exclusive"] else [] end)
    | .[]'
}

# Args: json cli_jar apk out bundles_file
engine_morphe_args() {
  local json="$1" cli="$2" apk="$3" out="$4" bf="$5"
  printf '%s\n' -jar "$cli" patch
  local b; while IFS= read -r b; do [ -n "$b" ] && printf -- '--patches=%s\n' "$b"; done < "$bf"
  printf '%s\n' --purge -o "$out"
  _engine_selection_lines "$json"
  printf '%s\n' "$apk"
}
