# CLAUDE.md

Guidance for Claude Code when working in this repo.

## Project overview

**apk-patch-kit** — a multi-app ReVanced patches repo with a one-shot bash driver that builds, applies, signs, and repackages APKs for sideloading. Layout mirrors [ReVanced/revanced-patches](https://gitlab.com/ReVanced/revanced-patches) so patches written here are liftable upstream, but each target app is its own Gradle subproject (produces its own jar) so one broken fingerprint can't knock out the build for unrelated apps.

Current apps:

- **`hidratespark`** (`hidratenow.com.hidrate.hidrateandroid` v4.6.9) — bypass login, disable Google Play license check, unlock premium
- **`meetup`** (`com.meetup` v2026.04.10.2881) — disable intro paywall, disable profile paywall popup, unblur gated profile content
- **`strava`** (`com.strava` v460.9) — **consumes upstream `patches.rvp` directly**, no `patches/strava/` subproject. Drop a `patches-<ver>.rvp` at the repo root and run `./patch-apks.sh --app strava --patches patches-<ver>.rvp`. Pattern used because the upstream Strava patches depend on a full Android/DEX extension toolchain (`extensions/strava/` library + stubs + shared `Utils`) that isn't ported here.
- **`twitter`** / X (`com.twitter.android` v12.4.1-release.0) — patches written (disable sensitive-media blur, remove promoted timeline items, pairip bypass) but **not shippable: X is PairIP-wrapped and its native VM SIGSEGVs on any re-signed sideload**. See the twitter Target-classes note. Kept as RE reference; needs root (Frida/LSPosed) to defeat. For X ads without root, use an **older pre-PairIP Twitter APK (≤ ~10.86)** + ReVanced's own `twitter/misc/hook/HideAdsHookPatch` (targets 10.60/10.86).

**Universal (app-agnostic) patch subproject:**

- **`patches/pairip/`** → `pairip-patches.jar` — **no `apps/` dir, no `compatibleWith`**. `DisablePairipLicenseCheckPatch` universally bypasses PairIP's *licensecheck* (the Java Play-ownership gate: `com.pairip.licensecheck.LicenseContentProvider.onCreate` / `LicenseClient.initializeLicenseCheck` / `checkLicense` / `LicenseClient$1.run`). Each surface is `runCatching`-guarded so it applies to whatever a given app contains (provider-flavor like hidratespark, or application-flavor like X). Matches by class presence; `revanced-cli list-patches -b --universal-patches` shows it. **Defeats only licensecheck — NOT PairIP's native VM/integrity** (see twitter note). Apply to any app with `./patch-apks.sh --patches patches/pairip/build/libs/pairip-patches.jar --apk <file>`.

## Environment

- **Host:** Windows 10/11 + WSL2 (Debian). Repo lives on the Windows drive (`/mnt/c/...`) and scripts run from WSL.
- **JDK:** 17. `./gradlew` uses the JVM 17 toolchain.
- **adb:** WSL cannot see USB devices without `usbipd` (not set up here), so bash scripts call the **Windows** `adb.exe` (usually `/mnt/c/ProgramData/chocolatey/bin/adb.exe`). Three WSL-specific fixes in `add-app.sh` exist because of this — see Architecture below.
- **GitHub Packages auth:** the `revanced-patcher` dep lives on GitHub Packages. Store `gprUser` + `gprKey` (PAT with `read:packages`) in `~/.gradle/gradle.properties`, or export `GITHUB_ACTOR` + `GITHUB_TOKEN`. 401s during Gradle builds almost always mean these are missing or expired.
- **apksigner:** needed for `.apks` signing. WSL: `sudo apt install apksigner`. Windows: `patch-apks.bat` looks on PATH, then scans `%ANDROID_HOME%`, `%ANDROID_SDK_ROOT%`, and `%LOCALAPPDATA%\Android\Sdk` for `build-tools\*\apksigner.bat` (newest wins). Android Studio is enough — no PATH edit needed.
- **revanced-cli:** download a `revanced-cli-*.jar` from [revanced/revanced-cli](https://github.com/revanced/revanced-cli/releases) into the repo root. Not committed (see `.gitignore`).
- **Decompile tooling on this host:**
  - `apktool` is at `~/bin/apktool` (wrapper) → `~/bin/apktool_3.0.1.jar`. Already on `$PATH`. Use it for smali dumps; that's what the patcher fingerprints against.
  - **`jadx` is NOT installed** in this WSL. Don't reach for it — work from the apktool smali tree directly. Install with `apt install jadx` if you really need Java pseudocode.
  - Decompile dumps land under `apps/<app>/decompiled-apktool/` and are git-ignored via `apps/*/decompiled-*/` in `.gitignore` — never commit them, they're regenerable from the APK.

## Layout

```
revanced-cli-*.jar              # Shared ReVanced CLI at repo root (gitignored)
patch-apks.sh                   # Driver: build → patch → sign → repack
add-app.sh                      # Scaffold a new app + pull its APKs from a device
build.gradle.kts                # Root Gradle
settings.gradle.kts             # Registers each :patches:<app> subproject
gradle/libs.versions.toml       # Single source of truth (patcher, kotlin, smali)

patches/<app>/                  # One Gradle subproject per app
  build.gradle.kts              # Sets archiveBaseName to "<app>-patches"
  src/main/kotlin/app/revanced/patches/<app>/<category>/<Patch>.kt

apps/<app>/                     # One directory per app
  README.md                     # Autogenerated: package, version, SHA-256s, install notes
  apks/                         # Gitignored — user supplies
  decompiled-apktool/           # Gitignored reference dumps (optional)
  decompiled-jadx/              # Gitignored reference dumps (optional)
```

APK binaries, build outputs, decompiled dumps, signing artefacts, and all `*.jar` files (except `gradle-wrapper.jar`) are `.gitignore`d.

### Morphe patch source lives in its own repo

The `morphe`-engine patches (the `.mpp` bundle those apps consume) are **not** kept in this repo. Their source is a standalone patches repo, **[`Kirby1997/morphe-patches`](https://github.com/Kirby1997/morphe-patches)**, which builds one `patches-<ver>.mpp` and publishes it as a GitHub **release**. This repo links to it the same way it links to any external bundle — via each app's `sources.toml` (`repo = "Kirby1997/morphe-patches"` + a `version` pin that resolves the release asset). Nothing here builds that source; the pipeline only downloads the published `.mpp`.

To work on those patches: clone the repo (`git clone https://github.com/Kirby1997/morphe-patches`) — you can clone it to `./morphe-patches/` here (it's `.gitignore`d so it never gets committed back in) or anywhere else. Edit → `./gradlew :patches:build` → cut a new `gh release` → bump the `version` in the relevant `apps/<app>/sources.toml`. This is the standard Morphe split: a patches repo is standalone (source + release), and consumers (this driver, `morphe-cli`, the on-device Manager) reference the bundle by URL/version, never by vendoring the source. The **ReVanced** `patches/<app>/` subprojects (the `type = "local"` jar-built ones) are different — those stay here and the driver builds them directly.

## Commands

All from the repo root.

```bash
# Scaffold a new app: picks a package, pulls every APK, derives a shortname from
# the Application label, records SHA-256s, writes apps/<name>/ + patches/<name>/.
./add-app.sh                                  # Fully interactive
./add-app.sh <package>                        # Non-interactive package, name auto-derived
./add-app.sh --name <shortname> [package]     # Force a shortname, skip aapt derivation
./add-app.sh --scaffold-only --name <n> <pkg> # Skip adb/aapt, just create files
./add-app.sh --app-only [...]                 # Scaffold apps/<name>/ only, no patches/<name>/ subproject (for apps that consume an upstream patches.rvp — see strava)
./add-app.sh --adb <path>                     # Override adb.exe location
./add-app.sh --aapt <path>                    # Override aapt.exe location
./add-app.sh --decompile [...]                # Also apktool-decompile base.apk after scaffolding

# Decompile an existing app's base.apk → apps/<app>/decompiled-apktool/
./decompile.sh                                # Interactive picker over apps/*
./decompile.sh <app>                          # Decompile that app
./decompile.sh <app> --force                  # Overwrite an existing dump

# Build patches jars
./gradlew :patches:<app>:build                # One app
./gradlew build                               # All apps

# Apply patches → sign → repackage
./patch-apks.sh                               # Fully interactive (pick app → APK → patches)
./patch-apks.sh --app <app>                   # Preselects that app's jar + apks/ dir
./patch-apks.sh --app <app> --no-ui           # Every patch, no prompts
```

Output lands in `build/<name>-patched.apks` (or `-patched.apk` for a single APK). The driver prints the correct `adb install-multiple` or `adb install` command on completion.

## Workflows

The operational how-to — adding an app end-to-end, reverse-engineering a
fingerprint target, and the patch-file template — lives in the **`apk-patch`
skill** (`.claude/skills/apk-patch/SKILL.md`). Invoke it when scaffolding an app,
writing a patch, or building/applying patches. It drives `add-app.sh`,
`decompile.sh`, `./gradlew`, and `patch-apks.sh`; this file keeps the reference
data the skill points back to (Architecture, Target classes, Gotchas below).

Patch-file convention: **one `bytecodePatch` object per feature** (each is
selected by name via `patch-apks.sh -e "<Name>" --exclusive`), **grouped one file
per `<category>`** where patches share a fingerprint shape or disable body — the
patcher discovers patches by reflection regardless of file, so colocating keeps
them independently selectable while sharing a `private const val` smali body.
Worked examples: `patches/tinder/.../subscription/DisableUpsellDialogsPatch.kt`
and `patches/meetup/.../subscription/DisableSubscriptionPaywallsPatch.kt`.

## Architecture

### Patching pipeline (`patch-apks.sh`)

Five stages in order — if something breaks, identify which:

1. **Resolve inputs.** Locates `revanced-cli-*.jar` at the repo root. Resolves the app via `--app`, an interactive picker over `apps/*`, or explicit `--patches`/`--apk` flags. For an app, auto-finds `patches/<app>/build/libs/*.jar` and `apps/<app>/apks/`.
2. **Enumerate patches.** Runs `revanced-cli list-patches -p <jar> -b` and parses `Name: <patch>` lines. (The earlier dry-run trick of `patch -b --force` with the jar as its own APK broke on patcher 22+ — `ResourcesDecoder` crashes before any patches load — and was removed.)
3. **Extract & patch.** `.apks` is unzipped to `build/patch-work/extracted/`; only `base.apk` is patched (splits carry no code). Patches pass via repeated `-e "<Name>"` with `--exclusive` so deselected patches never run even if marked default-enabled.
4. **Sign consistently.** A fresh PKCS12 keystore is generated per run at `build/patch-work/sign.p12` (pass `revanced`). **Every** APK in a bundle (base + all `split_*.apk`) is signed with the same key — Android rejects bundles whose splits have different signing identities.
5. **Repackage.** Splits are `jar cMf`'d back into `build/<name>-patched.apks`. Original inputs are never modified.

`--exclusive` is load-bearing: without it, any patch marked default-enabled in the jar would run even when deselected.

### Manifest applier (`apps/<app>/sources.toml`)

Additive, opt-in layer on top of the legacy pipeline above. `patch-apks.sh --app <app>` checks for `apps/<app>/sources.toml` first (only when `--apk`/`--patches` aren't given); if present, `lib/manifest.sh` + `lib/fetch.sh` + `lib/resolve.sh` + `lib/engine-{morphe,revanced}.sh` take over resolution — no interactive picker, no manual jar path. Every app, including the ones with a local `patches/<app>` subproject, can carry a manifest; it's the preferred way to describe "how to patch this app" going forward.

**`sources.toml` schema:**

```toml
package     = "com.example.app"        # required
app_version = "1.2.3"                  # required, informational
engine      = "morphe" | "revanced"    # required — see engine rule below
apk         = "apks/base.apk"          # required, path relative to apps/<app>/

[[bundle]]                             # one or more, applied in order
type = "github"                        # github | gitlab | local | url
repo = "owner/repo"                    # github/gitlab only
version = "1.2.3"                      # github/gitlab/url pin (tries "$v" then "v$v" as release tag)
asset = "patches-1.2.3.mpp"            # optional; auto-detected (*.mpp/*.rvp) if omitted
sha256 = "..."                         # optional; "-" or omitted logs the hash instead of enforcing it
project = "foldersync"                 # local only — gradle-builds patches/<project>
url = "https://.../patches.rvp"        # url only — plain prebuilt-bundle download

[patches]                              # optional — omit to apply every default-enabled patch
enable = ["Patch name"]
disable = ["Other patch"]
exclusive = true                       # maps to --exclusive
```

- **`engines.toml`** (repo root) pins one version per engine: `[morphe].version`, `[revanced].version`. `engine_cli_path` in `lib/fetch.sh` reads it, downloads the matching `morphe-cli-<ver>-all.jar` / `revanced-cli-<ver>-all.jar` from its GitHub releases, and caches it at `bin/<engine>-cli.jar`. `bin/` and `.cache/bundles/` (resolved `[[bundle]]` downloads, keyed by host+repo+version+asset) are both `.gitignore`d and self-populate on first run — nothing under either needs to be committed or pre-fetched.
- **One engine per app.** `manifest_validate` rejects anything but `engine = "morphe"` or `engine = "revanced"` — an app can't mix bundles from both patchers in one manifest.
- **`type = "local"` implies `engine = "revanced"`** (validated, not just convention) — `patches/<project>` subprojects are ReVanced-patcher Kotlin, morphe can't consume them.
- **`--resolve-only`** prints the resolved engine, CLI jar path, input APK, every resolved bundle path, and the exact command that would run, then exits 0 without patching or downloading anything not already needed for resolution — use it to sanity-check a manifest edit before committing to a multi-minute patch run.
- **Two very different output shapes**, both driven by the same `engine` field:
  - **`morphe`** apps (currently just `twitter`, the reference example — see its `sources.toml`) merge every split in the input `.apks`/`.apkm` into one universal APK, apply all bundles' patches via `morphe-cli`, and self-sign — output is a single `build/<app>-patched.apk`, install with plain `adb install`.
  - **`revanced`** apps set `REVANCED_CLI`/`APK_FILE`/`PATCHES_JAR`/`NO_UI` from the manifest and **fall through** into the unchanged legacy pipeline (stages 1–5 above): extract `.apks`, patch `base.apk` only, sign every split with one per-run keystore, repackage to `build/<app>-patched.apks`. This is why `foldersync`, `hidratespark`, `meetup`, `metoffice`, `strava`, and `tinder` moved to manifests without any change to how their output is produced or installed (`strava` uses `type = "url"` to pull the upstream `.rvp` instead of `type = "local"`, everything else builds its own `patches/<app>` jar).

### Scaffolding pipeline (`add-app.sh`)

Three WSL-specific fixes are embedded in the script — **do not remove them without cause**, each was debugged after a reproducible hang or silent failure:

1. **Pre-start the adb daemon with fully detached stdio**, guarded by `timeout 10`:
   ```bash
   timeout 10 "$ADB" start-server </dev/null >/dev/null 2>&1
   ```
   Without this, the first piped call (`adb.exe devices | awk ...`) spawns the daemon, the daemon inherits the pipe's fds, and the reader never sees EOF → the script hangs forever. The timeout catches the other failure mode: an invisible Windows Firewall prompt on first run.

2. **Strip `\r` before awk-filtering `adb devices` output.** `adb.exe` emits CRLF, so `awk 'NR>1 && $2=="device" {print $1}'` matches `device\r` against `device` and fails silently:
   ```bash
   "$ADB" devices | tr -d '\r' | awk 'NR>1 && $2=="device" {print $1}'
   ```

3. **Convert local paths via `wslpath -w` before passing them to `adb.exe`.** Windows binaries do not auto-translate `/mnt/c/...` arguments; `adb pull /sdcard/x /mnt/c/...` fails with "cannot create file/directory". `adb_local_path()` in the script handles this and is a no-op for Linux-native adb.

### Gradle multi-module

- Root `build.gradle.kts` declares the Kotlin plugin with `apply false` — not applied at root, each subproject applies it.
- Each `patches/<app>/build.gradle.kts` applies Kotlin JVM, depends on `libs.revanced.patcher` + `libs.smali`, targets JVM 17, sets `archiveBaseName` so jars land at `patches/<app>/build/libs/<app>-patches.jar`.
- `gradle/libs.versions.toml` is the single source of truth — bump `revanced-patcher` there and every subproject follows.

## WSL/adb troubleshooting

If adb suddenly stops seeing the device (both WSL and Windows empty):

1. **Kill every adb daemon first** — multiple servers fighting over tcp:5037 is common after an interrupted run:
   ```bash
   pkill -f adb.exe 2>/dev/null
   "$(command -v adb.exe)" kill-server 2>/dev/null
   ```
2. **Check USB mode on the phone.** Notification shade → tap USB → **File Transfer (MTP)**. Many phones suppress the ADB auth popup in charge-only mode.
3. **Check the cable.** Charge-only USB-C cables have no data lines.
4. **Confirm Developer options + USB debugging are still enabled** — some OEM skins reset these when you revoke trusted devices.
5. **First run: start the daemon from PowerShell, not WSL.** The Windows Firewall prompt for `adb.exe` is invisible from a backgrounded WSL pipe. From PowerShell: `adb.exe start-server; adb.exe devices`. Accept the prompt.
6. If the script hangs with no output, check for a stopped job: `jobs -l`, then `kill %1 %2 ...`.

## Gotchas

- **Do not remove the three WSL fixes in `add-app.sh`** (detached daemon pre-start, `\r` strip, `wslpath -w`). Each was debugged after a reproducible hang or silent failure.
- **Patches are version-pinned** via `compatibleWith(...)`. A new app release will break any fingerprint anchored on a renamed obfuscated class — expect to re-decompile and update `L...;` type strings.
- **`.apks` bundles need `adb install-multiple`**, not `adb install`. All splits must share a signing identity — `patch-apks.sh` signs every split with the same per-run keystore.
- **APKs are `.gitignore`d** on purpose — not the repo's IP to redistribute. Per-app READMEs carry the expected version + SHA-256 so anyone cloning knows exactly what to fetch.
- **`revanced-cli-*.jar` is `.gitignore`d** (covered by the blanket `*.jar` rule). Download a matching release into the repo root; without it the driver exits early.

## Target classes

Anchor points for the current patches — these are the obfuscated identifiers the fingerprints key off. Expect to re-verify on any version bump.

### hidratespark (v4.6.9)

Obfuscation is light and names are stable:

- **License check:** `com.pairip.licensecheck.LicenseContentProvider#onCreate`, `LicenseClient#initializeLicenseCheck`, `LicenseClient$1#run`
- **Billing:** `com.hidrate.iap.BillingRepository#getIfUserHasPremium`, `com.hidrate.iap.localdb.GlowStudioEntitlement#isPurchased`

> The bypass-login patch (`NoDisplayActivity#onCreate` + `parse.User#needsToUpdateUserParams`) was parked on branch `fix/hidratespark-bypass-login` — the rewritten `onCreate` doesn't launch MainActivity correctly on v4.6.9.

### meetup (v2026.04.10.2881)

Obfuscation is heavy; anchor on class type + method signature, not opcode patterns. Expect drift on every app release.

- **Intro paywall:** `Lcom/meetup/base/settings/AppSettings;->isIntroPaywallEnabled()Z`
- **Profile paywall launcher:** `Lcom/meetup/feature/profile/e;->a(Lcom/meetup/feature/profile/e;Lcom/meetup/shared/meetupplus/MeetupPlusPaywallType;Lcom/meetup/library/tracking/data/conversion/OriginType;Lcom/meetup/shared/groupstart/z;Lln/a;I)V` — the static accessor that calls `ActivityResultLauncher.launch` for every `MeetupPlusPaywallType` routed via the profile feature.
- **Paywall activity chokepoints** — two intent factories, two eras. `Lwa/b;` (legacy) routes its `pswitch_4` to `Lcom/meetup/subscription/stepup/StepUpActivity;`; `Lwa/a;` (Compose-era) routes `pswitch_d` to `Lcom/meetup/feature/membersub/MemberSubActivity;` and `pswitch_b` to `Lcom/meetup/feature/membersub/MemberSubWebViewActivity;`. Profile and compose-message flows go through `wa/a.q` → MemberSubActivity, which is why the StepUp patch alone does not catch them. All three `onCreate` methods are patched the same way: `invoke-super` + `finish()` + `return-void`. Hilt parents are `Hilt_StepUpActivity`, `Hilt_MemberSubActivity`, `Hilt_MemberSubWebViewActivity` respectively.
- **Trial banner composable:** `Lcom/meetup/feature/home/composables/x0;->d(ILandroidx/compose/runtime/Composer;Landroidx/compose/ui/Modifier;Lln/a;)V` — the `MeetupPlusTrialBanner` composable (identified via its own `traceEventStart` string `"com.meetup.feature.home.composables.MeetupPlusTrialBanner (YourGroupsSection.kt:442)"`). Embedded by home, notifications, explore, group, and profile screens; returning at offset 0 removes it everywhere.
- **Attendees paywall composables:**
  - `Log/f;->d(Ljava/lang/String;ILln/a;Lln/a;Llh/b;Log/h;Landroidx/compose/runtime/Composer;I)V` — `EventInsightsComponent` (event-page "Learn more about attendees / Unlock full details" teaser).
  - `Lcom/meetup/shared/attendees/q;->e(ZLln/k;Landroidx/compose/runtime/Composer;I)V` — `AttendeeListMemberPlusUpsell` (Attendees list "Learn more about who will be there. Try for free." banner, uses `R.string.event_insights_cta_not_subscribed`).
- **OneTrust cookie banner:** consent UI is gated by `Lcom/onetrust/otpublishers/headless/Public/OTPublishersHeadlessSDK;->shouldShowBanner()Z` — called from `IntroFragment` on fresh install. Returning `0` skips `setupUI`. Pin `getConsentStatusForGroupId(Ljava/lang/String;)I`, `getConsentStatusForGroupId(Ljava/lang/String;Ljava/lang/String;)I`, and `getConsentStatusForSDKId(Ljava/lang/String;)I` to `0` so downstream trackers that query per-category consent see "rejected".
- **Blur overlays:** `Landroidx/compose/ui/draw/BlurKt;` overloads `blur-1fqS-gw`, `blur-1fqS-gw$default`, `blur-F8QBwvs`, `blur-F8QBwvs$default`
- **Unprompted paywall flags** (not yet patched — belt-and-braces candidates if a popup slips past the Activity chokepoints): `Lcom/meetup/base/settings/AppSettings;->getShouldShowUnpromptedPaywall()Z`, `getShouldShowEventUnpromptedPaywall()Z`
- **`MeetupPlusPaywallType` enum:** `Lcom/meetup/shared/meetupplus/MeetupPlusPaywallType;` with values `Messaging, Profile, Attendees, Waitlist, GroupMembers` — useful index when figuring out which feature's paywall flow you're looking at.

### tinder (v17.15.0)

Decompile dump under `apps/tinder/decompiled-apktool/` (gitignored). Heavy obfuscation; lots of single-letter file names. Anchor on class type + method signature.

- **"Be Seen Faster" / "Upgrade Likes" Platinum popup:** layout `res/layout/platinum_likes_upsell_dialog_fragment.xml` uses `@string/upgrade_likes_title` ("Be Seen Faster"), `@string/upgrade_likes_subtitle` ("Increase your chance to get a match. With Tinder Platinum we'll prioritize your likes."), `@string/upgrade_likes` ("Upgrade Likes"). Owned by `Lcom/tinder/mylikes/ui/dialog/PlatinumLikesUpsellDialogFragment;` (extends `Lcom/tinder/feature/fastmatchfilters/internal/ui/filters/k;` → `Landroidx/appcompat/app/l0;` → `Landroidx/fragment/app/q;`/DialogFragment). Sole construction site is the deeplink router `Lcom/tinder/idverification/feature/internal/deeplink/b;` `pswitch_0`. Disable by patching `onCreateView(Landroid/view/LayoutInflater;Landroid/view/ViewGroup;Landroid/os/Bundle;)Landroid/view/View;` (`.locals 1`) at offset 0 with `invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V` + `const/4 p1, 0x0` + `return-object p1`.
- **Sibling "MyLikes" Platinum upsell popup:** `Lcom/tinder/mylikes/ui/dialog/MyLikesUpsellDialogFragment;` — uses `my_likes_upsell_initial_entry_description` ("You've liked amazing people! Be Seen faster with Tinder Platinum"). Triggered from `Lcom/tinder/mylikes/ui/LikesSentFragment$observeViewEffect$1;->invokeSuspend(Ljava/lang/Object;)Ljava/lang/Object;` when the view-effect is `Lcom/tinder/mylikes/ui/k;`. Same dismissAllowingStateLoss strategy.
- **Other DialogFragment-based upsells:**
  - `Lcom/tinder/headlesspurchaseupsell/internal/view/HeadlessPurchaseUpsellDialogFragment;`
  - `Lcom/tinder/primetimeboostupsell/internal/view/PrimetimeBoostUpsellDialogFragment;`
  - `Lcom/tinder/boost/ui/upsell/BoostUpsellDialogFragment;`
  - `Lcom/tinder/feature/secretadmirer/internal/view/SecretAdmirerUpsellDialogFragment;`
- **Generic paywall chokepoint:** `Lcom/tinder/feature/paywallflow/internal/delegates/a;->c(Luc1/a;Landroidx/appcompat/app/n;)V` (`.locals 9`) is the `LaunchPaywallFlow.invoke` entry — every `paywallflow`-routed paywall passes through here. `return-void` at offset 0 nukes them all but probably also breaks legit purchases initiated via Settings → Get Tinder Plus etc.
- **Dynamic paywall sheet:** `Lcom/tinder/dynamicpaywall/PaywallDialogFragment;` — instantiated by `Lcom/tinder/feature/paywallflow/internal/delegates/a;->b(...)` (the static `proceedToShowPaywall` handler). Same DialogFragment dismiss strategy works.
- **Rec-card ads:** `smali_classes11/com/tinder/library/adsrecs/internal/rule/{a,b,d,e}.smali` — Kotlin obfuscated `AdMainCardStackInjectorImpl`/`AdCuratedCardStackInjectorImpl`. Each has a `shouldInsertAdRec` lambda generated as `*$shouldInsertAdRec$1.smali`. Returning false there should stop the swipe-stack ads. `Lcom/tinder/library/adsconfig/model/AdFeature;` enum lists `REWARDED_VIDEO_CARD_STACK_LIKES`/`_REWIND` — the two rewarded-video surfaces.
- **Ads bouncer paywall (rewarded-video offer when out of likes/rewinds):** `Lcom/tinder/feature/adsbouncerpaywall/internal/presentation/RewardedVideoBottomSheet;` and `Lcom/tinder/rewardedvideomodal/internal/ui/RewardedVideoBottomSheetFragment;`. Both BottomSheetDialogFragments — same dismiss strategy.
- **Ad SDKs bundled:** Facebook Audience Network (`smali_classes6/com/facebook/ads/*` — `RewardedVideoAd`, `NativeBannerAd`, `MediationBannerAdapter`), Google Mobile Ads (`smali_classes11/com/tinder/library/adsgoogle/internal/*`), Nimbus (`smali/com/tinder/adsnimbus/*`). All three are wired through `AdFeature` config and `adsrecs/internal/rule/*` injection rules — disabling at the rule layer is upstream of vendor.
- **String-resource cheatsheet for grepping monetisation surfaces:** `paywall`, `upsell`, `boost_paywall_*`, `bouncer_paywall_*`, `discount_paywall_*`, `bundle_offer_paywall_*`, `tabbed_vertical_paywall_*`, `controlla_button_subscriptions_*`, `my_likes_upsell_*`, `upgrade_likes*`, `superlike_upsell_*`, `boost_upsell_*` — 273 distinct `paywall`/`upsell` string names total.

### twitter / X (v12.4.1-release.0)

Two model layers coexist: **legacy** `Lcom/twitter/model/...;` + `Lcom/twitter/tweetview/...;` (Java/RxJava era, delegate-binder UI) and **new** `Lcom/x/...;` (Kotlin, kotlinx-serialization models, Flow/Compose URT pipeline). Obfuscation is single-letter class names (`a`, `b`, … `g4`) but package paths + method signatures survive — anchor on those.

- **Sensitive-media "content warning" blur** (legacy tweetview path). The blur overlay is `Lcom/twitter/sensitivemedia/ui/widget/SensitiveMediaBlurPreviewInterstitialView;`, toggled VISIBLE(0x0)/GONE(0x8) by `SensitiveMediaBlurPreviewInterstitialViewDelegateBinder.d(...)` and its ViewStub sibling `...tombstone/j.smali`. **Both gate on one static predicate** `Lcom/twitter/tweetview/core/k;->a(Lcom/twitter/tweetview/core/t;Lcom/twitter/ui/renderable/i;Lcom/twitter/account/model/x;)Z` — returns true only when the tweetview sensitive-media state resolves to `e$a`. Force it `return 0` → interstitial never inflates/shows, media renders unblurred. Patched in `patches/twitter/.../sensitivemedia/DisableSensitiveMediaBlurPatch.kt`. (The full non-blur tombstone that *replaces* media is a different, uncovered surface — this only touches the blur-preview overlay, which is the "flashes then hides" symptom.)
- **Promoted / ad timeline items** (new `com/x` URT path). The shared URT repo `Lcom/x/repositories/urt/g;` reads the persisted timeline from the DB as `Flow<List<UrtTimelineItem>>`, runs an onEach-style operator whose side-effect action is the SuspendLambda `Lcom/x/repositories/urt/e;->invokeSuspend(...)` (the list is in its field `n`), then scribe flow `k` → distinctUntilChanged → stateIn into MutableStateFlow `g.x` (exposed by `g.w()`). **Every** surface (home/profile/list/search/bookmark/communities/ntab/videotab) delegates to this one `g`, and `o1` forwards the *same* list instance downstream — so mutating that list inside `e.invokeSuspend` removes items from all timelines at once, no row, no gap. Promoted-item oracle: `Lcom/x/repositories/urt/b;->b(Lcom/x/models/timelines/items/UrtTimelineItem;)Lcom/x/repositories/urt/b$a;` returns non-null iff the item carries `Lcom/x/models/TimelinePromotedMetadata;` (covers `UrtTimelinePost`, `EventSummary`/`UrtTimelineEventSummary`, `TimelineTrend`/`UrtTimelineTrend`). Patched in `patches/twitter/.../ads/RemovePromotedTimelineItemsPatch.kt`.
  - Ad-signal source getters (if the oracle drifts): `Lcom/x/models/timelines/items/UrtTimelinePost;->getPromotedMetadata()` (= `component5`), same on `EventSummary`, `TimelineTrend`, `UrtTimelineUser`. `Lcom/x/repositories/urt/g;->S(Ljava/util/List;)V` is a small non-suspend seen-set/snapshot recorder (updates `z.c` + entryId set) — **not** the render path, do not filter there.
  - Note `Lcom/x/repositories/home/i0;` already filters promoted for a narrow author-subset feature — it is not the general feed; there is no built-in global ad filter (ads are server-injected to be shown).
  - **⚑ SUPERSEDED (2026-07-07): X IS sideload-patchable UNROOTED at v12.2.0 via Morphe + x-shim.** The "BLOCKED by PairIP" analysis below is correct *for 12.4.1* but the conclusion "unusable at every version / root-only" is **wrong** — see the "RESULT" + "SUCCESS" bullets under the `inotia00/x-shim` entry lower in this section. Full proof on unrooted device HQ64A9065A: patched X **12.2.0-release.0** (Piko 3.7.0 + x-shim 1.7.0, morphe-cli, our re-sign) **boots past PairIP native check (no SIGSEGV), logs in (attestation passes — `Integrity key attestation record generated successfully`, no `AttestationDenied`), loads the home feed.** The native wall is version-dependent: 12.4.1 SIGSEGVs, 12.2.0 does not. Working artifact: `build/x-12.2.0-patched.apk`. Everything below is retained as the 12.4.1-specific record.
  - **BLOCKED by PairIP — X is not sideload-patchable on an unrooted device (v12.4.1 ONLY; NOT true for 12.2.0 — see superseding note above).** X is wrapped by Google Play **PairIP** anti-tamper: `Lcom/pairip/application/Application;` extends the real `Lcom/twitter/app/TwitterApplication;` and, in `attachBaseContext`, calls `VMRunner.setContext` + `SignatureCheck.verifyIntegrity` + `LicenseClient.checkLicense`. ~22 real app methods (mostly `BroadcastReceiver.onReceive` across `com/twitter`, `com/x`, `androidx`, `com/google`, `braze`) are **virtualized** — body replaced by `Lcom/pairip/VMRunner;->invoke(blobName, args)`, real bytecode encrypted in `assets/` blobs (random 16-char names) and interpreted by native `libpairipcore.so`. `StartupLauncher.launch()` runs the startup blob.
    - **Rigorous empirical findings (all with a ≥20 s observation window — pairip's crash is *delayed* ~5–10 s after StartActivity, so short checks give false positives):**
      1. **Any our-key re-sign SIGSEGVs.** Even resign-only (no code patches) native-crashes in `libpairipcore.so`, fault addr `0x6ffabf365d000337`. So pairip's native VM enforces the Play signing identity; every sideloaded (re-signed) build dies. Blur/ad patches are irrelevant to *this* crash.
      2. **The tamper crash is defeatable**, but not the app. Neutering the VM entry (`VMRunner.invoke`→null, or surgically `StartupLauncher.launch`→`return-void`, plus `verifyIntegrity`/`checkLicense`→`return-void`) removes the native SIGSEGV — the app then boots further and dies with a **Java** `NullPointerException` in `FirebaseInitProvider.onCreate` (`gms .../u.a` → `Resources.getIdentifier(name=null)`). The startup blob does **essential init entangled with the integrity check** in one encrypted native blob; skipping it starves downstream init, running it crashes on signature. Can't split them statically.
    - **`pairip/BypassPairipPatch.kt`** mirrors kareemlukitomo/morphe-patches' `DisableTwitterPairIpPatch` (the one known static attempt): `Application.attachBaseContext`→`invoke-super`+`return-void` (skips setContext/verifyIntegrity/checkLicense), `SignatureCheck.verifyIntegrity`→`return-void`, `StartupLauncher.launch`→`return-void`. **It removes the native SIGSEGV** but our apktool-repacked Play bundle then dies with the same Firebase NPE. Morphe targets **APKMirror APKM** bundles — the source/repack tooling differs; the startup blob's essential init is the sticking point on a Play-pulled bundle.
    - **Community consensus (crimera/piko#977, Jul 2026):** no non-root `libpairipcore` bypass exists. pairipfix and ReVanced use the same "return pass" idea; only in-memory (LSPosed) works because it never re-signs/rebuilds the dex. **Worse — a login wall independent of pairip:** current X sends a Play Integrity token at login, so a re-signed APK gets `LoginError.AttestationDenied` + OAuth `UNREGISTERED_ON_API_CONSOLE` (cert-fingerprint mismatch). Even the old pre-PairIP escape (≤11.81) now can't log in. PairIP history on X: added 10.85, removed, re-added 11.82, present on 12.4.1.
    - **Conclusion (12.4.1-specific):** X 12.4.1 re-signed crashes in pairip's native VM (SIGSEGV) on unrooted, and even the tamper-neutered build dies at FirebaseInit — so **12.4.1 is not sideload-patchable unrooted** by static re-sign. This does NOT generalize: **12.2.0 works unrooted** (superseding note at the top of this section + RESULT/SUCCESS bullets below). For 12.4.1 specifically the only route remains root + LSPosed. Our three hand-written `patches/twitter/*` smali patches were RE artifacts against 12.4.1; the actually-shipping path is Piko+x-shim on 12.2.0, not those. Restore stock X by reinstalling the **original Play-signed** apks from `apps/twitter/apks/` (`adb install-multiple`) — valid signature, launches fine.
    - Upstream references: ReVanced's own Twitter "Hide ads" (`twitter/misc/hook/HideAdsHookPatch`, extension-based JSON hook) targets **10.60/10.86** (pre-PairIP) and won't `compatibleWith` 12.4.1. ReVanced's shared pairip *licensecheck* patch: `patches/shared/misc/pairip/license/DisableLicenseCheckPatch.kt` (our `patches/pairip/` replicates it, universally).
    - **`inotia00/x-shim` evaluated (2026-07-07) — NOT a non-root escape, doesn't change our conclusion.** It's a *Piko* compatibility shim, not a PairIP defeat. Zero references to `vmrunner/signature/integrity/attest/licensecheck/corepatch/pairipcore` anywhere in its source — it never touches the native VM, the resign SIGSEGV, or Play attestation. What it does: PairIP virtualizes ~22 `BroadcastReceiver.onReceive` bodies (GoogleAds, Braze push/dispatch, ExoPlayer, Timeline, Tracker, Telephony, Locale, Media3, Worker, AppCompat…); the shim *reconstructs those virtualized method shapes* from a ProGuard-mock JSON name-map (`inotia00/proguard-patches` + `piko-proguard-mock`) so Piko's hooks resolve, and re-injects native libs Piko needs (`libjingle_peerconnection`, `libjuicebox_sdk_jni`). It restores hook targets; it does not crack the VM. Still requires root — README: "Root permission may be required (LSPosed CorePatch)" (CorePatch = the signature-verification defeat = our native/attestation wall), and getting the mock JSON also needs root. Wrong pipeline for us anyway: `ApkFileType.APKM` (ApkMirror bundles) via **Morphe Manager** on-device patcher and its own `app.morphe.patcher` fork, not our `revanced-cli` + Play-pulled bundle. And dead on current X: v1.7.0 (2026-07-03) "Temporarily disable all patches in 12.5.0-release.0+" (`is_12_05_or_greater → false`), prior 15 releases a stream of "Exception thrown in 12.x" firefighting; README: "may not work in its current state." Bottom line: x-shim is the **root-path Piko tooling**, confirms "root + LSPosed only" — do not re-investigate as a non-root route.
      - **Morphe toolchain assembled + empirically probed (2026-07-07), scratchpad `morphe/`.** Pieces: `morphe-cli-1.9.1-all.jar` (GitHub MorpheApp/morphe-cli, 109MB), Piko `patches-3.7.0.mpp` (GitHub crimera/piko, 122 patches), x-shim `patches-1.7.0.mpp` (GitLab release asset, 3 patches: "Abstract shim layer" / "…for native library" / "…for method", all default-on), mock data GitLab `inotia00/piko-proguard-mock` (`mock/312020000.json`=12.2.0 … `312041000.json`=12.4.1, auto-fetched by the shim patch — **no root needed to fetch when the version's JSON exists**). `.mpp` = Morphe patch bundle (a jar). morphe-cli **accepts our Play-pulled `.apks`** (merges splits like an APKM) — the ApkMirror-vs-Play distinction is not a hard input requirement. `patch` has `--mount` (root install, keeps original sig) and `--unsigned`.
      - **Hard blockers found (both stable Piko 3.7.0 AND dev 3.8.0-dev.3):** (1) **Piko X version ceiling = 12.2.0-release.0** (`list-versions -f com.twitter.android` → 11.81/11.99-ripped/12.0.0/12.2.0 only; 70 patches). Our repo's **12.4.1** is *past* Piko — a full run skips all 122 twitter patches as incompatible, leaving only x-shim's 3 no-op shims. To get real features (Remove Ads, Show sensitive media, etc.) you must target **X 12.2.0-release.0** from ApkMirror. (2) **No PairIP/native-sig bypass exists in either bundle** — grep of piko+x-shim `.mpp` classes and patch names for `pairip|signat|integrit|spoof|attest|mount|license|tamper|verif` = nothing (lone "SignatureCheckExtensionFingerprint" is Instagram-links, unrelated). Piko twitter patches are pure UI/feature toggles. So a re-signed unrooted build still hits the same native SIGSEGV; Morphe's only answer is `--mount` = **root**. Confirms: **the Reddit "it works" reports are rooted-mount** (original signature preserved), not a non-root escape.
      - **RESULT (2026-07-07, unrooted device HQ64A9065A) — the native PairIP wall is VERSION-DEPENDENT; 12.2.0 BOOTS re-signed.** Built re-signed X **12.2.0-release.0** (ApkMirror APKM at `apps/twitter/apks/x-12.2.0.apkm`) with piko 3.7.0 + x-shim 1.7.0 via morphe-cli (70 piko + 3 x-shim applied, mock JSON `312020000` auto-fetched no-root, output single merged universal APK `build/x-12.2.0-patched.apk`, 230MB). Uninstalled stock 12.4.1, `adb install` succeeded, launched. **App runs — process stays alive past the ~5–10s delayed-crash window, NO `libpairipcore` SIGSEGV, NO tombstone, FirebaseInit SUCCEEDS** (on 12.4.1 this same point NPE'd in FirebaseInitProvider). Reaches the X login screen ("See what's happening" — Google / email / Continue with Phone / Login with username; top activity `com.twitter.x.lite.XLiteActivity`). Screenshot `build/x122-screen2.png`. **So the earlier "X unusable when patched on unrooted at *every* version" conclusion was wrong — it held for 12.4.1 (which SIGSEGVs) but 12.2.0 clears the native check via this Morphe+x-shim+resign path.** Why the difference: 12.4.1's native integrity is stricter than 12.2.0's, and/or x-shim's shim-layer only supports up to 12.4.1 with the piko hooks resolving at 12.2.0. Build cmd: `java -jar morphe-cli.jar patch --patches=piko-3.7.0.mpp --patches=x-shim-1.7.0.mpp -o build/x-12.2.0-patched.apkm apps/twitter/apks/x-12.2.0.apkm`.
      - **SUCCESS — login attestation PASSES on re-signed 12.2.0 (unrooted).** User logged in with username/password; the home "For you" feed loads real tweets (screenshot `build/x122-loggedin.png`). Logcat shows `Finsky: Integrity key attestation record generated successfully` and **zero** `AttestationDenied` / `UNREGISTERED_ON_API_CONSOLE` / login errors. So the prior "server-side attestation blocks login on any re-signed build" claim was 12.4.1-era and does **not** hold at 12.2.0 — the whole flow (patch → boot → login → feed) works unrooted. Why login passes despite the changed signing cert: the 12.2.0 OAuth/login path evidently isn't gating on the Play cert-fingerprint the way 12.4.1 does (or x-shim's shim keeps the attestation surface satisfied). **Net: on this host the shipping recipe for a working ad-reduced X on an unrooted phone is `morphe-cli patch --patches=piko-3.7.0.mpp --patches=x-shim-1.7.0.mpp -o out.apk <X-12.2.0 APKM>` then `adb install` (single merged universal APK, plain install not install-multiple).** Feature-verification: **user confirmed the Piko patches (ad removal etc.) are working** on the live logged-in build. End-to-end verified: patch → boot → login → feed → features active, all on the unrooted device.
  - **PairIP flavors differ per app.** hidratespark defeats only pairip's *licensecheck* (`com.pairip.licensecheck.LicenseClient` — a Java Play-ownership gate, no-op to success; no native-VM entanglement there). X adds *VM virtualization + native signature/integrity* on top, which the licensecheck no-op alone does not touch. meetup has no pairip at all (pure R8). A universal `LicenseClient.checkLicense`→`return-void` patch is worth having for the licensecheck-only flavor but does not unlock X.

## Upstreaming

Each subproject is self-contained and pins the same patcher version as ReVanced upstream. To contribute a patch: move the `.kt` file into `patches/src/main/kotlin/app/revanced/patches/<app>/` in their tree, match their `build.gradle.kts` conventions — the patch source itself shouldn't need changes.
