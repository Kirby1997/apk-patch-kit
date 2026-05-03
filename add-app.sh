#!/bin/bash
#
# add-app.sh — scaffold a new app subproject and (optionally) pull its APKs via adb.
#
# Usage:
#   ./add-app.sh                                    # Interactive: device + package, name auto-derived
#   ./add-app.sh <package>                          # Non-interactive package, name auto-derived
#   ./add-app.sh --name <shortname> [package]       # Force a shortname, skip aapt derivation
#   ./add-app.sh --scaffold-only --name <name> <pkg># Skip adb/aapt, just create files
#   ./add-app.sh --app-only                         # Scaffold apps/<name>/ only; no patches/<name>/
#   ./add-app.sh --adb <path>                       # Override adb binary location
#   ./add-app.sh --aapt <path>                      # Override aapt binary location
#
# The app shortname is derived from the APK's Application label (via aapt
# dump badging) so the same app always lands in the same apps/<name>/ directory
# regardless of who runs the script — preventing duplicate subprojects for
# the same package. Pass --name to override.
#
# On WSL, the Linux `adb` binary cannot see USB devices — this script prefers
# Windows `adb.exe` automatically. Same applies to `aapt.exe` from the Android
# SDK build-tools. Install Android Platform Tools + Build-Tools on Windows
# (https://developer.android.com/tools/releases/platform-tools) and make sure
# the binaries are on PATH (or pass --adb / --aapt).

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

# ── Args ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCAFFOLD_ONLY=false
APP_ONLY=false
ADB_OVERRIDE=""
AAPT_OVERRIDE=""
APP_NAME=""
APP_PACKAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scaffold-only) SCAFFOLD_ONLY=true; shift ;;
        --app-only)      APP_ONLY=true; shift ;;
        --adb)           ADB_OVERRIDE="$2"; shift 2 ;;
        --aapt)          AAPT_OVERRIDE="$2"; shift 2 ;;
        --name)          APP_NAME="$2"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        -*) err "Unknown flag: $1" ;;
        *)
            if [[ -z "$APP_PACKAGE" ]]; then
                APP_PACKAGE="$1"
            else
                err "Unexpected positional argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate any user-supplied --name upfront.
if [[ -n "$APP_NAME" && ! "$APP_NAME" =~ ^[a-z][a-z0-9]*$ ]]; then
    err "--name must match ^[a-z][a-z0-9]*\$ (lowercase letters and digits, leading letter). Got: $APP_NAME"
fi

if $SCAFFOLD_ONLY; then
    [[ -n "$APP_NAME" ]]    || err "--scaffold-only requires --name <shortname> (no APK to derive from)."
    [[ -n "$APP_PACKAGE" ]] || err "--scaffold-only requires a <package> positional argument."
fi

SETTINGS_FILE="$SCRIPT_DIR/settings.gradle.kts"
[[ -f "$SETTINGS_FILE" ]] || err "Root settings.gradle.kts not found — are you running this from the repo root?"

# ── Locate adb ──────────────────────────────────────────────────────
# On WSL, Linux adb can't see USB devices. Prefer adb.exe.
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
                    "/mnt/c/Program Files (x86)/Android/Sdk/platform-tools"; do
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

