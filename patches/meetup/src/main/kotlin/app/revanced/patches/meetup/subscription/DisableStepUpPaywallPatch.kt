package app.revanced.patches.meetup.subscription

import app.revanced.patcher.accessFlags
import app.revanced.patcher.definingClass
import app.revanced.patcher.extensions.addInstructions
import app.revanced.patcher.extensions.removeInstructions
import app.revanced.patcher.gettingFirstMethodDeclaratively
import app.revanced.patcher.name
import app.revanced.patcher.parameterTypes
import app.revanced.patcher.patch.BytecodePatchContext
import app.revanced.patcher.patch.bytecodePatch
import app.revanced.patcher.returnType
import com.android.tools.smali.dexlib2.AccessFlags

// StepUpActivity is the single destination for every Meetup+ paywall popup the
// app surfaces outside the dedicated subscription screen: RSVP "Going", compose
// message, attendees, waitlist, group members, and profile all eventually
// invoke-virtual launch(Intent) with a component targeting this class. Making
// onCreate call super and finish() immediately kills every such popup at the
// destination — we don't have to chase each trigger site individually.
val BytecodePatchContext.stepUpOnCreateMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("Landroid/os/Bundle;")
    definingClass("Lcom/meetup/subscription/stepup/StepUpActivity;")
    name("onCreate")
}

@Suppress("unused")
val disableStepUpPaywallPatch = bytecodePatch(
    name = "Disable step-up paywalls",
    description = "Closes the Meetup+ step-up paywall Activity before it renders, blocking every popup that routes through it (RSVP, messaging, attendees, waitlist, group members, profile).",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        val instructionCount = stepUpOnCreateMethod.implementation!!.instructions.size
        stepUpOnCreateMethod.removeInstructions(0, instructionCount)
        stepUpOnCreateMethod.addInstructions(
            0,
            """
                invoke-super {p0, p1}, Lcom/meetup/subscription/stepup/Hilt_StepUpActivity;->onCreate(Landroid/os/Bundle;)V
                invoke-virtual {p0}, Lcom/meetup/subscription/stepup/StepUpActivity;->finish()V
                return-void
            """,
        )
    }
}
