#!/bin/bash
#
# Universal ReVanced APK patcher with interactive patch selector.
#
# Usage:
#   ./patch-apks.sh                          # Interactive mode (prompts for everything)
#   ./patch-apks.sh --app <name>             # Select app (hidratenow, ...); picks apks + patches jar from apps/<name>
#   ./patch-apks.sh --apk <file> --patches <jar> [--cli <jar>]
#   ./patch-apks.sh --no-ui                  # Apply all patches, no prompts
#
# Layout assumed (run from repo root):
#   revanced-cli-*.jar           # shared CLI tool at repo root
#   patches/<app>/               # Gradle subproject; produces <app>-patches-*.jar
#   apps/<app>/apks/             # input APKs for that app
#   build/                       # output .apks bundles
#
# Requirements:
#   - Java 17+
#   - apksigner (apt install apksigner)
#   - revanced-cli jar
#   - keytool

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────
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

# ── Defaults ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP=""
APK_FILE=""
PATCHES_JAR=""
REVANCED_CLI=""
NO_UI=false

# ── Parse CLI arguments ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)       APP="$2"; shift 2 ;;
        --apk)       APK_FILE="$2"; shift 2 ;;
        --patches)   PATCHES_JAR="$2"; shift 2 ;;
        --cli)       REVANCED_CLI="$2"; shift 2 ;;
        --no-ui)     NO_UI=true; shift ;;
        --help|-h)
            echo "Usage: ./patch-apks.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --app <name>       App subproject name (e.g. hidratenow). Auto-picks APK + patches jar"
            echo "  --apk <file>       APK or APKS file to patch (overrides --app apk lookup)"
            echo "  --patches <jar>    Patches JAR/RVP file (overrides --app jar lookup)"
            echo "  --cli <jar>        Path to revanced-cli jar"
            echo "  --no-ui            Skip interactive UI, apply all patches"
            echo "  -h, --help         Show this help"
            exit 0
            ;;
        *) err "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ── App picker ──────────────────────────────────────────────────────
