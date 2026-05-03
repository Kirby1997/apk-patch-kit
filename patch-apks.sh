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
SIGN_ONLY=false
MAPS_KEY="${MAPS_API_KEY:-}"
PACKAGE=""
INCLUDE_UNIVERSAL=false
NO_FILTER=false
INSTALL=false
REINSTALL=false
ADB_OVERRIDE=""

# ── Parse CLI arguments ─────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)               APP="$2"; shift 2 ;;
        --apk)               APK_FILE="$2"; shift 2 ;;
        --patches)           PATCHES_JAR="$2"; shift 2 ;;
        --cli)               REVANCED_CLI="$2"; shift 2 ;;
        --no-ui)             NO_UI=true; shift ;;
        --sign-only)         SIGN_ONLY=true; shift ;;
        --maps-key)          MAPS_KEY="$2"; shift 2 ;;
        --package)           PACKAGE="$2"; shift 2 ;;
        --include-universal) INCLUDE_UNIVERSAL=true; shift ;;
        --no-filter)         NO_FILTER=true; shift ;;
        --install)           INSTALL=true; shift ;;
        --reinstall)         INSTALL=true; REINSTALL=true; shift ;;
        --adb)               ADB_OVERRIDE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: ./patch-apks.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --app <name>         App subproject name (e.g. hidratenow). Auto-picks APK + patches jar"
            echo "  --apk <file>         APK or APKS file to patch (overrides --app apk lookup)"
            echo "  --patches <jar>      Patches JAR/RVP file (overrides --app jar lookup)"
            echo "  --cli <jar>          Path to revanced-cli jar"
            echo "  --no-ui              Skip interactive UI, apply all patches"
            echo "  --sign-only          Skip patching entirely, just re-sign and repack"
            echo "  --maps-key <key>     Google Maps API key to inject via the 'Inject Google Maps API key' patch"
            echo ""
            echo "Install:"
            echo "  --install            adb-install the patched APK after building (in-place; keeps app data."
            echo "                       Bails with a hint if the device's installed copy was signed differently)."
            echo "  --reinstall          As --install, but uninstall first (wipes app data — only needed when"
            echo "                       transitioning from the Play Store build to the patched build)."
            echo "  --adb <path>         Override adb binary location (default: WSL→adb.exe, else adb on PATH)."
            echo ""
            echo "Patch filtering (applies when using a large upstream bundle like patches.rvp):"
            echo "  --package <pkg>      Explicit package name to filter patches by (e.g. com.strava)."
            echo "                       When --app is used, the package is auto-read from apps/<app>/README.md."
            echo "  --include-universal  Also show 'universal' patches (compatible with any app) in the selector."
            echo "                       Off by default to keep the selector small."
            echo "  --no-filter          Disable package filtering entirely — show every patch in the bundle."
            echo ""
            echo "  -h, --help           Show this help"
            exit 0
            ;;
        *) err "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ── adb locator ─────────────────────────────────────────────────────
