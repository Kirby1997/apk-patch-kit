package app.revanced.patches.tinder.subscription

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

// Tinder's upsell/paywall popups are DialogFragments that all share one disable
// strategy: at the top of onCreateView, dismiss the fragment and return a null
// view so nothing renders and the transaction is torn down. Each patch below is a
// distinct, independently selectable bytecodePatch (revanced-cli lists and toggles
// them by name); they are colocated here because they share DISMISS_DIALOG_FRAGMENT
// rather than because they are one unit.
//
// The two rewarded-video ad bottom sheets use the same shape but live in
// ../ads/DisableRewardedVideoPatch.kt. The central LaunchPaywallFlow chokepoint is
// a different mechanism (return-void, and it also disables legit purchases) so it
// stays in DisablePaywallFlowPatch.kt.
private const val DISMISS_DIALOG_FRAGMENT = """
    invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
    const/4 p1, 0x0
    return-object p1
"""

// "Be Seen Faster / Upgrade Likes" Platinum upsell popup. Layout
// res/layout/platinum_likes_upsell_dialog_fragment.xml binds @string/upgrade_likes_title,
// @string/upgrade_likes_subtitle, @string/upgrade_likes. The fragment is added via a
// FragmentTransaction by the deeplink router (idverification/feature/internal/deeplink/b
// pswitch_0), so dismissing on onCreateView and returning a null view both removes the
// fragment and prevents anything from rendering.
val BytecodePatchContext.platinumLikesUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/mylikes/ui/dialog/PlatinumLikesUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disablePlatinumLikesUpsellPatch = bytecodePatch(
    name = "Disable Platinum Likes upsell",
    description = "Suppresses the \"Be Seen Faster / Upgrade Likes\" Tinder Platinum popup.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        platinumLikesUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// "You've liked amazing people! Be Seen faster with Tinder Platinum" upsell — sibling
// to PlatinumLikesUpsellDialogFragment. Triggered from
// LikesSentFragment$observeViewEffect$1 when the view-effect is com.tinder.mylikes.ui.k.
val BytecodePatchContext.myLikesUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/mylikes/ui/dialog/MyLikesUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableMyLikesUpsellPatch = bytecodePatch(
    name = "Disable MyLikes upsell",
    description = "Suppresses the \"You've liked amazing people\" Tinder Platinum popup on the Likes Sent tab.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        myLikesUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// Standard Boost upsell popup ("Get Tinder Plus / Gold / Platinum" prompt shown
// when out of Boosts).
val BytecodePatchContext.boostUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/boost/ui/upsell/BoostUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableBoostUpsellPatch = bytecodePatch(
    name = "Disable Boost upsell",
    description = "Suppresses the standard Boost upsell popup (\"Get Tinder Plus / Gold / Platinum\" prompt that surfaces when out of Boosts).",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        boostUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// HeadlessPurchaseUpsellDialogFragment — the in-app prompt that appears mid-flow
// to confirm a "headless" (one-tap) purchase. Killing it stops the popup and the
// upsell flow it gates.
val BytecodePatchContext.headlessPurchaseUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/headlesspurchaseupsell/internal/view/HeadlessPurchaseUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableHeadlessPurchaseUpsellPatch = bytecodePatch(
    name = "Disable headless purchase upsell",
    description = "Suppresses the headless-purchase confirmation upsell popup.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        headlessPurchaseUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// PrimetimeBoostUpsellDialogFragment — the Primetime Boost variant of the Boost
// upsell popup.
val BytecodePatchContext.primetimeBoostUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/primetimeboostupsell/internal/view/PrimetimeBoostUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disablePrimetimeBoostUpsellPatch = bytecodePatch(
    name = "Disable Primetime Boost upsell",
    description = "Suppresses the Primetime Boost upsell popup.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        primetimeBoostUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// SecretAdmirerUpsellDialogFragment — the Secret Admirer (Gold) upsell popup.
val BytecodePatchContext.secretAdmirerUpsellOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/feature/secretadmirer/internal/view/SecretAdmirerUpsellDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableSecretAdmirerUpsellPatch = bytecodePatch(
    name = "Disable Secret Admirer upsell",
    description = "Suppresses the Secret Admirer (Gold) upsell popup.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        secretAdmirerUpsellOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}

// PaywallDialogFragment is the dynamic, server-driven paywall sheet that the
// LaunchPaywallFlow delegate ends up showing for most upgrade prompts. Many
// non-popup entry points (settings tile, "Get Tinder Plus" buttons) also surface
// this same fragment, so disabling it removes the legitimate upgrade UI too —
// expect to also need disablePaywallFlowPatch for full coverage.
val BytecodePatchContext.dynamicPaywallOnCreateViewMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Landroid/view/View;")
    parameterTypes("Landroid/view/LayoutInflater;", "Landroid/view/ViewGroup;", "Landroid/os/Bundle;")
    definingClass("Lcom/tinder/dynamicpaywall/PaywallDialogFragment;")
    name("onCreateView")
}

@Suppress("unused")
val disableDynamicPaywallPatch = bytecodePatch(
    name = "Disable dynamic paywall sheet",
    description = "Suppresses the generic server-driven paywall sheet (PaywallDialogFragment) that LaunchPaywallFlow renders for most upgrade prompts.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        dynamicPaywallOnCreateViewMethod.addInstructions(0, DISMISS_DIALOG_FRAGMENT)
    }
}
