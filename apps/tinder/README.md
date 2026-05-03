# tinder

- **Package:** `com.tinder`
- **Target version:** `17.15.0`
- **Patches module:** `:patches:tinder`

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored - APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `4c99ba809b43588736c2f2be55c57a7138d1759e195607a17b1c8b2cb5101275` |
| `com.tinder.apks` | `86390ad619a9d6ef359d048938102c41de5d621b4cdae0916c7f78c19e98dd92` |
| `split_config.arm64_v8a.apk` | `fe02720b7c98e5165f5ebbdb39694d33221a915f2c5db78867c3dff10687bcc8` |
| `split_config.en.apk` | `e1843ca39103eb0299984a03b3904fae7c6525293d88fa99f8c4638d857218d6` |
| `split_config.xxhdpi.apk` | `efa89b97f8525e0348fdded3007c9929493c642842c70f31b7430eb52abfda15` |

## Applying patches

From the repo root:

```cmd
patch-apks.bat --app tinder
```

## Writing patches

Place Kotlin patch files under `patches\tinder\src\main\kotlin\app\revanced\patches\tinder\`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("com.tinder"("17.15.0"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