pick_app() {
    local apps_dir="$SCRIPT_DIR/apps"
    [[ -d "$apps_dir" ]] || err "No apps/ directory found"

    local apps=()
    while IFS= read -r -d '' d; do
        apps+=("$(basename "$d")")
    done < <(find "$apps_dir" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

    [[ ${#apps[@]} -gt 0 ]] || err "No app subdirectories under apps/"

    echo "" >&2
    echo -e "${BOLD}Select app:${NC}" >&2
    echo "" >&2
    for i in "${!apps[@]}"; do
        echo -e "  ${CYAN}$((i + 1))${NC}) ${apps[$i]}" >&2
    done
    echo "" >&2

    while true; do
        read -rp "  Select [1]: " choice
        choice="${choice:-1}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#apps[@]} )); then
            echo "${apps[$((choice - 1))]}"
            return
        fi
        echo -e "  ${RED}Invalid selection.${NC}" >&2
    done
}

# ── File picker ─────────────────────────────────────────────────────
# Lists files matching a glob, lets the user pick by number.
pick_file() {
    local prompt="$1"
    local search_root="$2"
    shift 2
    local patterns=("$@")
    local files=()

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$search_root" -maxdepth 4 -name "$pattern" -print0 2>/dev/null | sort -z)
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    echo "" >&2
    echo -e "${BOLD}${prompt}${NC}" >&2
    echo "" >&2
    for i in "${!files[@]}"; do
        local display="${files[$i]#"$SCRIPT_DIR"/}"
        echo -e "  ${CYAN}$((i + 1))${NC}) $display" >&2
    done
    echo "" >&2
    echo -e "  ${CYAN}0${NC}) Enter a custom path" >&2
    echo "" >&2

    while true; do
        read -rp "  Select [1]: " choice
        choice="${choice:-1}"

        if [[ "$choice" == "0" ]]; then
            read -rp "  Path: " custom_path
            if [[ -f "$custom_path" ]]; then
                echo "$custom_path"
                return
            fi
            echo -e "  ${RED}File not found.${NC}" >&2
            continue
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#files[@]} )); then
            echo "${files[$((choice - 1))]}"
            return
        fi
        echo -e "  ${RED}Invalid selection.${NC}" >&2
    done
}

# ── Parse patch names from the patches jar ─────────────────────────
get_patch_names() {
    local cli_jar="$1"
    local patches_jar="$2"

    # Use list-patches: patcher 22+ crashes in ResourcesDecoder before any
    # patches load if the "APK" input isn't really an APK, so the old
    # dry-run trick no longer yields a patch list.
    java -jar "$cli_jar" list-patches -p "$patches_jar" -b 2>/dev/null \
        | sed -n 's/^Name: //p'
}

# ── Interactive patch selector ──────────────────────────────────────
patch_selector() {
    local -n _names=$1
    local -n _states=$2
    local count=${#_names[@]}

    while true; do
        echo ""
        echo -e "${BOLD}${CYAN}  ┌──────────────────────────────────────────┐${NC}"
        echo -e "${BOLD}${CYAN}  │         Patch Selector                   │${NC}"
        echo -e "${BOLD}${CYAN}  └──────────────────────────────────────────┘${NC}"
        echo ""

        for i in "${!_names[@]}"; do
            local indicator
            if [[ "${_states[$i]}" == "on" ]]; then
                indicator="${GREEN}[x]${NC}"
            else
                indicator="${RED}[ ]${NC}"
            fi
            echo -e "    ${CYAN}$((i + 1))${NC}) ${indicator} ${_names[$i]}"
        done

        local enabled_count=0
        for state in "${_states[@]}"; do
            [[ "$state" == "on" ]] && ((enabled_count++))
        done

        echo ""
        echo -e "  ${DIM}──────────────────────────────────────────────${NC}"
        echo -e "  ${CYAN}${enabled_count}/${count}${NC} patches enabled"
        echo ""
        echo -e "  ${DIM}Enter a number to toggle, or:${NC}"
        echo -e "  ${DIM}  a = all on  |  n = all off  |  Enter = continue  |  q = quit${NC}"
        echo ""
        read -rp "  > " input

        case "$input" in
            "")
                if [[ $enabled_count -eq 0 ]]; then
                    warn "No patches enabled. Select at least one or press q to quit."
                    continue
                fi
                return 0
                ;;
            q|Q) echo "Aborted."; exit 0 ;;
            a|A) for i in "${!_states[@]}"; do _states[$i]="on"; done ;;
            n|N) for i in "${!_states[@]}"; do _states[$i]="off"; done ;;
            *)
                if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= count )); then
                    local idx=$((input - 1))
                    if [[ "${_states[$idx]}" == "on" ]]; then
                        _states[$idx]="off"
                    else
                        _states[$idx]="on"
                    fi
                else
                    warn "Invalid input. Enter a number 1-${count}, a, n, or Enter."
                fi
                ;;
        esac
    done
}

# ── Main ────────────────────────────────────────────────────────────

echo -e "${BOLD}${CYAN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║         ReVanced APK Patcher                 ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Find revanced-cli ───────────────────────────────────────────────
if [[ -z "$REVANCED_CLI" ]]; then
    REVANCED_CLI=$(pick_file "Select revanced-cli JAR:" "$SCRIPT_DIR" "revanced-cli-*-all.jar" "revanced-cli*.jar")
fi
[[ -n "$REVANCED_CLI" && -f "$REVANCED_CLI" ]] || err "revanced-cli jar not found. Use --cli <path> or place one in the repo root."
log "CLI: $(basename "$REVANCED_CLI")"

# ── Resolve app ─────────────────────────────────────────────────────
if [[ -z "$APP" && -z "$APK_FILE" && -z "$PATCHES_JAR" ]]; then
    APP=$(pick_app)
fi
if [[ -n "$APP" ]]; then
    [[ -d "$SCRIPT_DIR/apps/$APP" ]] || err "apps/$APP does not exist"
    log "App: $APP"
fi

