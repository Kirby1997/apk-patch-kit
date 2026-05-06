package app.revanced.patches.foldersync.ads

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

// Lip/c; is a Kotlin-generated synthetic Runnable that fronts AdManagerAdMob's
// interstitial flow: a packed-switch on its `a:I` field dispatches to
// case 0 → cu.show(Activity)  (display the cached interstitial)
// default → vh.a.b(Context, "ca-app-pub-1805098847593136/1515170008", ...)
//           which is com.google.android.gms.ads.interstitial.InterstitialAd.load
// The only call sites (MainActivity / activity.b destinationChanged) gate on
// PreferenceManager.getPremiumVersionPurchased() — we don't try to flip that
// pref here because it would unlock unrelated premium features. Instead we
// neutralise the Runnable itself: return-void at offset 0 of run() means
// neither the load nor the show ever fires.
val BytecodePatchContext.interstitialRunnableRunMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes()
    definingClass("Lip/c;")
    name("run")
}

@Suppress("unused")
val disableInterstitialAdsPatch = bytecodePatch(
    name = "Disable AdMob interstitials",
    description = "Neutralises the synthetic Runnable that loads and shows AdMob interstitial ads on navigation events.",
) {
    compatibleWith("dk.tacit.android.foldersync.lite"("4.8.5"))

    apply {
        interstitialRunnableRunMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
