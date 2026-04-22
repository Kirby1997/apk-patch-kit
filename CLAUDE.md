# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A **multi-app ReVanced patches repo** with a one-shot bash driver that builds, applies, signs, and repackages the result for sideloading. Layout mirrors [ReVanced/revanced-patches](https://gitlab.com/ReVanced/revanced-patches) so patches written here are liftable upstream, but each target app is its own Gradle subproject (produces its own jar) so one broken fingerprint can't knock out the build for unrelated apps.

Currently targets:
- **HidrateNow** v4.6.9 (`hidratenow.com.hidrate.hidrateandroid`) — bypass login, disable Google Play license check, unlock premium

## Environment

- **Host:** Windows 10/11 with WSL2 (Debian). Repo lives on the Windows drive at `/mnt/c/Users/Jacob/Documents/Claude APK decompiling and patching/` and all scripts run from WSL.
- **JDK:** 17 (Debian `openjdk-17-jdk`). `./gradlew` uses JVM 17 toolchain.
- **Bash scripts run from WSL**, but `adb.exe` is the **Windows** binary (typically `/mnt/c/ProgramData/chocolatey/bin/adb.exe`). Linux-native `adb` inside WSL cannot see USB devices without `usbipd`, which is not set up here.
- **GitHub Packages auth** is required for the `revanced-patcher` dep. Store `gprUser` + `gprKey` (a PAT with `read:packages`) in `~/.gradle/gradle.properties`, or export `GITHUB_ACTOR` + `GITHUB_TOKEN`. 401s during Gradle builds almost always mean these are missing or expired.
- **apksigner** is required for `.apks` signing. On WSL: `sudo apt install apksigner`. On Windows, `patch-apks.bat` looks on PATH first, then falls back to scanning `%ANDROID_HOME%`, `%ANDROID_SDK_ROOT%`, and `%LOCALAPPDATA%\Android\Sdk` for `build-tools\*\apksigner.bat` (newest version wins). Installing Android Studio is enough; no PATH edit needed.

## Layout

```
revanced-cli-*.jar              # Shared ReVanced CLI at repo root
patch-apks.sh                   # Driver: build → patch → sign → repack
add-app.sh                      # Scaffold a new app subproject + adb-pull its APKs
build.gradle.kts                # Root Gradle
settings.gradle.kts             # Registers each :patches:<app> subproject
gradle/libs.versions.toml       # Single source of truth (patcher, kotlin, smali)

patches/<app>/                  # One Gradle subproject per app
  build.gradle.kts              # Sets archiveBaseName to "<app>-patches"
  src/main/kotlin/app/revanced/patches/<app>/<category>/<Patch>.kt

apps/<app>/                     # One directory per app
  README.md                     # Target package+version, SHA-256s, install notes
  apks/                         # Git-ignored — user supplies their own APK/APKS
  decompiled-apktool/           # Git-ignored reference dumps (optional)
  decompiled-jadx/              # Git-ignored reference dumps (optional)
```

APK binaries, build outputs, decompiled dumps, and signing artefacts are all `.gitignore`d. See `.gitignore` for the full list.

## Commands

All commands run from the repo root.

```bash
# Scaffold a new app, pull APKs from device, fill in version + SHA-256.
# Shortname is derived from the APK's Application label via aapt — same package
# always lands in the same apps/<name>/ directory regardless of who runs it.
./add-app.sh                                 # Fully interactive (device + package)
./add-app.sh <package>                       # Non-interactive package, name auto-derived
./add-app.sh --name <shortname> [package]    # Force a shortname, skip aapt derivation
./add-app.sh --scaffold-only --name <n> <pkg>  # Skip adb/aapt, just create files
./add-app.sh --adb <path>                    # Override adb.exe binary location
./add-app.sh --aapt <path>                   # Override aapt.exe binary location

# Build a single app's patches jar
./gradlew :patches:<app>:build

# Build every app's patches jar
./gradlew build

# Apply patches to APK/APKS, sign, repackage
./patch-apks.sh                       # Fully interactive (pick app → pick APK → pick patches)
./patch-apks.sh --app <app>           # Pre-selects the app's patches jar + apks/ dir
./patch-apks.sh --app <app> --no-ui   # Apply every patch, no prompts
```

Output lands in `build/<name>-patched.apks` (or `-patched.apk` for single APKs). The driver prints the correct `adb install-multiple` or `adb install` command on completion.

## Workflows

### Adding a new app end-to-end

1. Connect device via USB, unlock, accept any adb auth prompt. Verify from **a Windows terminal** (not WSL):
   ```powershell
   adb.exe devices      # should show "<serial>  device"
   ```
