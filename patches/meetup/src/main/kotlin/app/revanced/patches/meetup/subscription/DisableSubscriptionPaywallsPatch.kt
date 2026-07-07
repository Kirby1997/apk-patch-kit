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

// Every Meetup+ subscription paywall surface, grouped by category. Unlike Tinder's
// dialogs these do not share one disable body — they use three mechanisms:
//   * a settings-flag getter forced false (intro paywall),
//   * Activity onCreate rewritten to super + finish() (StepUp / MemberSub),
//   * a launcher/composable short-circuited with return-void (profile / trial).
// Each remains a distinct, independently selectable bytecodePatch; they are
// colocated by category only.

// --- Intro paywall -----------------------------------------------------------
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

// --- Legacy step-up paywall Activity -----------------------------------------
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

// --- Compose-era MemberSub paywall Activities --------------------------------
// disableStepUpPaywallPatch closes the *legacy* paywall destination
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

// --- Profile paywall launcher ------------------------------------------------
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

// --- Meetup+ trial banner composable -----------------------------------------
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
