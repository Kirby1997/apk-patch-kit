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

// The rewarded-video ad surfaces ("watch an ad to keep swiping / get a Rewind
// back") are BottomSheetDialogFragments. Same disable strategy as the subscription
// upsell dialogs: dismiss + return a null view at the top of onCreateView. Two
// distinct, independently selectable patches share this file.
//
// The disable body differs by register width. RewardedVideoModal has few locals so
// p0/p1 are addressable by the 4-bit invoke-virtual / const-4 forms. The
// adsbouncer sheet has .locals 18 (p0=v18, p1=v19) which those forms cannot reach,
// so it uses invoke-virtual/range and stashes null in a low local.
private const val DISMISS_DIALOG_FRAGMENT = """
    invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
    const/4 p1, 0x0
    return-object p1
"""

private const val DISMISS_DIALOG_FRAGMENT_RANGE = """
    invoke-virtual/range {p0 .. p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
    const/4 v0, 0x0
    return-object v0
"""

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
        adsBouncerRewardedVideoOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT_RANGE)
    }
}

// Sibling rewarded-video modal that lives outside the adsbouncer feature module —
// e.g. the "watch an ad to get a Rewind back" prompt. Same shape, same disable.
val BytecodePatchContext.rewardedVideoModalOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/rewardedvideomodal/internal/ui/RewardedVideoBottomSheetFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableRewardedVideoModalPatch = bytecodePatch(
    name = "Disable rewarded-video modal",
    description = "Suppresses the standalone rewarded-video bottom sheet (e.g. \"watch an ad to get a Rewind\").",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        rewardedVideoModalOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}