# ── Find patches jar ───────────────────────────────────────────────
if [[ -z "$PATCHES_JAR" ]]; then
    if [[ -n "$APP" ]]; then
        PATCHES_PROJECT="$SCRIPT_DIR/patches/$APP"
        if [[ -d "$PATCHES_PROJECT" ]]; then
            echo ""
            read -rp "  Build :patches:$APP from source? (Y/n): " build_choice
            if [[ "${build_choice:-Y}" =~ ^[Yy]$ ]]; then
                log "Building :patches:$APP ..."
                (cd "$SCRIPT_DIR" && ./gradlew ":patches:$APP:build" -q 2>&1 | tail -5)
            fi
            PATCHES_JAR=$(find "$PATCHES_PROJECT/build/libs" -maxdepth 1 -name '*.jar' 2>/dev/null | head -1)
        fi
    fi

    if [[ -z "$PATCHES_JAR" || ! -f "$PATCHES_JAR" ]]; then
        PATCHES_JAR=$(pick_file "Select patches JAR/RVP:" "$SCRIPT_DIR" "*patches*.jar" "*.rvp")
    fi
fi
[[ -n "$PATCHES_JAR" && -f "$PATCHES_JAR" ]] || err "Patches file not found."
log "Patches: $(basename "$PATCHES_JAR")"

# ── Find APK ───────────────────────────────────────────────────────
if [[ -z "$APK_FILE" ]]; then
    if [[ -n "$APP" && -d "$SCRIPT_DIR/apps/$APP/apks" ]]; then
        APK_FILE=$(pick_file "Select APK or APKS to patch:" "$SCRIPT_DIR/apps/$APP/apks" "*.apk" "*.apks")
    fi
    if [[ -z "$APK_FILE" ]]; then
        APK_FILE=$(pick_file "Select APK or APKS to patch:" "$SCRIPT_DIR" "*.apk" "*.apks")
    fi
fi
[[ -n "$APK_FILE" && -f "$APK_FILE" ]] || err "APK file not found."
log "APK: $(basename "$APK_FILE")"

# ── Check apksigner ────────────────────────────────────────────────
IS_APKS=false
if [[ "$APK_FILE" == *.apks ]]; then
    IS_APKS=true
    command -v apksigner >/dev/null 2>&1 || err "apksigner required for .apks bundles. Install with: sudo apt install apksigner"
fi

# ── Discover available patches ──────────────────────────────────────
log "Discovering patches..."
declare -a PATCH_NAMES=()
declare -a PATCH_STATES=()

while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    PATCH_NAMES+=("$name")
    PATCH_STATES+=("on")
done < <(get_patch_names "$REVANCED_CLI" "$PATCHES_JAR")

