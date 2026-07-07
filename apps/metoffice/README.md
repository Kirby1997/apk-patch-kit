# metoffice

- **Package:** `uk.gov.metoffice.weather.android`
- **Target version:** `3.40.0`
- **Patches module:** `:patches:metoffice`

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored - APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `2ada660d9e6abd06b559e69623e6758d67ac0aadbf4c15beff8f535697e2880f` |
| `split_config.arm64_v8a.apk` | `6a0d7340064ea7b866bb690f505f31810204d9f5795333ae24c66dbffd20910a` |
| `split_config.en.apk` | `83a38296deb16f1c1b27e88eb70faf7b7a3ce4015432bee7247b5f2646924164` |
| `split_config.xxhdpi.apk` | `69cb251e7c45dc8a8e5e10d4eb14ab69098e4a0dc23477b540e952b083562402` |
| `uk.gov.metoffice.weather.android.apks` | `3bc6e795795983018ef57f91ee3415ed6aedff3db9522e79fa68d4fa379640e7` |

## Applying patches

From the repo root:

```cmd
patch-apks.bat --app metoffice
```

## Writing patches

Place Kotlin patch files under `patches\metoffice\src\main\kotlin\app\revanced\patches\metoffice\`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("uk.gov.metoffice.weather.android"("3.40.0"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
