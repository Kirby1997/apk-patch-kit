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
        boostUpsellOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
