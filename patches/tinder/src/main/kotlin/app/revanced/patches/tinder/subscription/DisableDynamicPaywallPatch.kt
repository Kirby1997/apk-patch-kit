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
        dynamicPaywallOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
