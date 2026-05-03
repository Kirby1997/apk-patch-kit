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
        myLikesUpsellOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
