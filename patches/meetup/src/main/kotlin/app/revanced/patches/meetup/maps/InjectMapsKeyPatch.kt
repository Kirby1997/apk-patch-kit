package app.revanced.patches.meetup.maps

import app.revanced.patcher.patch.resourcePatch
import app.revanced.patcher.patch.stringOption
import org.w3c.dom.Element

// Meetup's production Google Maps API key in AndroidManifest.xml is locked by
// Google Cloud Console to the (com.meetup, <Meetup-production-cert-SHA1>) pair.
// Sideloaded builds re-sign with our own keystore, so the fingerprint changes
// and Google rejects tile requests server-side — the map surface renders blank
// with no on-device error code. Pass -O "mapsKey=YOUR_KEY" to inject a key you
// control (register it against the cert fingerprint printed by patch-apks.sh).

@Suppress("unused")
val injectMapsKeyPatch = resourcePatch(
    name = "Inject Google Maps API key",
    description = "Replaces the manifest's com.google.android.maps.v2.API_KEY with a user-supplied key. REQUIRED for Maps to render on sideloaded builds — Meetup's production key is cert-fingerprint-locked and rejects requests from any re-signed APK.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    val mapsKey by stringOption(
        key = "mapsKey",
        default = null,
        description = "Google Cloud Maps SDK for Android API key. Leave empty to skip (Maps will stay broken).",
        required = false,
    )

    execute {
        val key = mapsKey?.takeIf { it.isNotBlank() } ?: return@execute

        document("AndroidManifest.xml").use { doc ->
            val nodes = doc.getElementsByTagName("meta-data")
            var replaced = false
            for (i in 0 until nodes.length) {
                val el = nodes.item(i) as? Element ?: continue
                if (el.getAttribute("android:name") == "com.google.android.maps.v2.API_KEY") {
                    el.setAttribute("android:value", key)
                    replaced = true
                }
            }
            check(replaced) {
                "meta-data com.google.android.maps.v2.API_KEY not found in AndroidManifest.xml"
            }
        }
    }
}