# ── Locate aapt ─────────────────────────────────────────────────────
# aapt ships in the Android SDK build-tools (versioned subdirs). We pick the
# lexicographically-highest version so newer devices work. Prefer aapt.exe on WSL.
locate_aapt() {
    [[ -n "$AAPT_OVERRIDE" ]] && { echo "$AAPT_OVERRIDE"; return 0; }

    local is_wsl=false
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then
        is_wsl=true
    fi

    if $is_wsl; then
        if command -v aapt.exe >/dev/null 2>&1; then
            command -v aapt.exe
            return 0
        fi
        # Scan build-tools/*/aapt.exe under each SDK location, pick newest version.
        local best=""
        for base in /mnt/c/Users/*/AppData/Local/Android/Sdk/build-tools \
                    "/mnt/c/Program Files/Android/Sdk/build-tools" \
                    "/mnt/c/Program Files (x86)/Android/Sdk/build-tools"; do
            [[ -d "$base" ]] || continue
            while IFS= read -r cand; do
                [[ -x "$cand" ]] && best="$cand"
            done < <(find "$base" -maxdepth 2 -name 'aapt.exe' -type f 2>/dev/null | sort)
        done
        [[ -n "$best" ]] && { echo "$best"; return 0; }
    fi

    if command -v aapt >/dev/null 2>&1; then
        command -v aapt
        return 0
    fi
    if command -v aapt2 >/dev/null 2>&1; then
        # aapt2 dump badging has a slightly different output format but
        # exposes the same application-label line we care about.
        command -v aapt2
        return 0
    fi
    return 1
}

ADB=""
if ! $SCAFFOLD_ONLY; then
    ADB=$(locate_adb || true)
    if [[ -z "$ADB" ]]; then
        err "adb not found. Install Android Platform Tools or pass --adb <path>. \
For --scaffold-only mode, also pass --name <shortname>."
    fi
    log "Using adb: $ADB"
    # WSL + adb.exe quirks:
    #  1. A piped adb call (e.g. `adb.exe devices | awk …`) that also spawns
    #     the daemon leaves the pipe FDs open forever — reader never sees EOF.
    #     Pre-start the daemon with stdio fully detached so later calls are
    #     pure short-lived clients.
    #  2. The first adb.exe run can block on a Windows Firewall prompt that is
    #     invisible to a WSL-side pipe. Bound by `timeout` so a stuck prompt
    #     surfaces as a script failure rather than an indefinite hang.
    if ! timeout 10 "$ADB" start-server </dev/null >/dev/null 2>&1; then
        err "adb start-server timed out. Likely a Windows Firewall prompt on first run — \
open PowerShell, run 'adb.exe start-server', accept the prompt, then re-run this script."
    fi
fi

# ── Device selection + package resolution ───────────────────────────
DEVICE_SERIAL=""
APP_VERSION=""
APK_DEVICE_PATHS=()

if ! $SCAFFOLD_ONLY; then
    # `adb devices` output includes a header and blank trailing line.
    # adb.exe on Windows uses CRLF — strip \r *before* awk, or $2 is "device\r"
    # and never matches the "device" literal we're filtering for.
    DEVICES=$("$ADB" devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}')
    DEVICE_COUNT=$(echo "$DEVICES" | grep -c . || true)

    if [[ "$DEVICE_COUNT" -eq 0 ]]; then
        err "No authorised devices connected. Unlock the device and authorise USB debugging, \
or pass --scaffold-only --name <shortname> <package> to scaffold without a device."
    elif [[ "$DEVICE_COUNT" -eq 1 ]]; then
        DEVICE_SERIAL="$DEVICES"
        log "Device: $DEVICE_SERIAL"
    else
        echo ""
        echo -e "${BOLD}Multiple devices connected — select one:${NC}"
        mapfile -t DEVICE_LIST <<<"$DEVICES"
        for i in "${!DEVICE_LIST[@]}"; do
            echo -e "  ${CYAN}$((i+1))${NC}) ${DEVICE_LIST[$i]}"
        done
        read -rp "  Select [1]: " idx
        idx="${idx:-1}"
        DEVICE_SERIAL="${DEVICE_LIST[$((idx-1))]}"
        log "Device: $DEVICE_SERIAL"
    fi
fi

adb_cmd() { "$ADB" -s "$DEVICE_SERIAL" "$@"; }

# Convert a local Linux path to the form adb expects.
# adb.exe is a Windows binary and requires a Windows path (C:\...) for its
# local-filesystem arguments — WSL interop does not auto-translate.
adb_local_path() {
    if [[ "$ADB" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# Same idea for aapt.exe — it'll be reading the pulled base.apk which lives in a
# WSL temp path. aapt.exe won't accept /mnt/c/... without translation.
aapt_local_path() {
    if [[ "$AAPT" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$1"
    else
        printf '%s\n' "$1"
    fi
}

# If the user didn't pass a package name, interactively pick from installed apps.
if ! $SCAFFOLD_ONLY && [[ -z "$APP_PACKAGE" ]]; then
    log "Listing user-installed packages on device..."
    # -3 = third-party only (skip system apps, far too many to scroll through)
    mapfile -t PACKAGES < <(adb_cmd shell pm list packages -3 | sed 's/^package://' | tr -d '\r' | sort)

    if [[ ${#PACKAGES[@]} -eq 0 ]]; then
        err "No third-party packages found on device."
    fi

    echo ""
    echo -e "${BOLD}Installed packages (type to filter, or number to pick):${NC}"
    echo ""
    for i in "${!PACKAGES[@]}"; do
        echo -e "  ${CYAN}$((i+1))${NC}) ${PACKAGES[$i]}"
    done
    echo ""

    while true; do
        read -rp "  Package or index: " sel
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#PACKAGES[@]} )); then
            APP_PACKAGE="${PACKAGES[$((sel-1))]}"
            break
        elif [[ -n "$sel" ]]; then
            # Treat as a literal package name (must match something installed).
            for p in "${PACKAGES[@]}"; do
                [[ "$p" == "$sel" ]] && { APP_PACKAGE="$p"; break 2; }
            done
            warn "Not found: $sel. Try again."
        fi
    done
fi

# Validate package looks like a real Android package.
if [[ -n "$APP_PACKAGE" && ! "$APP_PACKAGE" =~ ^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$ ]]; then
    err "Package name looks invalid: $APP_PACKAGE"
fi

# ── Pull APKs to a staging tmpdir ───────────────────────────────────
# We don't know the final apps/<name>/ directory yet — the name is derived
# from aapt after we have base.apk locally. Pull into a tmpdir first, then
# move into place once the name is known.
PULL_TMP=""
PULLED_APKS=()
BASE_APK_LOCAL=""

cleanup_tmp() {
    [[ -n "$PULL_TMP" && -d "$PULL_TMP" ]] && rm -rf "$PULL_TMP"
}
trap cleanup_tmp EXIT

if ! $SCAFFOLD_ONLY; then
    log "Resolving APK paths for $APP_PACKAGE..."
    mapfile -t PATH_LINES < <(adb_cmd shell pm path "$APP_PACKAGE" | tr -d '\r')

    if [[ ${#PATH_LINES[@]} -eq 0 ]]; then
        err "Package $APP_PACKAGE not installed on device."
    fi

    for line in "${PATH_LINES[@]}"; do
        APK_DEVICE_PATHS+=("${line#package:}")
    done

    log "Found ${#APK_DEVICE_PATHS[@]} APK(s) on device"

    APP_VERSION=$(adb_cmd shell dumpsys package "$APP_PACKAGE" \
        | grep -m1 versionName \
        | sed -E 's/.*versionName=([^ ]+).*/\1/' \
        | tr -d '\r' || true)
    [[ -n "$APP_VERSION" ]] && log "Version: $APP_VERSION"

    PULL_TMP=$(mktemp -d -t add-app.XXXXXX)
    for remote in "${APK_DEVICE_PATHS[@]}"; do
        local_name=$(basename "$remote")
        local_dest="$PULL_TMP/$local_name"
        log "  Pulling $local_name..."
        adb_cmd pull "$remote" "$(adb_local_path "$local_dest")" >/dev/null
        PULLED_APKS+=("$local_dest")
        # First APK in pm path output is conventionally the base; also detect
        # explicitly by filename so split-first orderings don't trip us.
        if [[ -z "$BASE_APK_LOCAL" && "$local_name" == "base.apk" ]]; then
            BASE_APK_LOCAL="$local_dest"
        fi
    done
    # Fallback: if no file is literally named "base.apk" (rare), use the first.
    [[ -z "$BASE_APK_LOCAL" ]] && BASE_APK_LOCAL="${PULLED_APKS[0]}"
fi

# ── Derive APP_NAME from APK application-label via aapt ─────────────
AAPT=""
if [[ -z "$APP_NAME" && ! $SCAFFOLD_ONLY ]]; then
    AAPT=$(locate_aapt || true)
    if [[ -z "$AAPT" ]]; then
        err "aapt not found — cannot auto-derive app shortname. Install Android SDK \
build-tools, pass --aapt <path>, or pass --name <shortname> explicitly."
    fi
    log "Using aapt: $AAPT"

    # Capture stderr too so we can surface aapt errors on failure (some older
    # build-tools aapt builds can't parse newer APKs and fail silently if 2>/dev/null).
    BADGING=$("$AAPT" dump badging "$(aapt_local_path "$BASE_APK_LOCAL")" 2>&1 || true)

    # Prefer bare `application-label:'...'` — Android picks this as the canonical
    # label when the device locale has no localized override. Fall back to any
    # locale-suffixed variant (`application-label-en:'...'`, etc.), since some
    # APKs only emit localized labels. Final fallback: last component of the
    # package name (`com.strava` → `strava`), because a derived name is always
    # better than a hard error for users who just want to scaffold.
    derived_from=""
    RAW_LABEL=$(echo "$BADGING" | awk -F"'" '/^application-label:/{print $2; exit}')
    [[ -n "$RAW_LABEL" ]] && derived_from="application-label"

    if [[ -z "$RAW_LABEL" ]]; then
        RAW_LABEL=$(echo "$BADGING" | awk -F"'" '/^application-label-[a-zA-Z0-9-]+:/{print $2; exit}')
        [[ -n "$RAW_LABEL" ]] && derived_from="localized application-label"
    fi

    if [[ -z "$RAW_LABEL" ]]; then
        warn "No application-label line in aapt output. First 10 lines:"
        echo "$BADGING" | head -10 | sed 's/^/    /' >&2
        if [[ -n "$APP_PACKAGE" ]]; then
            RAW_LABEL="${APP_PACKAGE##*.}"
            derived_from="package name suffix"
            warn "Falling back to package name suffix: '$RAW_LABEL'"
        else
            err "aapt produced no application-label for $BASE_APK_LOCAL and no package name \
is available as fallback. Pass --name <shortname> to override."
        fi
    fi

    # Sanitize: lowercase, strip everything not a-z0-9. If the result starts
    # with a digit (e.g. "9gag" → "9gag"), prefix with 'a' to satisfy the
    # leading-letter rule. Empty result (label was all symbols) → error.
    SANITIZED=$(echo "$RAW_LABEL" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    if [[ -z "$SANITIZED" ]]; then
        err "Could not derive a valid shortname from '$RAW_LABEL' (source: $derived_from). Pass --name <shortname>."
    fi
    if [[ ! "$SANITIZED" =~ ^[a-z] ]]; then
        SANITIZED="a$SANITIZED"
    fi

    APP_NAME="$SANITIZED"
    log "Derived shortname '$APP_NAME' from $derived_from '$RAW_LABEL'"
fi

# Final validation (covers both user-supplied and derived names).
[[ -n "$APP_NAME" ]] || err "APP_NAME is unset — this should not happen."
if [[ ! "$APP_NAME" =~ ^[a-z][a-z0-9]*$ ]]; then
    err "Derived shortname '$APP_NAME' is invalid. Pass --name <shortname> to override."
fi

APP_DIR="$SCRIPT_DIR/apps/$APP_NAME"
PATCHES_DIR="$SCRIPT_DIR/patches/$APP_NAME"

[[ ! -d "$APP_DIR" ]]     || err "apps/$APP_NAME already exists — this app has been scaffolded before. \
Remove it first if you want to recreate, or use --name <other> for a variant."
if ! $APP_ONLY; then
    [[ ! -d "$PATCHES_DIR" ]] || err "patches/$APP_NAME already exists. Remove it first if you want to recreate."
fi

# ── Move staged APKs into place ─────────────────────────────────────
mkdir -p "$APP_DIR/apks"
FINAL_APKS=()
if ! $SCAFFOLD_ONLY; then
    for src in "${PULLED_APKS[@]}"; do
        base=$(basename "$src")
        mv "$src" "$APP_DIR/apks/$base"
        FINAL_APKS+=("$APP_DIR/apks/$base")
    done

    # If more than one APK, bundle them into a .apks zip for the patcher driver.
    if [[ ${#FINAL_APKS[@]} -gt 1 ]]; then
        BUNDLE="$APP_DIR/apks/$APP_PACKAGE.apks"
        log "Assembling .apks bundle: $(basename "$BUNDLE")"
        (cd "$APP_DIR/apks" && \
            rm -f "$BUNDLE" && \
            jar cMf "$BUNDLE" $(printf '%s ' "${FINAL_APKS[@]##*/}"))
    fi
fi

# ── Compute SHA-256s for README ─────────────────────────────────────
SHA_LINES=""
if [[ -d "$APP_DIR/apks" ]]; then
    while IFS= read -r f; do
        sha=$(sha256sum "$f" | awk '{print $1}')
        SHA_LINES+="| \`$(basename "$f")\` | \`$sha\` |"$'\n'
    done < <(find "$APP_DIR/apks" -maxdepth 1 -type f \( -name '*.apk' -o -name '*.apks' \) | sort)
fi

# ── Scaffold patches subproject ─────────────────────────────────────
# Skipped under --app-only: the app consumes an upstream patches bundle
# (patches-*.rvp at repo root) via patch-apks.sh --patches <file>, so no
# local Gradle subproject is needed.
if ! $APP_ONLY; then
    log "Scaffolding patches/$APP_NAME ..."
    KT_DIR="$PATCHES_DIR/src/main/kotlin/app/revanced/patches/$APP_NAME"
    mkdir -p "$KT_DIR"

    cat >"$PATCHES_DIR/build.gradle.kts" <<EOF
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    implementation(libs.revanced.patcher)
    implementation(libs.smali)
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.addAll("-Xcontext-receivers", "-Xskip-prerelease-check")
    }
}

tasks.jar {
    archiveBaseName.set("$APP_NAME-patches")
}
EOF

    touch "$KT_DIR/.gitkeep"
fi

# ── Scaffold apps/<name>/README.md ──────────────────────────────────
log "Scaffolding apps/$APP_NAME/README.md ..."
if $APP_ONLY; then
    cat >"$APP_DIR/README.md" <<EOF
# $APP_NAME

- **Package:** \`${APP_PACKAGE:-TODO-fill-in}\`
- **Target version:** \`${APP_VERSION:-TODO-fill-in}\`
- **Patches source:** upstream \`patches.rvp\` from ReVanced — **no \`patches/$APP_NAME/\` subproject in this repo**.

This app consumes the upstream ReVanced patches bundle directly. Drop a \`patches-<ver>.rvp\` at the repo root (download from \`https://api.revanced.app/v5/patches.rvp\`, check the current version at \`https://api.revanced.app/v5/patches/version\`), then run the patcher with \`--patches\`. The CLI only applies patches whose \`compatibleWith\` matches the APK's package, so unrelated patches in the bundle are a no-op at apply time.

> Scaffolded by \`add-app.sh --app-only\`. Re-running against the same package on any device produces the same layout.

## APKs

The \`apks/\` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself (or re-run \`add-app.sh --app-only --name $APP_NAME $APP_PACKAGE\` against a device that has the app installed) and place them in \`apks/\`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
${SHA_LINES:-| TODO | TODO |}

## Applying patches

From the repo root:

\`\`\`bash
# One-time: fetch the upstream bundle
curl -L -o patches.rvp https://api.revanced.app/v5/patches.rvp

./patch-apks.sh --app $APP_NAME --patches patches.rvp
\`\`\`

The interactive patch selector lists every patch in the bundle (hundreds). Type \`n\` to deselect all, then pick the ones for this app by number.
EOF
else
    cat >"$APP_DIR/README.md" <<EOF
# $APP_NAME

- **Package:** \`${APP_PACKAGE:-TODO-fill-in}\`
- **Target version:** \`${APP_VERSION:-TODO-fill-in}\`
- **Patches module:** \`:patches:$APP_NAME\`

> Scaffolded by \`add-app.sh\` / \`add-app.bat\`, which pulled the APK (and any splits) from a connected device via \`adb pull\`. Re-running the script on a different device with the same package produces the same \`apps/<name>/\` layout.

## APKs

The \`apks/\` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run \`add-app.sh\` against a device that has the app installed) and place them in \`apks/\`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
${SHA_LINES:-| TODO | TODO |}

## Applying patches

From the repo root:

\`\`\`bash
./patch-apks.sh --app $APP_NAME
\`\`\`

## Writing patches

Place Kotlin patch files under \`${PATCHES_DIR#"$SCRIPT_DIR"/}/src/main/kotlin/app/revanced/patches/$APP_NAME/\`. Each patch should:

- Use the \`bytecodePatch { ... }\` DSL
- Declare \`compatibleWith("${APP_PACKAGE:-TODO}"("${APP_VERSION:-TODO}"))\`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
EOF
fi

# ── Wire into settings.gradle.kts ───────────────────────────────────
# Skipped under --app-only: there's no Gradle subproject to register.
if ! $APP_ONLY; then
    if grep -qE "^include\(\":patches:$APP_NAME\"\)" "$SETTINGS_FILE"; then
        log "settings.gradle.kts already includes :patches:$APP_NAME"
    else
        log "Adding :patches:$APP_NAME to settings.gradle.kts ..."
        printf 'include(":patches:%s")\n' "$APP_NAME" >>"$SETTINGS_FILE"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
log "Done."
echo ""
echo -e "  ${BOLD}App:${NC}         $APP_NAME"
echo -e "  ${BOLD}Package:${NC}     ${APP_PACKAGE:-(not set — edit apps/$APP_NAME/README.md)}"
echo -e "  ${BOLD}Version:${NC}     ${APP_VERSION:-(not set — edit apps/$APP_NAME/README.md)}"
if ! $APP_ONLY; then
    echo -e "  ${BOLD}Patches:${NC}     $(realpath --relative-to="$SCRIPT_DIR" "$PATCHES_DIR")/"
fi
echo -e "  ${BOLD}APKs:${NC}        $(realpath --relative-to="$SCRIPT_DIR" "$APP_DIR")/apks/"
echo ""
echo -e "  ${DIM}Next:${NC}"
if $APP_ONLY; then
    echo -e "  ${DIM}  1. Download upstream bundle: curl -L -o patches.rvp https://api.revanced.app/v5/patches.rvp${NC}"
    echo -e "  ${DIM}  2. Run: ./patch-apks.sh --app $APP_NAME --patches patches.rvp${NC}"
else
    echo -e "  ${DIM}  1. Drop .kt patch files under patches/$APP_NAME/src/main/kotlin/app/revanced/patches/$APP_NAME/${NC}"
    echo -e "  ${DIM}  2. Run: ./gradlew :patches:$APP_NAME:build${NC}"
    echo -e "  ${DIM}  3. Run: ./patch-apks.sh --app $APP_NAME${NC}"
fi
echo ""