if [[ ${#PATCH_NAMES[@]} -eq 0 ]]; then
    err "No patches found in $(basename "$PATCHES_JAR")"
fi

log "Found ${#PATCH_NAMES[@]} patch(es)"

# ── Patch selector UI ──────────────────────────────────────────────
if ! $NO_UI; then
    patch_selector PATCH_NAMES PATCH_STATES
fi

# ── Print selection summary ─────────────────────────────────────────
echo ""
log "Patch configuration:"
for i in "${!PATCH_NAMES[@]}"; do
    if [[ "${PATCH_STATES[$i]}" == "on" ]]; then
        echo -e "    ${GREEN}[x]${NC} ${PATCH_NAMES[$i]}"
    else
        echo -e "    ${DIM}[ ] ${PATCH_NAMES[$i]}${NC}"
    fi
done
echo ""

# ── Build revanced-cli args ────────────────────────────────────────
CLI_PATCH_ARGS=("--exclusive")
for i in "${!PATCH_NAMES[@]}"; do
    if [[ "${PATCH_STATES[$i]}" == "on" ]]; then
        CLI_PATCH_ARGS+=("-e" "${PATCH_NAMES[$i]}")
    fi
done

# ── Setup work directory ───────────────────────────────────────────
WORK_DIR="$SCRIPT_DIR/build/patch-work"
mkdir -p "$WORK_DIR/extracted" "$WORK_DIR/patched-splits"
find "$WORK_DIR/extracted" -type f -delete 2>/dev/null || true
find "$WORK_DIR/patched-splits" -type f -delete 2>/dev/null || true
rm -f "$WORK_DIR"/*.apk "$WORK_DIR"/*.p12 "$WORK_DIR"/*.keystore 2>/dev/null || true

# ── Determine the actual APK to patch ──────────────────────────────
if $IS_APKS; then
    log "Extracting .apks bundle..."
    unzip -o -q "$APK_FILE" -d "$WORK_DIR/extracted"
    BASE_APK="$WORK_DIR/extracted/base.apk"
    [[ -f "$BASE_APK" ]] || err "No base.apk found in the bundle"
    log "Extracted $(ls "$WORK_DIR/extracted/"*.apk | wc -l) APK(s) from bundle"
else
    BASE_APK="$APK_FILE"
fi

# ── Patch ──────────────────────────────────────────────────────────
PATCHED_APK="$WORK_DIR/patched-base.apk"
log "Patching $(basename "$BASE_APK")..."

java -jar "$REVANCED_CLI" patch \
    -p "$PATCHES_JAR" -b \
    -o "$PATCHED_APK" \
    --force \
    "${CLI_PATCH_ARGS[@]}" \
    "$BASE_APK" 2>&1 | while IFS= read -r line; do echo "    $line"; done

[[ -f "$PATCHED_APK" ]] || err "Patched APK not produced"
log "Patching complete"

# ── Signing ────────────────────────────────────────────────────────
KEYSTORE="$WORK_DIR/sign.p12"
KS_PASS="revanced"
KS_ALIAS="key"

log "Generating signing keystore..."
keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storetype PKCS12 \
    -storepass "$KS_PASS" \
    -keypass "$KS_PASS" \
    -alias "$KS_ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=ReVanced" \
    2>/dev/null

if $IS_APKS; then
    log "Signing all APKs with consistent keystore..."

    cp "$PATCHED_APK" "$WORK_DIR/patched-splits/base.apk"
    apksigner sign \
        --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" \
        --ks-key-alias "$KS_ALIAS" --key-pass "pass:$KS_PASS" \
        "$WORK_DIR/patched-splits/base.apk"
    log "  Signed: base.apk"

    for split in "$WORK_DIR/extracted"/split_*.apk; do
        if [[ -f "$split" ]]; then
            SPLIT_NAME="$(basename "$split")"
            cp "$split" "$WORK_DIR/patched-splits/$SPLIT_NAME"
            apksigner sign \
                --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" \
                --ks-key-alias "$KS_ALIAS" --key-pass "pass:$KS_PASS" \
                "$WORK_DIR/patched-splits/$SPLIT_NAME"
            log "  Signed: $SPLIT_NAME"
        fi
    done

    log "Verifying signatures..."
    for apk in "$WORK_DIR/patched-splits"/*.apk; do
        CERT=$(apksigner verify --print-certs "$apk" 2>&1 | grep "certificate SHA-256" | head -1)
        echo "    $(basename "$apk"): $CERT"
    done

    APK_BASENAME="$(basename "$APK_FILE" .apks)"
    OUTPUT_APKS="$SCRIPT_DIR/build/${APK_BASENAME}-patched.apks"
    mkdir -p "$(dirname "$OUTPUT_APKS")"

    log "Assembling patched .apks bundle..."
    cd "$WORK_DIR/patched-splits"
    rm -f "$OUTPUT_APKS"
    jar cMf "$OUTPUT_APKS" *.apk

    log "Output: $OUTPUT_APKS"
    log "Size: $(du -h "$OUTPUT_APKS" | cut -f1)"
    echo ""
    log "Install with:"
    echo "    adb install-multiple $WORK_DIR/patched-splits/*.apk"
else
    APK_BASENAME="$(basename "$APK_FILE" .apk)"
    OUTPUT_APK="$SCRIPT_DIR/build/${APK_BASENAME}-patched.apk"
    mkdir -p "$(dirname "$OUTPUT_APK")"

    cp "$PATCHED_APK" "$OUTPUT_APK"
    apksigner sign \
        --ks "$KEYSTORE" --ks-pass "pass:$KS_PASS" \
        --ks-key-alias "$KS_ALIAS" --key-pass "pass:$KS_PASS" \
        "$OUTPUT_APK" 2>/dev/null || true

    log "Output: $OUTPUT_APK"
    log "Size: $(du -h "$OUTPUT_APK" | cut -f1)"
    echo ""
    log "Install with:"
    echo "    adb install \"$OUTPUT_APK\""
fi

echo ""
