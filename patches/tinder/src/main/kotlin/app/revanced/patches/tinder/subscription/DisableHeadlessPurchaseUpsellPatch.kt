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
        headlessPurchaseUpsellOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
