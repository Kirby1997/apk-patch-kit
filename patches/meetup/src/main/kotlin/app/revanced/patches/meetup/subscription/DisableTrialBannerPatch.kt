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

// The "Try Meetup+ free for 7 days" panel is a single Compose function —
// MeetupPlusTrialBanner in YourGroupsSection.kt — that every screen embeds
// (home, notifications, explore, group, profile, etc.). Its generated smali
// lives at Lcom/meetup/feature/home/composables/x0;->d, and the traceEventStart
// call in the body still carries the original name so there's no guessing on
// identity. Returning at offset 0 skips startRestartGroup entirely, which
// Compose tolerates as "this composable rendered nothing" — the banner simply
// disappears everywhere it's embedded.
val BytecodePatchContext.meetupPlusTrialBannerMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes(
        "I",
        "Landroidx/compose/runtime/Composer;",
        "Landroidx/compose/ui/Modifier;",
        "Lln/a;",
    )
    definingClass("Lcom/meetup/feature/home/composables/x0;")
    name("d")
}

@Suppress("unused")
val disableTrialBannerPatch = bytecodePatch(
    name = "Disable Meetup+ trial panels",
    description = "Removes the 'Try Meetup+ free for 7 days' banner composable from every screen that embeds it.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        meetupPlusTrialBannerMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
