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

// LaunchPaywallFlow.invoke (obfuscated to method `c`) is the central entry that
// every paywallflow-routed paywall passes through. Returning immediately stops
// every popup that funnels through it without having to chase individual
// dialog/activity entry points. Tradeoff: this also blocks user-initiated
// upgrade flows from Settings → "Get Tinder Plus / Gold / Platinum" — keep the
// app's purchase flow non-functional while this patch is active.
val BytecodePatchContext.launchPaywallFlowInvokeMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("Luc1/a;", "Landroidx/appcompat/app/n;")
    definingClass("Lcom/tinder/feature/paywallflow/internal/delegates/a;")
    name("c")
}

@Suppress("unused")
val disablePaywallFlowPatch = bytecodePatch(
    name = "Disable paywall flow",
    description = "Short-circuits the central LaunchPaywallFlow entry. Suppresses every paywall routed through paywallflow but also disables legitimate purchase flows.",
) {
    compatibleWith("com.tinder"("17.15.0"))

    apply {
        launchPaywallFlowInvokeMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
