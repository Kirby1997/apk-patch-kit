# tinder

- **Package:** `com.tinder`
- **Target version:** `17.15.0`
- **Patches module:** `:patches:tinder`

## Patches

| Patch | What it does |
|-------|--------------|
| Disable paywall flow | `return-void` at offset 0 of `LaunchPaywallFlow.invoke` (`Lcom/tinder/feature/paywallflow/internal/delegates/a;->c`) — every paywall routed through the paywallflow module is suppressed at the entry point. **Will also block legitimate purchase flows initiated from Settings → Get Tinder Plus etc.** |
| Disable dynamic paywall sheet | Dismisses `Lcom/tinder/dynamicpaywall/PaywallDialogFragment;` (the bottom-sheet paywall instantiated by `proceedToShowPaywall`) on `onCreateView` and returns null. |
| Disable Boost upsell | Dismisses `Lcom/tinder/boost/ui/upsell/BoostUpsellDialogFragment;`. |
| Disable MyLikes upsell | Dismisses `Lcom/tinder/mylikes/ui/dialog/MyLikesUpsellDialogFragment;` (the "You've liked amazing people! Be Seen faster with Tinder Platinum" prompt). |
| Disable Platinum Likes upsell | Dismisses `Lcom/tinder/mylikes/ui/dialog/PlatinumLikesUpsellDialogFragment;` (the "Be Seen Faster / Upgrade Likes" Platinum popup). |
| Disable Primetime Boost upsell | Dismisses `Lcom/tinder/primetimeboostupsell/internal/view/PrimetimeBoostUpsellDialogFragment;`. |
| Disable Secret Admirer upsell | Dismisses `Lcom/tinder/feature/secretadmirer/internal/view/SecretAdmirerUpsellDialogFragment;`. |
| Disable Headless Purchase upsell | Dismisses `Lcom/tinder/headlesspurchaseupsell/internal/view/HeadlessPurchaseUpsellDialogFragment;`. |
| Disable ads-bouncer rewarded-video paywall | Dismisses `Lcom/tinder/feature/adsbouncerpaywall/internal/presentation/RewardedVideoBottomSheet;` — the "watch an ad to keep swiping" interstitial shown when out of likes. |
| Disable rewarded-video modal | Dismisses `Lcom/tinder/rewardedvideomodal/internal/ui/RewardedVideoBottomSheetFragment;` — the standalone "watch an ad to get a Rewind back" prompt. |

### Target classes (v17.15.0)

Anchors expected to drift on app updates:

- **Generic paywall chokepoint:** `Lcom/tinder/feature/paywallflow/internal/delegates/a;->c(Luc1/a;Landroidx/appcompat/app/n;)V` (`.locals 9`) — `LaunchPaywallFlow.invoke` entry, every `paywallflow`-routed paywall passes through here.
- **Dynamic paywall sheet:** `Lcom/tinder/dynamicpaywall/PaywallDialogFragment;` — instantiated by `Lcom/tinder/feature/paywallflow/internal/delegates/a;->b(...)`.
- **DialogFragment upsells** (all dismissed via `dismissAllowingStateLoss()` at `onCreateView` offset 0):
  - `Lcom/tinder/boost/ui/upsell/BoostUpsellDialogFragment;`
  - `Lcom/tinder/mylikes/ui/dialog/MyLikesUpsellDialogFragment;` — triggered from `LikesSentFragment$observeViewEffect$1` when the view-effect is `Lcom/tinder/mylikes/ui/k;`
  - `Lcom/tinder/mylikes/ui/dialog/PlatinumLikesUpsellDialogFragment;` (extends `Lcom/tinder/feature/fastmatchfilters/internal/ui/filters/k;` → DialogFragment) — sole construction site is the deeplink router `Lcom/tinder/idverification/feature/internal/deeplink/b;` `pswitch_0`. Strings: `@string/upgrade_likes_title`, `@string/upgrade_likes_subtitle`, `@string/upgrade_likes`.
  - `Lcom/tinder/primetimeboostupsell/internal/view/PrimetimeBoostUpsellDialogFragment;`
  - `Lcom/tinder/feature/secretadmirer/internal/view/SecretAdmirerUpsellDialogFragment;`
  - `Lcom/tinder/headlesspurchaseupsell/internal/view/HeadlessPurchaseUpsellDialogFragment;`
- **Rewarded-video bottom sheets:**
  - `Lcom/tinder/feature/adsbouncerpaywall/internal/presentation/RewardedVideoBottomSheet;->onCreateView` has `.locals 18` — see the high-locals note below.
  - `Lcom/tinder/rewardedvideomodal/internal/ui/RewardedVideoBottomSheetFragment;->onCreateView` (`.locals 6`).

### High-locals gotcha

`RewardedVideoBottomSheet.onCreateView` declares `.locals 18` and takes 3 parameters (plus `this`), so `p0=v18`, `p1=v19`. `addInstructions` injects raw smali into the existing method and inherits its register layout — 4-bit register instructions (`invoke-virtual {p0}`, `const/4 p1`) cannot address those and fail to assemble with `[N,0] Invalid register: v18`. The patch uses `invoke-virtual/range {p0 .. p0}` and stashes null in `v0` instead of `p1`. Apply the same trick whenever an `addInstructions` snippet has to touch `p`-registers in a high-locals method.

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

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

```bash
./patch-apks.sh --app tinder            # interactive patch picker
./patch-apks.sh --app tinder --no-ui    # apply every patch
```

```cmd
patch-apks.bat --app tinder
```

The driver prints an install line that starts with `adb uninstall com.tinder` because Android rejects an in-place replace when the signing cert changes. After the first install with our keystore, future patched builds upgrade in place.

## Writing patches

Place Kotlin patch files under `patches/tinder/src/main/kotlin/app/revanced/patches/tinder/`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("com.tinder"("17.15.0"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
- Mind the high-locals gotcha above when injecting smali that references `p`-registers
