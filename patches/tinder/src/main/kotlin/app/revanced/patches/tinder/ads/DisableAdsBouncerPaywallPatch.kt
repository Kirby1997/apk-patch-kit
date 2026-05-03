package app.revanced.patches.tinder.ads

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

// RewardedVideoBottomSheet is the "Watch an ad to keep swiping" interstitial
// shown when the user runs out of likes (the AdsBouncer paywall surface).
val BytecodePatchContext.adsBouncerRewardedVideoOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/feature/adsbouncerpaywall/internal/presentation/RewardedVideoBottomSheet;")
    name("onCreateView")
}

@Suppress("unused")
val disableAdsBouncerPaywallPatch = bytecodePatch(
    name = "Disable ads-bouncer rewarded-video paywall",
    description = "Suppresses the \"Watch an ad to keep swiping\" rewarded-video bottom sheet shown when out of likes.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        // Method has .locals 18 + 4 param slots → p0=v18, p1=v19. The 4-bit register
        // instructions `invoke-virtual {p0}` and `const/4 p1` cannot address those, so
        // call via /range and stash null in a low local before returning.
        adsBouncerRewardedVideoOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual/range {p0 .. p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 v0, 0x0
                return-object v0
            """,
        )
    }
}
