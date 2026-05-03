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
        secretAdmirerUpsellOnCreateViewMethod.addInstructions(
            0,
            """
                invoke-virtual {p0}, Landroidx/fragment/app/q;->dismissAllowingStateLoss()V
                const/4 p1, 0x0
                return-object p1
            """,
        )
    }
}