2. From WSL repo root: `./add-app.sh` (no args needed — interactive pick, name auto-derived)
3. Script output flow:
   - Detects `adb.exe` via `locate_adb` (WSL check + common SDK paths)
   - Pre-starts the daemon: `adb.exe start-server </dev/null >/dev/null 2>&1` with a 10s timeout
   - Detects `aapt.exe` via `locate_aapt` (scans SDK build-tools/*/aapt.exe, picks newest version) — skipped if `--name` was given
   - Runs `adb.exe devices` (stripping `\r` before awk-filtering — critical on Windows adb output)
   - If no package arg, runs `pm list packages -3` (third-party only) and prompts for one
   - Runs `pm path <pkg>` to get every APK (base + splits)
   - Pulls each via `adb pull` into a **tmpdir** first (path converted with `wslpath -w`) — the final `apps/<name>/` dir isn't known yet
   - Runs `aapt dump badging base.apk`, parses the first `application-label:'...'`, lowercases and strips non-alphanumeric → that's the shortname. Example: `Hidrate Spark` → `hidratespark`. Leading digit gets an `a` prefix. Duplicate detection fires if `apps/<derived>/` already exists.
   - Moves APKs from tmpdir → `apps/<name>/apks/`; if >1 APK, bundles into `apps/<name>/apks/<pkg>.apks` via `jar cMf`
   - Extracts version via `dumpsys package <pkg> | grep versionName`
   - Computes SHA-256 on every pulled APK
   - Writes `patches/<name>/build.gradle.kts` (with `archiveBaseName = "<name>-patches"`), empty Kotlin source tree with `.gitkeep`, and `apps/<name>/README.md` with package/version/SHA-256 pre-filled
   - Appends `include(":patches:<name>")` to `settings.gradle.kts` (idempotent)
4. Decompile for target-class discovery (optional but usually necessary):
   ```bash
   cd apps/<name>
   apktool d apks/base.apk -o decompiled-apktool
   jadx -d decompiled-jadx apks/base.apk
   ```
5. Write `.kt` patch files under `patches/<name>/src/main/kotlin/app/revanced/patches/<name>/<category>/`
6. Build: `./gradlew :patches:<name>:build`
7. Apply: `./patch-apks.sh --app <name>`
8. Install per the driver's printout: `adb install-multiple build/patch-work/patched-splits/*.apk`

### Writing a patch (template)

Every patch file should have this shape. See `patches/hidratenow/` for three working examples.

```kotlin
package app.revanced.patches.<app>.<category>

import app.revanced.patcher.extensions.InstructionExtensions.addInstructions
import app.revanced.patcher.fingerprint
import app.revanced.patcher.patch.bytecodePatch
import com.android.tools.smali.dexlib2.AccessFlags

val <name>Fingerprint = fingerprint {
    accessFlags(AccessFlags.PUBLIC)
    returns("Z")
    parameters()
    custom { method, classDef ->
        classDef.type == "L<package/slash/path>;" && method.name == "<methodName>"
    }
}

@Suppress("unused")
val <name>Patch = bytecodePatch(
    name = "<Human-readable patch name>",
    description = "<What this does, user-facing>",
) {
    compatibleWith("<package>"("<version>"))

    execute {
        <name>Fingerprint.method.addInstructions(
            0,
            """
                const/4 v0, 0x1
                return v0
            """,
        )
    }
}
```

Key conventions:
- Fingerprint on **class type + method name + signature**, never on opcode patterns. Types survive obfuscation better than instruction sequences.
- Always declare `compatibleWith("<package>"("<version>"))`. Omitting it means the patch silently no-ops against other versions.
- For `return true`/`return false`/`return-void` patches, prepend the `const/4`+`return` at offset 0 and leave the original body as dead code — simplest, most robust.
- Only fully rewrite a method when the original flow is incompatible (see `BypassLoginPatch.kt` — replaces `NoDisplayActivity.onCreate` to forward straight to `MainActivity`).

## Architecture

### Patching pipeline (`patch-apks.sh`)

The driver does five things in order — if something breaks, identify which stage:

1. **Resolve inputs** — locates `revanced-cli-*.jar` at the repo root; resolves the app either from `--app`, an interactive picker over `apps/*`, or explicit `--patches`/`--apk` flags. For an app, it auto-finds `patches/<app>/build/libs/*.jar` and `apps/<app>/apks/`.
2. **Enumerate patches** — runs `revanced-cli list-patches -p <jar> -b` and parses `Name: <patch>` lines from the output. Earlier versions abused `patch -b --force` with the jar as its own "APK" input as a dry-run trick; patcher 22+ crashes inside `ResourcesDecoder` before any patches load, so that path no longer works and was removed.
3. **Extract & patch** — `.apks` is unzipped to `build/patch-work/extracted/`; only `base.apk` is patched (splits carry no code). Patches are passed via repeated `-e "<Name>"` with `--exclusive` so deselected patches never run even if marked default-enabled.
4. **Sign consistently** — a fresh PKCS12 keystore is generated per run at `build/patch-work/sign.p12` (pass `revanced`). **Every** APK in a bundle (base + all `split_*.apk`) is signed with the same key — Android rejects bundles whose splits have different signing identities.
5. **Repackage** — splits are `jar cMf`'d back into `build/<name>-patched.apks`. Original inputs are never modified.

`--exclusive` on the CLI is load-bearing: without it, any patch marked default-enabled in the jar would run even when deselected in the UI.

### Scaffolding pipeline (`add-app.sh`)

Implements the flow above. Three WSL-specific fixes are embedded in the script — **do not remove them without cause**:

1. **Pre-start the adb daemon with fully detached stdio**, guarded by `timeout 10`:
   ```bash
   timeout 10 "$ADB" start-server </dev/null >/dev/null 2>&1
   ```
   Without this, the first piped call (`adb.exe devices | awk ...`) spawns the daemon, the daemon inherits the pipe's file descriptors, and the reader never sees EOF → the script hangs forever. The timeout catches the other failure mode: a Windows Firewall prompt on first run that's invisible from WSL and would otherwise block indefinitely.

2. **Strip `\r` before awk-filtering `adb devices` output.** `adb.exe` emits CRLF, so `awk 'NR>1 && $2=="device" {print $1}'` matches `device\r` against `device` and fails silently, producing an empty device list:
   ```bash
   "$ADB" devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}'
   ```

3. **Convert local paths via `wslpath -w` before passing them to `adb.exe`.** Windows binaries do not auto-translate `/mnt/c/...` arguments; `adb pull /sdcard/x /mnt/c/...` fails with "cannot create file/directory". `adb_local_path()` in the script handles this and is a no-op for Linux-native adb:
   ```bash
   adb_cmd pull "$remote" "$(adb_local_path "$local_dest")"
   ```

### Gradle multi-module

- Root `build.gradle.kts` declares the Kotlin plugin with `apply false` — not applied at root, each subproject applies it.
- Each `patches/<app>/build.gradle.kts` applies Kotlin JVM, depends on `libs.revanced.patcher` + `libs.smali`, targets JVM 17, and sets `archiveBaseName` so jars land at `patches/<app>/build/libs/<app>-patches.jar`.
- `gradle/libs.versions.toml` is the single source of truth — bump `revanced-patcher` there and every subproject follows.

## WSL/adb troubleshooting

If adb suddenly stops seeing the device (both WSL and Windows showing empty device lists):

1. **Kill every adb daemon first** — multiple servers fighting over tcp:5037 is common after an interrupted run:
   ```bash
   # From WSL
   pkill -f adb.exe 2>/dev/null
   "$(command -v adb.exe)" kill-server 2>/dev/null
   ```
2. **Check USB mode on the phone.** Pull down the notification shade, tap the USB notification, switch to **File Transfer (MTP)**. Many phones suppress the ADB auth popup in charge-only mode.
3. **Check the cable.** Charge-only USB-C cables have no data lines. Swap to one known to do file transfer.
4. **Confirm Developer options + USB debugging are still enabled** — some OEM skins reset these when you revoke trusted devices.
5. **Start the daemon from PowerShell, not WSL, on first run.** Windows Firewall will prompt for `adb.exe` and the prompt is invisible if the call was backgrounded in a WSL pipe. From PowerShell: `adb.exe start-server; adb.exe devices`. Accept the firewall prompt.
6. If script hangs with no output, you probably have a stopped job in the shell — `jobs -l`, then `kill %1 %2 ...`.

## Gotchas

- **Do not remove the three WSL fixes in `add-app.sh`** (pre-start detach, `\r` strip, `wslpath -w`). Each was debugged after a reproducible hang or silent failure.
- **Patches are version-pinned** via `compatibleWith(...)`. A new app release will break every fingerprint that anchors on a renamed obfuscated class — expect to re-decompile and update the `L...;` type strings.
- **`.apks` bundles need `adb install-multiple`**, not `adb install`. All splits must share a signing identity — `patch-apks.sh` signs every split with the same per-run keystore.
- **APKs are `.gitignore`d** on purpose — not the repo's IP to redistribute. Per-app READMEs carry the expected version + SHA-256 so anyone cloning the repo knows exactly what to fetch.
- **Do not commit `revanced-cli-*.jar` if upstreaming.** ReVanced upstream expects consumers to download the CLI themselves. For a self-hosted repo it's convenient to keep; uncomment the matching line in `.gitignore` to exclude.

## Target classes (HidrateNow v4.6.9)

Anchor points for the current patches — obfuscation on this APK is light and names are stable:

- **Login gate:** `hidratenow.com.hidrate.hidrateandroid.activities.NoDisplayActivity#onCreate`, `parse.User#needsToUpdateUserParams`
- **License check:** `com.pairip.licensecheck.LicenseContentProvider#onCreate`, `LicenseClient#initializeLicenseCheck`, `LicenseClient$1#run`
- **Billing:** `com.hidrate.iap.BillingRepository#getIfUserHasPremium`, `com.hidrate.iap.localdb.GlowStudioEntitlement#isPurchased`

## Upstreaming patches

Each subproject is self-contained and pins the same patcher version as ReVanced upstream. To contribute a patch, move the `.kt` file into their `patches/src/main/kotlin/app/revanced/patches/<app>/` tree and match their `build.gradle.kts` conventions — the patch source itself shouldn't need changes.
