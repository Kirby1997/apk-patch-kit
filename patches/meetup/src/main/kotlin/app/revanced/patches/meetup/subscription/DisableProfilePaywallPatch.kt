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

// All "tap a profile" / "see full profile" paywall popups funnel through a single
// static accessor on the profile-feature interface. It builds the upsell intent
// and calls launch() on the ProfileActivity's ActivityResultLauncher. No-oping it
// kills every Profile-flavored Meetup+ popup at the source.
val BytecodePatchContext.profilePaywallLauncherMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC)
    returnType("V")
    parameterTypes(
        "Lcom/meetup/feature/profile/e;",
        "Lcom/meetup/shared/meetupplus/MeetupPlusPaywallType;",
        "Lcom/meetup/library/tracking/data/conversion/OriginType;",
        "Lcom/meetup/shared/groupstart/z;",
        "Lln/a;",
        "I",
    )
    definingClass("Lcom/meetup/feature/profile/e;")
    name("a")
}

@Suppress("unused")
val disableProfilePaywallPatch = bytecodePatch(
    name = "Disable profile paywall",
    description = "Stops the Meetup+ subscription popup from appearing when tapping a member's name or 'See full profile'.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        profilePaywallLauncherMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
