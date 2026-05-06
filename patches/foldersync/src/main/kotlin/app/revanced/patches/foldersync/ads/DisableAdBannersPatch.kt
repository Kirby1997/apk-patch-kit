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

// AppAdmobBannerLoader implements the kmp-ui Lzq/a; "BannerLoader" interface
// for the lite flavor. Its only virtual method, a(String, Composer, Int)V,
// is the @Composable that every screen embeds wherever a banner ad slot
// belongs (file-list footer, transfers, etc). Returning at offset 0 skips
// all Compose machinery — the parent's startRestartGroup tolerates a
// composable that renders nothing, so the banner area collapses everywhere.
val BytecodePatchContext.appAdmobBannerLoaderRenderMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.FINAL)
    returnType("V")
    parameterTypes("Ljava/lang/String;", "Lw1/u;", "I")
    definingClass("Ldk/tacit/android/foldersync/ads/AppAdmobBannerLoader;")
    name("a")
}

@Suppress("unused")
val disableAdBannersPatch = bytecodePatch(
    name = "Disable AdMob banners",
    description = "Turns the AppAdmobBannerLoader composable into a no-op so the lite-version banner ad never renders.",
) {
    compatibleWith("dk.tacit.android.foldersync.lite"("4.8.5"))

    apply {
        appAdmobBannerLoaderRenderMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
