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
        platinumLikesUpsellOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