# Mirrors add-app.sh: on WSL we must call the Windows adb.exe (USB devices
# are invisible to the Linux adb without usbipd), so prefer adb.exe when
# we can find it, fall back to adb on PATH otherwise.
locate_adb() {
    [[ -n "$ADB_OVERRIDE" ]] && { echo "$ADB_OVERRIDE"; return 0; }

    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        if command -v adb.exe >/dev/null 2>&1; then
            command -v adb.exe
            return 0
        fi
        local candidate
        for base in /mnt/c/Users/*/AppData/Local/Android/Sdk/platform-tools \
                    "/mnt/c/Program Files/Android/Sdk/platform-tools" \
                    "/mnt/c/Program Files (x86)/Android/Sdk/platform-tools" \
                    /mnt/c/ProgramData/chocolatey/bin; do
            candidate="$base/adb.exe"
            [[ -x "$candidate" ]] && { echo "$candidate"; return 0; }
        done
    fi

    if command -v adb >/dev/null 2>&1; then
        command -v adb
        return 0
    fi
    return 1
}

# adb.exe is a Windows binary; pass Windows-style paths to its install args.
# On native Linux this is a no-op.
adb_local_path() {
    if [[ "${ADB:-}" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

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
            # Split APKs from Android App Bundles can't be patched on their own —
            # they carry no dex code, only per-config resources. Hide them from
            # the picker so users don't accidentally pick one.
            [[ "$(basename "$f")" == split_*.apk ]] && continue
            files+=("$f")
        done < <(find "$search_root" -maxdepth 4 -name "$pattern" -print0 2>/dev/null | sort -z)
    done

    # Dedupe — overlapping patterns (e.g. revanced-cli-*-all.jar and
    # revanced-cli*.jar) can match the same file twice. Order-preserving.
    if [[ ${#files[@]} -gt 1 ]]; then
        mapfile -t files < <(printf '%s\n' "${files[@]}" | awk '!seen[$0]++')
    fi

    # When a .apks bundle is in the mix, drop standalone .apk files — the
    # bundle already contains base + every split, so listing them separately
    # is redundant and just invites a wrong pick.
    local has_apks=false
    for f in "${files[@]}"; do
        [[ "$f" == *.apks ]] && { has_apks=true; break; }
    done
    if $has_apks; then
        local filtered=()
        for f in "${files[@]}"; do
            [[ "$f" == *.apks ]] && filtered+=("$f")
        done
        files=("${filtered[@]}")
    fi

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
# Accepts optional --filter-package-name / --universal-patches=false to
# let the caller scope the list to an app's compatible patches. See the
# "Discover + select patches" block below for how the flags are chosen.
get_patch_names() {
    local cli_jar="$1"
    local patches_jar="$2"
    shift 2
    # Remaining args: extra flags forwarded to list-patches.

    # Use list-patches: patcher 22+ crashes in ResourcesDecoder before any
    # patches load if the "APK" input isn't really an APK, so the old
    # dry-run trick no longer yields a patch list.
    java -jar "$cli_jar" list-patches -p "$patches_jar" -b "$@" 2>/dev/null \
        | sed -n 's/^Name: //p'
}

# Read the declared package name for an app from its README front-matter.
# The add-app scaffolder writes `- **Package:** `com.foo.bar`` as the first
# bullet; this greps that line back out.
read_app_package() {
    local app="$1"
    local readme="$SCRIPT_DIR/apps/$app/README.md"
    [[ -f "$readme" ]] || return 1
    # Matches: - **Package:** `com.foo.bar`
    sed -n 's/^- \*\*Package:\*\* `\([^`]*\)`.*/\1/p' "$readme" | head -1
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
            [[ "$state" == "on" ]] && enabled_count=$((enabled_count + 1))
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

# ── Find revanced-cli (skipped in --sign-only) ─────────────────────
if ! $SIGN_ONLY; then
    if [[ -z "$REVANCED_CLI" ]]; then
        REVANCED_CLI=$(pick_file "Select revanced-cli JAR:" "$SCRIPT_DIR" "revanced-cli-*-all.jar" "revanced-cli*.jar")
    fi
    [[ -n "$REVANCED_CLI" && -f "$REVANCED_CLI" ]] || err "revanced-cli jar not found. Use --cli <path> or place one in the repo root."
    log "CLI: $(basename "$REVANCED_CLI")"
else
    log "Sign-only mode: skipping patcher (will re-sign the original APK unchanged)"
fi

# ── Resolve app ─────────────────────────────────────────────────────
if [[ -z "$APP" && -z "$APK_FILE" && -z "$PATCHES_JAR" ]]; then
    APP=$(pick_app)
fi
if [[ -n "$APP" ]]; then
    [[ -d "$SCRIPT_DIR/apps/$APP" ]] || err "apps/$APP does not exist"
    log "App: $APP"
fi

# ── Find patches jar (skipped in --sign-only) ──────────────────────
if ! $SIGN_ONLY; then
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
fi

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

# ── Discover + select patches (skipped in --sign-only) ─────────────
declare -a PATCH_NAMES=()
declare -a PATCH_STATES=()
CLI_PATCH_ARGS=()

if ! $SIGN_ONLY; then
    # Resolve the package name for filtering. Precedence:
    #   1. --package <pkg> (explicit override)
    #   2. `apps/<app>/README.md` "Package:" line, when --app is used
    # If neither is available, we don't filter — every patch in the bundle shows
    # up as before (that's the correct behaviour for ad-hoc `--apk` runs).
    if [[ -z "$PACKAGE" && -n "$APP" ]]; then
        PACKAGE=$(read_app_package "$APP" || true)
        [[ -n "$PACKAGE" ]] && log "Package (from apps/$APP/README.md): $PACKAGE"
    fi

    LIST_FLAGS=()
    if ! $NO_FILTER && [[ -n "$PACKAGE" ]]; then
        LIST_FLAGS+=("--filter-package-name=$PACKAGE")
        if ! $INCLUDE_UNIVERSAL; then
            LIST_FLAGS+=("--universal-patches=false")
        fi
    fi

    log "Discovering patches..."

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        PATCH_NAMES+=("$name")
        PATCH_STATES+=("on")
    done < <(get_patch_names "$REVANCED_CLI" "$PATCHES_JAR" "${LIST_FLAGS[@]}")

    if [[ ${#PATCH_NAMES[@]} -eq 0 ]]; then
        err "No patches found in $(basename "$PATCHES_JAR")"
    fi

    # Count hidden universals so users know the flag exists. We only compute
    # this when filtering is active; otherwise it's noise.
    if ! $NO_FILTER && [[ -n "$PACKAGE" ]] && ! $INCLUDE_UNIVERSAL; then
        UNIVERSAL_COUNT=$(get_patch_names "$REVANCED_CLI" "$PATCHES_JAR" \
            "--filter-package-name=__nonexistent__" 2>/dev/null | grep -c . || true)
        log "Found ${#PATCH_NAMES[@]} patch(es) for $PACKAGE (${UNIVERSAL_COUNT} universal patches hidden — pass --include-universal to see them)"
    elif ! $NO_FILTER && [[ -n "$PACKAGE" ]]; then
        log "Found ${#PATCH_NAMES[@]} patch(es) for $PACKAGE (including universal)"
    else
        log "Found ${#PATCH_NAMES[@]} patch(es) (unfiltered — pass --package <pkg> or use --app to scope)"
    fi

    if ! $NO_UI; then
        patch_selector PATCH_NAMES PATCH_STATES
    fi

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

    CLI_PATCH_ARGS=("--exclusive")
    for i in "${!PATCH_NAMES[@]}"; do
        if [[ "${PATCH_STATES[$i]}" == "on" ]]; then
            CLI_PATCH_ARGS+=("-e" "${PATCH_NAMES[$i]}")
        fi
    done

    # Maps API key injection piggybacks on the resource patch's stringOption.
    # Without it, tiles never render on sideloaded builds — Google locks the
    # bundled key to Meetup's production cert fingerprint.
    if [[ -n "$MAPS_KEY" ]]; then
        CLI_PATCH_ARGS+=("-O" "mapsKey=$MAPS_KEY")
        log "Maps API key: will be injected via the 'Inject Google Maps API key' patch"
    else
        warn "No Maps API key supplied. Pass --maps-key <KEY> or set MAPS_API_KEY=... or Maps will render blank."
        warn "Sideloading re-signs the APK with our keystore; Meetup's bundled key is locked to their production cert."
    fi
fi

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

# ── Patch (skipped in --sign-only: signing step re-signs the original) ──
PATCHED_APK="$WORK_DIR/patched-base.apk"
if $SIGN_ONLY; then
    cp "$BASE_APK" "$PATCHED_APK"
    log "Sign-only: copied $(basename "$BASE_APK") unchanged"
else
    log "Patching $(basename "$BASE_APK")..."

    java -jar "$REVANCED_CLI" patch \
        -p "$PATCHES_JAR" -b \
        -o "$PATCHED_APK" \
        --force \
        "${CLI_PATCH_ARGS[@]}" \
        "$BASE_APK" 2>&1 | while IFS= read -r line; do echo "    $line"; done

    [[ -f "$PATCHED_APK" ]] || err "Patched APK not produced"
    log "Patching complete"
fi

# ── Signing ────────────────────────────────────────────────────────
# Persistent keystore under $HOME so the cert fingerprint stays stable across
# patched builds: lets the user register the fingerprint against their own
# Google Maps API key once, and also lets future patched installs upgrade
# in-place instead of requiring an uninstall.
KEYSTORE_DIR="${APK_PATCH_KIT_HOME:-$HOME/.apk-patch-kit}"
KEYSTORE="$KEYSTORE_DIR/keystore.p12"
KS_PASS="revanced"
KS_ALIAS="key"

mkdir -p "$KEYSTORE_DIR"
if [[ ! -f "$KEYSTORE" ]]; then
    log "Generating persistent signing keystore at $KEYSTORE ..."
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -storepass "$KS_PASS" \
        -keypass "$KS_PASS" \
        -alias "$KS_ALIAS" \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -dname "CN=ReVanced" \
        2>/dev/null
else
    log "Using existing keystore: $KEYSTORE"
fi

# Emit SHA-1 + SHA-256 fingerprints. Users need SHA-1 to register this cert
# against Google Cloud restrictions on their own Maps API key.
KS_SHA1="$(keytool -list -v -keystore "$KEYSTORE" -storetype PKCS12 \
    -storepass "$KS_PASS" -alias "$KS_ALIAS" 2>/dev/null \
    | awk '/SHA1:/ {print $2; exit}')"
if [[ -n "$KS_SHA1" ]]; then
    echo -e "    ${DIM}Keystore cert SHA-1:${NC} $KS_SHA1"
    echo -e "    ${DIM}Register this fingerprint against your Google Cloud Maps API key (restriction: Android apps → com.<pkg> + this SHA-1).${NC}"
fi

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
    # The .apks filename is the package name (our add-app.sh writes it that
    # way). Print install + update lines separately:
    #   - First install: uninstall + install-multiple. Android refuses to
    #     replace an APK signed by one cert with one signed by another, so
    #     a Play-Store-built install must be removed first (data is wiped).
    #   - Subsequent updates: install-multiple alone — same persistent
    #     keystore means matching signatures, so the update keeps app data.
    # Separate lines (not chained with `;` / `&`) keep this paste-safe in
    # PowerShell too — PowerShell rejects `&` outright.
    PKG_NAME="$APK_BASENAME"
    INSTALL_TAIL="adb install-multiple -r -d"
    for apk in "$WORK_DIR/patched-splits"/*.apk; do
        INSTALL_TAIL="$INSTALL_TAIL \"$apk\""
    done
    log "First install (uninstall handles cert-mismatch against the Play Store build; ignore \"not installed\" if there's no prior copy):"
    echo "    adb uninstall $PKG_NAME"
    echo "    $INSTALL_TAIL"
    echo ""
    log "Subsequent updates (same keystore -> same signature -> in-place upgrade keeps app data):"
    echo "    $INSTALL_TAIL"

    if $INSTALL; then
        ADB="$(locate_adb)" || err "--install requested but no adb found. Pass --adb <path>."
        echo ""
        log "Auto-install via $ADB"
        if $REINSTALL; then
            log "  Uninstalling $PKG_NAME (data will be wiped) ..."
            "$ADB" uninstall "$PKG_NAME" || warn "  uninstall returned non-zero (likely 'not installed' — continuing)."
        fi
        # Translate paths for adb.exe on WSL.
        adb_split_args=()
        for apk in "$WORK_DIR/patched-splits"/*.apk; do
            adb_split_args+=("$(adb_local_path "$apk")")
        done
        log "  Installing ${#adb_split_args[@]} APK(s) ..."
        if "$ADB" install-multiple -r -d "${adb_split_args[@]}"; then
            log "  Installed."
        else
            rc=$?
            warn "  install-multiple failed (exit $rc)."
            if ! $REINSTALL; then
                warn "  If the failure was INSTALL_FAILED_UPDATE_INCOMPATIBLE / signature mismatch,"
                warn "  re-run with --reinstall (wipes app data) to replace the existing differently-signed copy."
            fi
            exit $rc
        fi
    fi
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
    log "Install with (-r/-d allow reinstall and downgrade; add 'adb uninstall <pkg>' first if the device has a differently-signed copy):"
    echo "    adb install -r -d \"$OUTPUT_APK\""

    if $INSTALL; then
        ADB="$(locate_adb)" || err "--install requested but no adb found. Pass --adb <path>."
        echo ""
        log "Auto-install via $ADB"
        # Single-APK path: we don't know the package name without parsing the
        # manifest. If the user passed --reinstall, we attempt uninstall via
        # the README-derived package (when --app was used). Otherwise we just
        # try the install and let it fail loudly on cert mismatch.
        if $REINSTALL; then
            if [[ -n "$PACKAGE" ]]; then
                log "  Uninstalling $PACKAGE (data will be wiped) ..."
                "$ADB" uninstall "$PACKAGE" || warn "  uninstall returned non-zero (likely 'not installed' — continuing)."
            else
                warn "  --reinstall set but no package name known (use --app or --package to enable uninstall)."
            fi
        fi
        log "  Installing $(basename "$OUTPUT_APK") ..."
        if "$ADB" install -r -d "$(adb_local_path "$OUTPUT_APK")"; then
            log "  Installed."
        else
            rc=$?
            warn "  install failed (exit $rc)."
            if ! $REINSTALL; then
                warn "  If the failure was INSTALL_FAILED_UPDATE_INCOMPATIBLE / signature mismatch,"
                warn "  re-run with --reinstall (wipes app data) to replace the existing differently-signed copy."
            fi
            exit $rc
        fi
    fi
fi

echo ""
