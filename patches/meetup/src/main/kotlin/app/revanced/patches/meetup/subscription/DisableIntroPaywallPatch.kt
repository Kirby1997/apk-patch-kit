package app.revanced.patches.meetup.subscription

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

// AppSettings.isIntroPaywallEnabled gates the "Connect More with Meetup+" paywall
// shown on first launch / fresh login. Forcing it false stops the intro popup
// before the explore screen ever consults it.
val BytecodePatchContext.isIntroPaywallEnabledMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("Z")
    parameterTypes()
    definingClass("Lcom/meetup/base/settings/AppSettings;")
    name("isIntroPaywallEnabled")
}

@Suppress("unused")
val disableIntroPaywallPatch = bytecodePatch(
    name = "Disable intro paywall",
    description = "Suppresses the Meetup+ intro paywall that pops up on fresh login.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        isIntroPaywallEnabledMethod.addInstructions(
            0,
            """
                const/4 v0, 0x0
                return v0
            """,
        )
    }
}
