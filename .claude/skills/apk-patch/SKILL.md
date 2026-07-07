---
name: apk-patch
description: Use when adding a new app to this ReVanced patch kit, writing/updating a bytecode patch, or building and applying patches to an APK. Covers the full loop — scaffold an app, decompile, reverse-engineer a fingerprint target, write the .kt patch, build the jar, and repackage a signed APK. Drives the repo's add-app.sh / decompile.sh / patch-apks.sh scripts; it does not replace them.
---

# apk-patch

Operational playbook for this repo (**apk-patch-kit**). The bash scripts do the
deterministic work (adb pull, gradle build, sign, repack); this skill is the
judgement layer — when to run which script, and how to reverse-engineer a target
and write the patch that the scripts then build and apply.

Scripts this skill drives, all run from the repo root:

| Script | Does |
|--------|------|
| `./add-app.sh` | Scaffold `apps/<name>/` + `patches/<name>/`, pull APKs from a USB device, record SHA-256s |
| `./decompile.sh <app>` | apktool-decompile `base.apk` → `apps/<app>/decompiled-apktool/` (the smali the patcher fingerprints against) |
| `./gradlew :patches:<app>:build` | Build one app's patch jar → `patches/<app>/build/libs/<app>-patches.jar` |
| `./patch-apks.sh --app <app>` | Apply → sign → repack → print the `adb install(-multiple)` line |

Reference data (obfuscated target classes per app, architecture of the two
pipelines, WSL/adb gotchas) lives in the repo `CLAUDE.md` — consult it, this
skill does not duplicate it.

## Add a new app end-to-end

1. **Connect the device.** USB, unlocked, adb authorised. Verify from a *Windows*
   terminal (not WSL): `adb.exe devices` shows `<serial>  device`.
2. **Scaffold + pull:** `./add-app.sh` (interactive, no args). It picks the
   package, pulls base + splits, derives the shortname from the APK's
   Application label, records SHA-256s, writes `patches/<name>/` +
   `apps/<name>/README.md`, and appends `include(":patches:<name>")` to
   `settings.gradle.kts`.
   - Non-interactive: `./add-app.sh <package>`; force a name with
     `--name <shortname>`; apps that consume an upstream `patches.rvp` (see
     strava) use `--app-only` so no `patches/<name>/` subproject is made.
   - Add `--decompile` to fold step 3 into scaffolding.
3. **Decompile:** `./decompile.sh <name>` → `apps/<name>/decompiled-apktool/`
   (one `smali_classes<N>/` per dex, plus `res/`, `AndroidManifest.xml`,
   `assets/`). Gitignored, regenerable — never commit it. jadx is **not**
   installed on this host; work from the smali tree.
4. **Reverse-engineer the target** (see next section).
5. **Write the patch** under
   `patches/<name>/src/main/kotlin/app/revanced/patches/<name>/<category>/`
   (see the template section).
6. `./gradlew :patches:<name>:build`
7. `./patch-apks.sh --app <name>`
8. Install per the driver's printout (`.apks` bundles need
   `adb install-multiple`, not `adb install`).

## Reverse-engineering recipes

Re-deriving fingerprint targets is the slow part. Standard moves on a fresh
decompile (`APP=apps/<app>/decompiled-apktool`):

- **Find the user-facing string** that labels the screen/popup you're targeting:
  `grep -iE "<keyword>" $APP/res/values/strings.xml` — the resource name
  (e.g. `intro_paywall_*`, `upgrade_likes_*`) often hints at the class that
  consumes it.
- **Narrow to a smali dir by domain noun** before grepping every dex:
  `find $APP -type d \( -iname '*paywall*' -o -iname '*upsell*' -o -iname '*plus*' \)`
- **Find callers of a fully-qualified type** (an enum, paywall trigger, etc.):
  `find $APP -name '*.smali' -exec grep -l '<FullyQualifiedSmaliType>' {} +` —
  slow on a large app (1–10 min); run it backgrounded.
