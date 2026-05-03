# hidratespark

- **Package:** `hidratenow.com.hidrate.hidrateandroid`
- **Target version:** `4.6.9`
- **Patches module:** `:patches:hidratespark`

## Patches

| Patch | What it does |
|-------|--------------|
| Disable license check | Forces `LicenseClient.initializeLicenseCheck` to return immediately and no-ops `LicenseContentProvider.onCreate` so PairIP's Google Play licensing layer never wires up — APK runs without a Play Store entitlement. |
| Unlock premium | Patches `BillingRepository.getIfUserHasPremium()` and `GlowStudioEntitlement.isPurchased()` to return true. |

### Target classes (v4.6.9)

Obfuscation is light and names are stable:

- **License check:** `Lcom/pairip/licensecheck/LicenseContentProvider;->onCreate()Z`, `Lcom/pairip/licensecheck/LicenseClient;->initializeLicenseCheck()V`, `Lcom/pairip/licensecheck/LicenseClient$1;->run()V`
- **Premium entitlement:** `Lcom/hidrate/iap/BillingRepository;->getIfUserHasPremium()Z`, `Lcom/hidrate/iap/localdb/GlowStudioEntitlement;->isPurchased()Z`

> The bypass-login patch (`NoDisplayActivity#onCreate` + `parse.User#needsToUpdateUserParams`) was parked on branch `fix/hidratespark-bypass-login` — the rewritten `onCreate` doesn't launch MainActivity correctly on v4.6.9.

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `1dfd7e4d2852bbf4d13051f07a0024e4306e20c61c77cf6c49c445bddceb45ac` |
| `hidratenow.com.hidrate.hidrateandroid.apks` | `aa35188ccc4ae7bd10ea4b5728dabc2717d0f9b59780ac16e6d79473fb7b6e19` |
| `split_config.arm64_v8a.apk` | `fdac1af1574fc67f608730add3fed4d62e760e6558e01fafcfe0e6b291921ecb` |
| `split_config.xxhdpi.apk` | `90ca510e9cf83f49afb68438f0bb470167dd603f98c04190fc94bb3cc08ef72b` |

## Applying patches

From the repo root:

```bash
./patch-apks.sh --app hidratespark            # interactive patch picker
./patch-apks.sh --app hidratespark --no-ui    # apply every patch
```

```cmd
patch-apks.bat --app hidratespark
```

## Writing patches

Place Kotlin patch files under `patches\hidratespark\src\main\kotlin\app\revanced\patches\hidratespark\`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("hidratenow.com.hidrate.hidrateandroid"("4.6.9"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
