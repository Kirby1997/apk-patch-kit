# apk-patch-kit

ReVanced-compatible patches for Android apps, plus a one-shot driver that builds, applies, signs, and repackages the result.

The layout mirrors [ReVanced/revanced-patches](https://gitlab.com/ReVanced/revanced-patches) so patches from here can be lifted upstream with minimal surgery, but each target app lives in its own Gradle subproject so one broken fingerprint can't knock out the whole build.

## Layout

```
revanced-cli-*.jar        # Shared ReVanced CLI (at repo root)
patch-apks.sh             # Interactive driver: build → patch → sign → repack
build.gradle.kts          # Root Gradle
settings.gradle.kts       # Lists every :patches:<app> subproject
gradle/libs.versions.toml # Single source of truth for patcher/kotlin versions

patches/                  # One subproject per app
  <app>/
    build.gradle.kts
    src/main/kotlin/app/revanced/patches/<app>/...

apps/                     # One directory per app
  <app>/
    README.md             # Target version, SHA-256s, install notes
    apks/                 # Git-ignored — user supplies their own
```

Apps currently supported:

- [`hidratenow`](apps/hidratenow/README.md) — bypass login, disable license check, unlock premium

## Requirements

- JDK 17+
- `apksigner` (`sudo apt install apksigner`) — only for `.apks` bundles
- `keytool` (ships with the JDK)
- A GitHub personal access token with `read:packages` scope for Maven auth to ReVanced's GitHub Packages mirror. Set as env vars or in `~/.gradle/gradle.properties`:
  ```properties
  gprUser=<your-github-username>
  gprKey=<your-github-pat>
  ```

## Quick start

```bash
# Pick everything interactively
./patch-apks.sh

# Or target a specific app
./patch-apks.sh --app hidratenow

# Fully unattended (applies every patch)
./patch-apks.sh --app hidratenow --no-ui
```

Output APK/APKS lands in `build/`. The driver prints the correct `adb install` or `adb install-multiple` command when it finishes.

## APKs

APK binaries are not checked in — they're the vendor's IP. Each `apps/<app>/README.md` lists the target package, version, and SHA-256 of the files the patches were written against. Obtain them from a reputable mirror (APKMirror et al.) and place them in `apps/<app>/apks/`.

## Adding a new app

The scaffolding is automated by `add-app.sh`:

```bash
# Pull the APK from a connected device, extract version + SHA-256, wire everything up
./add-app.sh spotify com.spotify.music

# Or interactive — prompts to pick the package from third-party apps on the device
./add-app.sh spotify

# Just create the file tree without adb (fill in version/APKs later)
./add-app.sh --scaffold-only spotify com.spotify.music
```

The script pulls every APK returned by `pm path` (including all splits, bundled into a `.apks` zip), writes `apps/<app>/README.md` with the version + checksums, scaffolds the `patches/<app>/` Gradle subproject, and appends the `include` line to `settings.gradle.kts`. Then just drop `.kt` patch files into `patches/<app>/src/main/kotlin/app/revanced/patches/<app>/`.

**WSL note:** the Linux `adb` binary cannot see USB devices. `add-app.sh` detects WSL and prefers Windows `adb.exe` — install [Android Platform Tools on Windows](https://developer.android.com/tools/releases/platform-tools) and put `adb.exe` on your PATH (or pass `--adb <path>`).

When writing patches, fingerprint target methods by fully-qualified class type rather than opcode patterns — more robust against obfuscation changes — and declare `compatibleWith("<package>"("<version>"))` on every patch.

## Upstreaming

Each subproject is self-contained and uses the same patcher version as upstream, so a patch can be lifted to [ReVanced/revanced-patches](https://gitlab.com/ReVanced/revanced-patches) by moving the `.kt` file into their `patches/src/main/kotlin/app/revanced/patches/<app>/` tree and adding the same dependencies.
