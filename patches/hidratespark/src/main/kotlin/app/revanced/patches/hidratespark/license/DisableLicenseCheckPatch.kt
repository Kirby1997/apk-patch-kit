package app.revanced.patches.hidratenow.license

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

// Target LicenseContentProvider.onCreate() — the entry point that triggers the whole check.
// ContentProviders run at app startup before any Activity.
val BytecodePatchContext.licenseContentProviderOnCreateMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC)
    returnType("Z")
    parameterTypes()
    definingClass("Lcom/pairip/licensecheck/LicenseContentProvider;")
    name("onCreate")
}

// Target initializeLicenseCheck() as a safety net.
val BytecodePatchContext.initializeLicenseCheckMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC)
    returnType("V")
    parameterTypes()
    definingClass("Lcom/pairip/licensecheck/LicenseClient;")
    name("initializeLicenseCheck")
}

// Target the exit action (LicenseClient$1.run()) which calls System.exit(0).
val BytecodePatchContext.exitActionRunMethod by gettingFirstMethodDeclaratively {
    returnType("V")
    parameterTypes()
    definingClass("Lcom/pairip/licensecheck/LicenseClient\$1;")
    name("run")
}

@Suppress("unused")
val disableLicenseCheckPatch = bytecodePatch(
    name = "Disable license check",
    description = "Bypasses the Google Play license verification that blocks sideloaded installs.",
) {
    compatibleWith("hidratenow.com.hidrate.hidrateandroid"("4.6.9"))

    apply {
        // 1. Gut LicenseContentProvider.onCreate() — just return true without
        //    creating LicenseClient or calling initializeLicenseCheck().
        val onCreateSize = licenseContentProviderOnCreateMethod.implementation!!.instructions.size
        licenseContentProviderOnCreateMethod.removeInstructions(0, onCreateSize)
        licenseContentProviderOnCreateMethod.addInstructions(
            0,
            """
                const/4 v0, 0x1
                return v0
            """,
        )

        // 2. Also NOP initializeLicenseCheck() in case anything else calls it.
        initializeLicenseCheckMethod.addInstructions(
            0,
            """
                return-void
            """,
        )

        // 3. Disable the System.exit(0) call as a last resort safety net.
        exitActionRunMethod.addInstructions(
            0,
            """
                return-void
            """,
        )
    }
}
