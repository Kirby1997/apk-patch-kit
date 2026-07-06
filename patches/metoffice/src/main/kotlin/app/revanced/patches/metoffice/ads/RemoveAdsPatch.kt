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

// react-native-google-mobile-ads banner chokepoint. Every banner ad routed through
// the JS <BannerAd /> component lands here to call into AdManagerAdView.loadAd().
// Returning at offset 0 leaves the slot in the layout but never fetches an ad.
val BytecodePatchContext.bannerRequestAdMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PRIVATE)
    returnType("V")
    parameterTypes("Lio/invertase/googlemobileads/common/ReactNativeAdView;")
    definingClass("Lio/invertase/googlemobileads/ReactNativeGoogleMobileAdsBannerAdViewManager;")
    name("requestAd")
}

// Shared entry point for InterstitialAd and RewardedAd (both modules subclass this
// abstract module). The JS bridge calls load(requestId, adUnitId, adRequestOptions);
// returning before the AdLoader runs prevents the ad from ever loading or showing.
val BytecodePatchContext.fullScreenLoadMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("I", "Ljava/lang/String;", "Lcom/facebook/react/bridge/ReadableMap;")
    definingClass("Lio/invertase/googlemobileads/ReactNativeGoogleMobileAdsFullScreenAdModule;")
    name("load")
}

// AppOpenAd module has its own load entry instead of inheriting from FullScreenAdModule.
val BytecodePatchContext.appOpenLoadMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("I", "Ljava/lang/String;", "Lcom/facebook/react/bridge/ReadableMap;")
    definingClass("Lio/invertase/googlemobileads/ReactNativeGoogleMobileAdsAppOpenModule;")
    name("appOpenLoad")
}

@Suppress("unused")
val removeAdsPatch = bytecodePatch(
    name = "Remove ads",
    description = "Stops banner, interstitial, rewarded, and app-open ads from loading by no-opping " +
        "the react-native-google-mobile-ads native bridge entry points.",
) {
    compatibleWith("uk.gov.metoffice.weather.android"("3.40.0"))

    apply {
        bannerRequestAdMethod.addInstructions(0, "return-void")
        fullScreenLoadMethod.addInstructions(0, "return-void")
        appOpenLoadMethod.addInstructions(0, "return-void")
    }
}
