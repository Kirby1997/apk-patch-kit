package app.revanced.patches.meetup.attendees

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

// Two attendee-adjacent upsell panels that non-subscribers see:
//
// 1. EventInsightsComponent — the "Learn more about attendees" section that
//    sits on the event page with an "Unlock full details" button. The whole
//    section is a teaser (R.string.event_page_learn_attendees +
//    R.string.group_insights_cta_unlock_full_details). For a non-subscriber
//    the server only returns placeholder sections, so there is nothing under
//    the teaser to unlock — hiding the section outright is the clean fix.
//    Identified via traceEventStart "com.meetup.shared.insights.EventInsightsComponent
//    (EventInsightsComponent.kt:80)" inside Log/f;->d.
//
// 2. AttendeeListMemberPlusUpsell — the "Learn more about who will be there.
//    Try for free." banner on the Attendees list
//    (R.string.event_insights_cta_not_subscribed). Identified via traceEventStart
//    "com.meetup.shared.attendees.AttendeeListMemberPlusUpsell
//    (AttendeeListMainScreen.kt:856)" inside Lcom/meetup/shared/attendees/q;->e.
//
// Returning at offset 0 skips startRestartGroup, which Compose accepts as
// "this composable rendered nothing" — the panels simply disappear.

val BytecodePatchContext.eventInsightsComponentMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes(
        "Ljava/lang/String;",
        "I",
        "Lln/a;",
        "Lln/a;",
        "Llh/b;",
        "Log/h;",
        "Landroidx/compose/runtime/Composer;",
        "I",
    )
    definingClass("Log/f;")
    name("d")
}

val BytecodePatchContext.attendeeListUpsellMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes(
        "Z",
        "Lln/k;",
        "Landroidx/compose/runtime/Composer;",
        "I",
    )
    definingClass("Lcom/meetup/shared/attendees/q;")
    name("e")
}

@Suppress("unused")
val hideAttendeesPaywallPatch = bytecodePatch(
    name = "Hide attendees paywall panels",
    description = "Hides the 'Learn more about attendees / Unlock full details' teaser on event pages and the 'Learn more about who will be there. Try for free.' banner on the Attendees list.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        val returnVoid = """
            return-void
        """

        eventInsightsComponentMethod.addInstructions(0, returnVoid)
        attendeeListUpsellMethod.addInstructions(0, returnVoid)
    }
}
