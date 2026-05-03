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

// DisableStepUpPaywallPatch closes the *legacy* paywall destination
// (Lcom/meetup/subscription/stepup/StepUpActivity;). Newer Compose-driven
// paywall flows — profile view, compose-message, and the other MeetupPlus
// upsells that resolve through the Lwa/a; intent factory at pswitch_d / _b —
// land on Lcom/meetup/feature/membersub/MemberSubActivity; (Compose) and
// Lcom/meetup/feature/membersub/MemberSubWebViewActivity; (WebView fallback).
// The StepUp patch doesn't catch them because wa/a;->q resolves to
// MemberSubActivity, not StepUpActivity. We apply the same technique —
// super.onCreate then finish() — to both MemberSub destinations so every
// Compose-era paywall is killed at the Activity level.
//
// Leaves Lcom/meetup/feature/membersub/MemberSubManageSubscriptionActivity;
// (pswitch_c) alone — that's the "Manage membership" screen for existing
// Plus users, not a paywall.

val BytecodePatchContext.memberSubOnCreateMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("Landroid/os/Bundle;")
    definingClass("Lcom/meetup/feature/membersub/MemberSubActivity;")
    name("onCreate")
}

val BytecodePatchContext.memberSubWebViewOnCreateMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("Landroid/os/Bundle;")
    definingClass("Lcom/meetup/feature/membersub/MemberSubWebViewActivity;")
    name("onCreate")
}

@Suppress("unused")
val disableMemberSubPaywallPatch = bytecodePatch(
    name = "Disable MemberSub paywalls",
    description = "Closes the Compose-era Meetup+ paywall activities (MemberSubActivity and MemberSubWebViewActivity) before they render, blocking the popups that profile views, message composition, and other upsells now route through.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        val memberSubCount = memberSubOnCreateMethod.implementation!!.instructions.size
        memberSubOnCreateMethod.removeInstructions(0, memberSubCount)
        memberSubOnCreateMethod.addInstructions(
            0,
            """
                invoke-super {p0, p1}, Lcom/meetup/feature/membersub/Hilt_MemberSubActivity;->onCreate(Landroid/os/Bundle;)V
                invoke-virtual {p0}, Lcom/meetup/feature/membersub/MemberSubActivity;->finish()V
                return-void
            """,
        )

        val webViewCount = memberSubWebViewOnCreateMethod.implementation!!.instructions.size
        memberSubWebViewOnCreateMethod.removeInstructions(0, webViewCount)
        memberSubWebViewOnCreateMethod.addInstructions(
            0,
            """
                invoke-super {p0, p1}, Lcom/meetup/feature/membersub/Hilt_MemberSubWebViewActivity;->onCreate(Landroid/os/Bundle;)V
                invoke-virtual {p0}, Lcom/meetup/feature/membersub/MemberSubWebViewActivity;->finish()V
                return-void
            """,
        )
    }
}
