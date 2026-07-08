#!/usr/bin/env bash
# Build a morphe-cli `patch` argument list (one arg per line, excl. `java -jar`).

# Shared: emit -O/-e/-d/--exclusive lines from [patches]. Morphe + revanced use identical flags.
# Each token lands on its own line so the caller builds one argv element per line.
# Per-patch options come from [[patches.options]] entries ({ patch = "<name>", <key> = <val>, ... }).
# morphe binds -O options to the -e that FOLLOWS them, so each patch's -O lines are
# emitted immediately before its own -e.
_engine_selection_lines() { # json -> lines
  local json="$1"
  printf '%s' "$json" | jq -r '
    (.patches.options // []) as $opts
    | ( [ (.patches.enable // [])[] as $n
          | ( $opts[] | select(.patch == $n) | to_entries[] | select(.key != "patch")
              | ("-O", "\(.key)=\(.value)") ),
            ("-e", $n)
        ]
        + [ (.patches.disable // [])[] | ("-d", .) ]
        + (if (.patches.exclusive // false) then ["--exclusive"] else [] end)
      )[]'
}

# Args: json cli_jar apk out bundles_file
engine_morphe_args() {
  local json="$1" cli="$2" apk="$3" out="$4" bf="$5"
  printf '%s\n' -jar "$cli" patch
  local b; while IFS= read -r b; do [ -n "$b" ] && printf -- '--patches=%s\n' "$b"; done < "$bf"
  printf '%s\n' --purge -o "$out"
  # STRIP_FAST dex compile+verify breaks on a 9p/DrvFs mount (/mnt/c): the just-written
  # DEX isn't visible to the immediate verify step ("DEX file does not exist"). When
  # MORPHE_TMP is set (driver points it at native ext4, e.g. /tmp), relocate morphe's
  # temp there so the dex compile stays off the Windows mount.
  [ -n "${MORPHE_TMP:-}" ] && printf '%s\n' -t "$MORPHE_TMP"
  _engine_selection_lines "$json"
  printf '%s\n' "$apk"
}
