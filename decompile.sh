#!/bin/bash
#
# decompile.sh — apktool-decompile an app's base.apk into apps/<app>/decompiled-apktool/.
#
# Usage:
#   ./decompile.sh                 # Interactive: pick from apps/*
#   ./decompile.sh <app>           # Decompile apps/<app>/apks/base.apk
#   ./decompile.sh <app> --force   # Overwrite an existing decompiled-apktool/
#   ./decompile.sh --apk <path>    # Decompile a specific APK (output still under apps/<app>/)
#
# The output directory is git-ignored via apps/*/decompiled-*/ — this is a
# regenerable reference dump, never commit it.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[-]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME=""
APK_OVERRIDE=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force|-f) FORCE=true; shift ;;
        --apk)      APK_OVERRIDE="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        -*) err "Unknown flag: $1" ;;
        *)
            if [[ -z "$APP_NAME" ]]; then
                APP_NAME="$1"
            else
                err "Unexpected positional argument: $1"
            fi
            shift
            ;;
    esac
done

command -v apktool >/dev/null 2>&1 || err "apktool not found on PATH. Install via the wrapper at ~/bin/apktool or 'apt install apktool'."

# ── Pick app (interactive if not supplied) ──────────────────────────
if [[ -z "$APP_NAME" ]]; then
    mapfile -t APPS < <(find "$SCRIPT_DIR/apps" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
    [[ ${#APPS[@]} -gt 0 ]] || err "No apps under apps/ — run ./add-app.sh first."

    echo ""
    echo -e "${BOLD}Select an app to decompile:${NC}"
    for i in "${!APPS[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${APPS[$i]}"
    done
    read -rp "  Select [1]: " idx
    idx="${idx:-1}"
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#APPS[@]} )) \
        || err "Invalid selection: $idx"
    APP_NAME="${APPS[$((idx-1))]}"
fi

APP_DIR="$SCRIPT_DIR/apps/$APP_NAME"
[[ -d "$APP_DIR" ]] || err "apps/$APP_NAME not found. Run ./add-app.sh to scaffold it."

# ── Resolve source APK ──────────────────────────────────────────────
if [[ -n "$APK_OVERRIDE" ]]; then
    SRC_APK="$APK_OVERRIDE"
else
    SRC_APK="$APP_DIR/apks/base.apk"
fi
[[ -f "$SRC_APK" ]] || err "APK not found: $SRC_APK
Place base.apk under apps/$APP_NAME/apks/ (re-run ./add-app.sh against the device, or copy the APK in manually)."

OUT_DIR="$APP_DIR/decompiled-apktool"

if [[ -d "$OUT_DIR" ]]; then
    if $FORCE; then
        log "Removing existing $OUT_DIR (--force)"
        rm -rf "$OUT_DIR"
    else
        err "$OUT_DIR already exists. Pass --force to overwrite."
    fi
fi

log "Decompiling $(realpath --relative-to="$SCRIPT_DIR" "$SRC_APK") → $(realpath --relative-to="$SCRIPT_DIR" "$OUT_DIR")/"
apktool d "$SRC_APK" -o "$OUT_DIR"

echo ""
log "Done."
echo -e "  ${BOLD}Smali:${NC}     $(realpath --relative-to="$SCRIPT_DIR" "$OUT_DIR")/smali_classes*/"
echo -e "  ${BOLD}Resources:${NC} $(realpath --relative-to="$SCRIPT_DIR" "$OUT_DIR")/res/"
echo -e "  ${BOLD}Manifest:${NC}  $(realpath --relative-to="$SCRIPT_DIR" "$OUT_DIR")/AndroidManifest.xml"
echo ""
echo -e "  ${DIM}Reverse-engineering recipes are in CLAUDE.md → 'Reverse-engineering recipes'.${NC}"
