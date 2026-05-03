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
        rewardedVideoModalOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
