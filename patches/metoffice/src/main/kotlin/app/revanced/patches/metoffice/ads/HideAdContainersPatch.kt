package app.revanced.patches.metoffice.ads

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

// createViewInstance returns a fresh ReactNativeAdView for every <BannerAd /> the JS
// layer mounts. Forcing visibility=GONE on the freshly-built view collapses the slot
// to zero pixels in the parent layout, so the empty 'Met Office'-branded strip that
// the homepage banner ad slot (AdIds.homepageBanner) leaves behind once RemoveAdsPatch
// has stopped requestAd disappears entirely.
val BytecodePatchContext.bannerCreateViewInstanceMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC)
    returnType("Lio/invertase/googlemobileads/common/ReactNativeAdView;")
    parameterTypes("Lcom/facebook/react/uimanager/ThemedReactContext;")
    definingClass("Lio/invertase/googlemobileads/ReactNativeGoogleMobileAdsBannerAdViewManager;")
    name("createViewInstance")
}

@Suppress("unused")
val hideAdContainersPatch = bytecodePatch(
    name = "Hide ad containers",
    description = "Collapses every AdMob BannerAd slot to zero pixels. Pair with 'Remove ads' to " +
        "also strip the empty Met Office-branded strip the homepage banner slot leaves behind.",
) {
    compatibleWith("uk.gov.metoffice.weather.android"("3.40.0"))

    apply {
        // Original body is three instructions (.locals 1):
        //   0  new-instance v0, ReactNativeAdView
        //   1  invoke-direct {v0, p1}, <init>(Context)
        //   2  return-object v0
        // Insert at index 2 so v0 is fully constructed before we mutate it.
        // p1 (the ThemedReactContext) has already been consumed by the constructor,
        // so reusing its register as an int scratch keeps .locals at 1.
        bannerCreateViewInstanceMethod.addInstructions(
            2,
            """
                const/16 p1, 0x8
                invoke-virtual {v0, p1}, Landroid/view/View;->setVisibility(I)V
            """,
        )
    }
}
