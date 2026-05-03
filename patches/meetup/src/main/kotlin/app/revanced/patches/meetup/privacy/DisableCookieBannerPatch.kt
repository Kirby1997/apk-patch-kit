package app.revanced.patches.meetup.privacy

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

// Meetup embeds the OneTrust cookie-consent SDK. On fresh install, IntroFragment
// gates the login screen behind OTPublishersHeadlessSDK.shouldShowBanner(); when
// true, it calls setupUI and renders the consent banner.
//
// Earlier approach forced every getConsentStatusForGroupId / getConsentStatusForSDKId
// call to return 0 (rejected). That was too blunt — it also rejected C0001
// (Strictly Necessary) and C0003 (Functional), which broke downstream features
// that key off functional-category consent (Google Maps tiles stopped loading).
// It also never persisted a decision, so the banner came back next launch.
//
// New approach: intercept shouldShowBanner() to programmatically save a proper
// "Banner - Reject All" decision through OneTrust's own API, then return false
// so the banner doesn't render. OneTrust writes real per-category consent to
// SharedPreferences, broadcasts the usual consent-change intents to Meetup's
// receivers, and downstream lookups return OneTrust's natural values (0 for
// rejected categories, 1 for Strictly Necessary).

private const val OT_SDK = "Lcom/onetrust/otpublishers/headless/Public/OTPublishersHeadlessSDK;"

val BytecodePatchContext.otShouldShowBannerMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC)
    returnType("Z")
    parameterTypes()
    definingClass(OT_SDK)
    name("shouldShowBanner")
}

@Suppress("unused")
val disableCookieBannerPatch = bytecodePatch(
    name = "Auto-reject cookie banner",
    description = "Programmatically persists a 'Banner - Reject All' decision through OneTrust and suppresses the consent banner, so the user is never prompted and non-essential tracking is rejected on every launch.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        otShouldShowBannerMethod.addInstructions(
            0,
            """
                const-string v0, "Banner - Reject All"
                invoke-virtual {p0, v0}, $OT_SDK->saveConsent(Ljava/lang/String;)V
                const/4 v0, 0x0
                return v0
            """,
        )
    }
}
