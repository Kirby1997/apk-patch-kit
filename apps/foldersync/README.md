# foldersync

- **Package:** `dk.tacit.android.foldersync.lite`
- **Target version:** `4.8.5`
- **Patches module:** `:patches:foldersync`

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored - APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `b015fcea1376987531c622d9143b8b9e75f58e9e46abcaf736862dd1756d8b0f` |
| `dk.tacit.android.foldersync.lite.apks` | `e4aca4cd16a61bbf0c66c7f66cfab2911f26ae12079437e3e25ebc9639f7eeb2` |
| `split_config.arm64_v8a.apk` | `d8517af1a52f813db4a579ce97ec87e825684c02446226745e522788b576f133` |
| `split_config.xxhdpi.apk` | `329c8a435e9046a5fe97d6f744d70701df64fb12ef738c0ff3bec6725e6825bf` |

## Applying patches

From the repo root:

```cmd
patch-apks.bat --app foldersync
```

## Writing patches

Place Kotlin patch files under `patches\foldersync\src\main\kotlin\app\revanced\patches\foldersync\`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("dk.tacit.android.foldersync.lite"("4.8.5"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
