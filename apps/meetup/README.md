# meetup

- **Package:** `com.meetup`
- **Target version:** `2026.04.10.2881`
- **Patches module:** `:patches:meetup`

## Patches

| Patch | What it does |
|-------|--------------|
| Disable intro paywall | Forces `AppSettings.isIntroPaywallEnabled()` false so the "Connect More with Meetup+" popup never opens on fresh login. |
| Disable profile paywall | No-ops the static accessor `Lcom/meetup/feature/profile/e;->a(...)V` that every "tap a member" / "see full profile" upsell launches through. |
| Disable step-up paywalls | Overrides `StepUpActivity.onCreate` so the activity calls super then immediately `finish()`es. `StepUpActivity` is the legacy paywall destination — RSVP "Going", waitlist, group members, attendees burger menu — so this catches every popup routed through it at the destination without chasing each trigger site. |
| Disable MemberSub paywalls | Same technique applied to `MemberSubActivity` and `MemberSubWebViewActivity` — the Compose-era paywall destinations that the `Lwa/a;` intent factory resolves to (profile views, message composition, and other newer upsells). StepUpActivity only covers the legacy flows; MemberSub covers the new ones. |
| Disable Meetup+ trial panels | `return-void` at offset 0 of `Lcom/meetup/feature/home/composables/x0;->d` (the `MeetupPlusTrialBanner` composable in `YourGroupsSection.kt`), so every screen that embeds the "Try Meetup+ free for 7 days" banner renders nothing instead. |
| Hide attendees paywall panels | `return-void` on the `EventInsightsComponent` composable (the event-page "Learn more about attendees / Unlock full details" teaser) and on `AttendeeListMemberPlusUpsell` (the "Learn more about who will be there. Try for free." banner on the Attendees list). |
| Auto-reject cookie banner | Intercepts `OTPublishersHeadlessSDK.shouldShowBanner()` to call `saveConsent("Banner - Reject All")` through OneTrust's own API, then returns false so the banner never renders. OneTrust writes real per-category consent to SharedPreferences and broadcasts the usual consent-change intents — the decision persists across launches and downstream consent queries return OneTrust's natural values (0 for rejected categories, 1 for Strictly Necessary). |
| Unblur profile content | Patches all four `androidx.compose.ui.draw.BlurKt` overloads to return the source `Modifier` unchanged, revealing the gated profile fields, group lists and member rows the app already loaded into memory. |
| Inject Google Maps API key | Replaces the manifest's `com.google.android.maps.v2.API_KEY` with a user-supplied key. **Required for Maps to render on sideloaded builds** — Meetup's bundled key is locked to their production cert fingerprint by Google Cloud Console, so tiles are rejected server-side once the APK is re-signed. See [Google Maps](#google-maps) below. |

### Target classes (v2026.04.10.2881)

Anchors expected to drift on app updates:

- **Intro paywall switch:** `Lcom/meetup/base/settings/AppSettings;->isIntroPaywallEnabled()Z` — caller: `Lcom/meetup/feature/explore/v1;`
- **Profile paywall launcher:** `Lcom/meetup/feature/profile/e;->a(Lcom/meetup/feature/profile/e;Lcom/meetup/shared/meetupplus/MeetupPlusPaywallType;Lcom/meetup/library/tracking/data/conversion/OriginType;Lcom/meetup/shared/groupstart/z;Lln/a;I)V`
- **Step-up paywall activity:** `Lcom/meetup/subscription/stepup/StepUpActivity;->onCreate(Landroid/os/Bundle;)V` (super: `Lcom/meetup/subscription/stepup/Hilt_StepUpActivity;`). The intent-factory `Lwa/b;` resolves paywall component names to `com.meetup.subscription.stepup.StepUpActivity` at `pswitch_4`.
- **MemberSub paywall activities:** `Lcom/meetup/feature/membersub/MemberSubActivity;->onCreate(Landroid/os/Bundle;)V` (super: `Hilt_MemberSubActivity`) and `Lcom/meetup/feature/membersub/MemberSubWebViewActivity;->onCreate(Landroid/os/Bundle;)V` (super: `Hilt_MemberSubWebViewActivity`). Intent-factory `Lwa/a;` resolves to these at `pswitch_d` and `pswitch_b` respectively — `wa/a.q` (the constant the profile paywall launcher passes) routes to `MemberSubActivity`.
- **Trial banner composable:** `Lcom/meetup/feature/home/composables/x0;->d(ILandroidx/compose/runtime/Composer;Landroidx/compose/ui/Modifier;Lln/a;)V` — confirmed via the `traceEventStart` call `"com.meetup.feature.home.composables.MeetupPlusTrialBanner (YourGroupsSection.kt:442)"` in its body.
- **Attendees paywall composables:**
  - `Log/f;->d(Ljava/lang/String;ILln/a;Lln/a;Llh/b;Log/h;Landroidx/compose/runtime/Composer;I)V` — `EventInsightsComponent` (traceEventStart `"com.meetup.shared.insights.EventInsightsComponent (EventInsightsComponent.kt:80)"`).
  - `Lcom/meetup/shared/attendees/q;->e(ZLln/k;Landroidx/compose/runtime/Composer;I)V` — `AttendeeListMemberPlusUpsell` (traceEventStart `"com.meetup.shared.attendees.AttendeeListMemberPlusUpsell (AttendeeListMainScreen.kt:856)"`).
- **OneTrust cookie banner:** `Lcom/onetrust/otpublishers/headless/Public/OTPublishersHeadlessSDK;->shouldShowBanner()Z` gates `IntroFragment`'s banner setup. The patch calls `saveConsent(Ljava/lang/String;)V` with `"Banner - Reject All"` (constant `Lcom/onetrust/otpublishers/headless/Public/OTConsentInteractionType;->BANNER_REJECT_ALL`) on `this` before returning false.
- **Blur overlays:** `Landroidx/compose/ui/draw/BlurKt;` overloads `blur-1fqS-gw`, `blur-1fqS-gw$default`, `blur-F8QBwvs`, `blur-F8QBwvs$default`
- **Google Maps API key:** `AndroidManifest.xml` `<meta-data android:name="com.google.android.maps.v2.API_KEY" android:value="..."/>` under the `<application>` element. The resource patch walks every `meta-data` node and rewrites the matching one's `android:value`.

> Scaffolded by `add-app.sh` / `add-app.bat`, which pulled the APK (and any splits) from a connected device via `adb pull`. Re-running the script on a different device with the same package produces the same `apps/<name>/` layout.

## APKs

The `apks/` directory is git-ignored — APKs are the vendor's IP and cannot be redistributed here. Obtain them yourself from a reputable mirror (or re-run `add-app.sh` against a device that has the app installed) and place them in `apks/`.

Expected files and checksums (SHA-256):

| File | SHA-256 |
|------|---------|
| `base.apk` | `f394e3c07d4193378bb6d46bf4d1009cfe1e064d33e781eea73025d5e82817d2` |
| `com.meetup.apks` | `c63d7fd268e43d5aadbcd4491a8565624c4ab3624abe4d08ee6fec73f3fb2511` |
| `split_config.arm64_v8a.apk` | `02c74c7ff0042c7001093d392ee096a60ccb2e9895fa3f27a0b178c786fa87ed` |
| `split_config.en.apk` | `37da737dca4ab3d189aa66ce970e4fe757f54bc7a61ee45037815d1ea49c232b` |
| `split_config.xxhdpi.apk` | `c9fedafb6e7f694f35cb89a1a6886b58fab2cc6931c2048ea376a00ca1646cba` |


## Applying patches

From the repo root:

```bash
./patch-apks.sh --app meetup --maps-key AIzaSy...
# or export once:
export MAPS_API_KEY=AIzaSy...
./patch-apks.sh --app meetup
```

Without `--maps-key` / `MAPS_API_KEY` the script still builds a working patched APK but Maps surfaces will render blank — see below.

The driver prints an install line that starts with `adb uninstall com.meetup` because Android rejects an in-place replace when the signing cert changes. After the first install with our keystore, future patched builds upgrade in place (the persistent keystore at `~/.apk-patch-kit/keystore.p12` keeps the cert stable).

## Google Maps

Meetup's `AndroidManifest.xml` ships a Maps API key locked by Google Cloud Console to the pair `(com.meetup, Meetup-production-cert-SHA1)`. Every build produced by `patch-apks.sh` is re-signed with our per-user keystore, so the cert fingerprint no longer matches and Google's tile servers reject the request:

```
Google Android Maps SDK: In the Google Developer Console ...
Ensure that the following Android Key exists:
    API Key: AIzaSy...  (Meetup's bundled key, redacted)
    Android Application (<cert_fingerprint>;<package_name>): <our-keystore-SHA1>;com.meetup
```

No bytecode patch can work around this — the check is server-side. The fix is to inject your own key. One-time setup:

1. Go to [Google Cloud Console](https://console.cloud.google.com/) → create (or pick) a project.
2. **APIs & Services → Library** → enable **Maps SDK for Android**.
3. **APIs & Services → Credentials → Create credentials → API key**.
4. Edit the new key → **Application restrictions → Android apps → Add an item**:
   - Package name: `com.meetup`
   - SHA-1 certificate fingerprint: the fingerprint `patch-apks.sh` prints on every run (`Keystore cert SHA-1: AB:CD:...`). Generated once at `~/.apk-patch-kit/keystore.p12` and reused forever, so you only register it once.
5. **API restrictions → Restrict key → Maps SDK for Android** (keeps the key useless if it leaks).
6. Pass the key to the patcher via `--maps-key` or the `MAPS_API_KEY` env var.

You're responsible for any quota usage on that key — the Maps SDK free tier covers typical personal use comfortably.

## Writing patches

Place Kotlin patch files under `patches/meetup/src/main/kotlin/app/revanced/patches/meetup/`. Each patch should:

- Use the `bytecodePatch { ... }` DSL
- Declare `compatibleWith("com.meetup"("2026.04.10.2881"))`
- Anchor fingerprints on fully-qualified class types rather than opcode patterns