- **Confirm the signature before writing the fingerprint:**
  `grep -nE '\.method|\.locals' <smali file>` — match return type, parameter
  types, and name (including any `-` Kotlin-mangled suffix) exactly. `.locals`
  matters: `addInstructions` cannot address registers above
  `.locals + parameter_count - 1`. If p0/p1 fall above that (high-locals
  methods), use `invoke-virtual/range {p0 .. p0}` and stash results in a low
  local — see `patches/tinder/.../ads/DisableRewardedVideoPatch.kt` for the
  standard-vs-range pair.

Common gate shapes:
- **Blur overlays:** `Landroidx/compose/ui/draw/BlurKt;->blur-*` — patch all four
  overloads to `return-object p0` to no-op every blur.
- **DialogFragment popups** (Tinder pattern): patch
  `onCreateView(...)Landroid/view/View;` at offset 0 with
  `dismissAllowingStateLoss()` + return a null view.
- **Paywall Activity chokepoint** (Meetup pattern): rewrite `onCreate` to
  `invoke-super` (to the Hilt_ parent) + `finish()` + `return-void`.
- **Settings-flag getter:** a boolean like `isIntroPaywallEnabled()Z` → return 0.
- **Compose banner:** a synthetic composable → `return-void` at offset 0
  (Compose treats it as "rendered nothing").

## Writing a patch — template

Fingerprint on **class type + method name + signature**, never on opcode
patterns — types survive obfuscation. Always declare `compatibleWith(...)` or the
patch silently no-ops against other versions.

```kotlin
package app.revanced.patches.<app>.<category>

import app.revanced.patcher.accessFlags
import app.revanced.patcher.definingClass
import app.revanced.patcher.extensions.addInstructions
import app.revanced.patcher.gettingFirstMethodDeclaratively
import app.revanced.patcher.name
import app.revanced.patcher.parameterTypes
import app.revanced.patcher.patch.BytecodePatchContext
import app.revanced.patcher.patch.bytecodePatch
import app.revanced.patcher.returnType
import com.android.tools.smali.dexlib2.AccessFlags

val BytecodePatchContext.<name>Method by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Z")
    parameterTypes()
    definingClass("L<package/slash/path>;")
    name("<methodName>")
}

@Suppress("unused")
val <name>Patch = bytecodePatch(
    name = "<Human-readable patch name>",
    description = "<What this does, user-facing>",
) {
    compatibleWith("<package>"("<version>"))

    apply {
        <name>Method.addInstructions(
            0,
            """
                const/4 v0, 0x1
                return v0
            """,
        )
    }
}
```

For `return true/false/void`, prepend `const/4` + `return` at offset 0 and leave
the original body as dead code — simplest and most robust. Fully rewrite a method
(remove all instructions first) only when the original flow is incompatible — see
the Activity-close patches in
`patches/meetup/.../subscription/DisableSubscriptionPaywallsPatch.kt`.

## File organisation

**One `bytecodePatch` object per feature** — each is listed and toggled by name
via `revanced-cli` (`patch-apks.sh` passes `-e "<Name>"` with `--exclusive`), and
one dead fingerprint after a version bump must not take out its siblings.

**Group patches into one file per `<category>`** when they share a fingerprint
shape or disable body. File grouping is not patch merging: the patcher discovers
patches by reflecting over public top-level `val`s of `bytecodePatch` type
regardless of file, so colocating keeps every patch independently selectable
while letting them share a `private const val` smali body. Worked examples:
`DisableUpsellDialogsPatch.kt` (7 dialogs, one shared body) and
`DisableRewardedVideoPatch.kt` (standard + range bodies) under `patches/tinder/`.

## When a version bump breaks a patch

`compatibleWith(...)` pins each patch. A new app release renames obfuscated
classes, so fingerprints anchored on `L...;` types will fail to resolve. Re-run
`./decompile.sh <app>`, re-derive the targets with the recipes above, and update
the `definingClass` / signature strings and the `compatibleWith` version.
