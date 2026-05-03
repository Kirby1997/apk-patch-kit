# strava

- **Package:** `com.strava`
- **Target version:** `460.9`
- **Patches source:** upstream `patches.rvp` from ReVanced - **no `patches/strava/` subproject in this repo**.

This app consumes the upstream ReVanced patches bundle directly. Drop a `patches-<ver>.rvp` at the repo root (download from `https://api.revanced.app/v5/patches.rvp`, check the current version at `https://api.revanced.app/v5/patches/version`), then run the patcher with `--patches`. The CLI only applies patches whose `compatibleWith` matches the APK's package.

> Scaffolded by `add-app.bat --app-only`. Re-running against the same package on any device produces the same layout.

## APKs

The `apks/` directory is git-ignored - APKs are the vendor's IP. Obtain them yourself (or re-run `add-app.bat --app-only --name strava com.strava` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `2cc602d278abc7d95dd821ba56785568e5c3c0e9df3bcb0b3ec452b3a1b97f3e` |
| `split_config.arm64_v8a.apk` | `f1d62d008ed47b0c8387f14c9e66b24e385b7bdd8137d7406e9262c72c226c22` |
| `split_config.en.apk` | `5d22c19bb89e07f2bcb4630c5cc126cc15048d6c13cf028c609bb4bc993fc3e1` |
| `split_config.xxhdpi.apk` | `c2ea53dd620c1e5fc399fec4cdb9e6a0479ac5376940c77f119782fefefb8f0a` |
| `com.strava.apks` | `de1bf8f3a05e672f164f648f0e75feeb8c98d09cd4de98b2f5850cd1cc361d10` |

## Applying patches

> Why no `:patches:strava` subproject? The upstream Strava patches depend on a full Android/DEX extension toolchain (`extensions/strava/` library + stubs + a shared `Utils` module) that isn't ported into this repo. Consuming the prebuilt `.rvp` is the path of least resistance — it carries every Strava patch the upstream maintains, already wired up to its extension code.

From the repo root:

```bash
# One-time: fetch the upstream bundle (check the current version at
# https://api.revanced.app/v5/patches/version).
curl -L -o patches.rvp https://api.revanced.app/v5/patches.rvp

./patch-apks.sh --app strava --patches patches.rvp
```

```cmd
REM Use curl.exe (not curl) because PowerShell aliases `curl` to
REM Invoke-WebRequest, which rejects curl flags.
curl.exe -L -o patches.rvp https://api.revanced.app/v5/patches.rvp

patch-apks.bat --app strava --patches patches.rvp
```

The interactive patch selector lists every patch in the bundle (hundreds). Type `n` to deselect all, then pick the Strava ones by number — the CLI only applies patches whose `compatibleWith` matches `com.strava` regardless, so leaving unrelated ones selected is harmless but slow.
