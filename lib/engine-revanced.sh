#!/usr/bin/env bash
# Build a revanced-cli `patch` argument list (one arg per line, excl. `java -jar`).
# Requires _engine_selection_lines from engine-morphe.sh.
[ "$(type -t _engine_selection_lines)" = function ] || . "$(dirname "${BASH_SOURCE[0]}")/engine-morphe.sh"
engine_revanced_args() {
  local json="$1" cli="$2" apk="$3" out="$4" bf="$5"
  printf '%s\n' -jar "$cli" patch
  local b; while IFS= read -r b; do [ -n "$b" ] && printf '%s\n' -p "$b"; done < "$bf"
  printf '%s\n' -o "$out"
  _engine_selection_lines "$json"
  printf '%s\n' "$apk"
}
