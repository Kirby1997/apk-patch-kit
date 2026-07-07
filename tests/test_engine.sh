#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/.." && pwd)"
. "$HERE/lib.sh"; . "$ROOT/lib/manifest.sh"
. "$ROOT/lib/engine-morphe.sh"; . "$ROOT/lib/engine-revanced.sh"
FX="$HERE/fixtures"

BF="$(mktemp)"; printf '/c/piko.mpp\n/c/xshim.mpp\n' > "$BF"
J="$(manifest_to_json "$FX/twitter.toml")"
OUT="$(engine_morphe_args "$J" /bin/morphe-cli.jar in.apkm out.apk "$BF" | tr '\n' ' ')"
assert_contains "$OUT" "patch" "morphe subcommand"
assert_contains "$OUT" "--patches=/c/piko.mpp" "morphe bundle0"
assert_contains "$OUT" "--patches=/c/xshim.mpp" "morphe bundle1"
assert_contains "$OUT" "-o out.apk" "morphe output"
assert_contains "$OUT" "in.apkm" "morphe input"

BF2="$(mktemp)"; printf '/c/hs.rvp\n' > "$BF2"
JH="$(manifest_to_json "$FX/hidratespark.toml")"
OUTH="$(engine_revanced_args "$JH" /bin/revanced-cli.jar base.apk out2.apk "$BF2" | tr '\n' ' ')"
assert_contains "$OUTH" "patch" "revanced subcommand"
assert_contains "$OUTH" "-p /c/hs.rvp" "revanced bundle"
assert_contains "$OUTH" "base.apk" "revanced input"
rm -f "$BF" "$BF2"

BF3="$(mktemp)"; printf '/c/b.mpp\n' > "$BF3"
JS="$(manifest_to_json "$FX/select.toml")"
SEL="$(engine_morphe_args "$JS" cli.jar a.apkm o.apk "$BF3" | tr '\n' '|')"
assert_contains "$SEL" "-e|Remove Ads" "enable pair"
assert_contains "$SEL" "-d|Custom font" "disable pair"
assert_contains "$SEL" "--exclusive" "exclusive flag"
rm -f "$BF3"

# MORPHE_TMP relocates morphe's temp off a 9p mount (emits -t only when set)
BF4="$(mktemp)"; printf '/c/b.mpp\n' > "$BF4"
JT="$(manifest_to_json "$FX/twitter.toml")"
NOTMP="$(engine_morphe_args "$JT" cli.jar a.apkm o.apk "$BF4" | tr '\n' '|')"
case "$NOTMP" in *"|-t|"*) assert_eq "unset-emitted-t" "unset-no-t" "MORPHE_TMP unset → no -t" ;; *) assert_eq ok ok "MORPHE_TMP unset → no -t" ;; esac
WITHTMP="$(MORPHE_TMP=/tmp/xyz engine_morphe_args "$JT" cli.jar a.apkm o.apk "$BF4" | tr '\n' '|')"
assert_contains "$WITHTMP" "-t|/tmp/xyz" "MORPHE_TMP set → -t emitted"
rm -f "$BF4"

t_summary
