package app.revanced.patches.hidratenow.premium

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

val BytecodePatchContext.getIfUserHasPremiumMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Z")
    parameterTypes()
    definingClass("Lcom/hidrate/iap/BillingRepository;")
    name("getIfUserHasPremium")
}

val BytecodePatchContext.isPurchasedMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Z")
    parameterTypes()
    definingClass("Lcom/hidrate/iap/localdb/GlowStudioEntitlement;")
    name("isPurchased")
}

@Suppress("unused")
val disablePaymentCheckPatch = bytecodePatch(
    name = "Disable payment check",
    description = "Bypasses the premium subscription check so all features are unlocked.",
) {
    compatibleWith("hidratenow.com.hidrate.hidrateandroid"("4.6.9"))

    apply {
        // Patch BillingRepository.getIfUserHasPremium() to always return true.
        // Original method checks: isSubscribed == Boolean.TRUE
        // Prepend "return true" so original code is never reached.
        getIfUserHasPremiumMethod.addInstructions(
            0,
            """
                const/4 v0, 0x1
                return v0
            """,
        )

        // Patch GlowStudioEntitlement.isPurchased() to always return true.
        // Original method checks if id != -1 && entitled == true.
        // Prepend "return true" so original code is never reached.
        isPurchasedMethod.addInstructions(
            0,
            """
                const/4 v0, 0x1
                return v0
            """,
        )
    }
}
