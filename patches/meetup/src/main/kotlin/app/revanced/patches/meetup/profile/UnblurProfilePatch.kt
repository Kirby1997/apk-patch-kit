package app.revanced.patches.meetup.profile

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

// Meetup gates profile fields, group lists and member rows behind Compose's
// Modifier.blur(). We patch the four androidx.compose.ui.draw.BlurKt overloads
// to return the input Modifier untouched, so every blur() call becomes a no-op.
// Side-effect: any cosmetic blur elsewhere in the app is also disabled — but
// nothing in this APK uses BlurKt for purely decorative effect that would matter.

val BytecodePatchContext.blur1fqSgwMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.FINAL)
    returnType("Landroidx/compose/ui/Modifier;")
    parameterTypes(
        "Landroidx/compose/ui/Modifier;",
        "F",
        "F",
        "Landroidx/compose/ui/graphics/Shape;",
    )
    definingClass("Landroidx/compose/ui/draw/BlurKt;")
    name("blur-1fqS-gw")
}

val BytecodePatchContext.blur1fqSgwDefaultMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.SYNTHETIC)
    returnType("Landroidx/compose/ui/Modifier;")
    parameterTypes(
        "Landroidx/compose/ui/Modifier;",
        "F",
        "F",
        "Landroidx/compose/ui/draw/BlurredEdgeTreatment;",
        "I",
        "Ljava/lang/Object;",
    )
    definingClass("Landroidx/compose/ui/draw/BlurKt;")
    name("blur-1fqS-gw\$default")
}

val BytecodePatchContext.blurF8QBwvsMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.FINAL)
    returnType("Landroidx/compose/ui/Modifier;")
    parameterTypes(
        "Landroidx/compose/ui/Modifier;",
        "F",
        "Landroidx/compose/ui/graphics/Shape;",
    )
    definingClass("Landroidx/compose/ui/draw/BlurKt;")
    name("blur-F8QBwvs")
}

val BytecodePatchContext.blurF8QBwvsDefaultMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC, AccessFlags.STATIC, AccessFlags.SYNTHETIC)
    returnType("Landroidx/compose/ui/Modifier;")
    parameterTypes(
        "Landroidx/compose/ui/Modifier;",
        "F",
        "Landroidx/compose/ui/draw/BlurredEdgeTreatment;",
        "I",
        "Ljava/lang/Object;",
    )
    definingClass("Landroidx/compose/ui/draw/BlurKt;")
    name("blur-F8QBwvs\$default")
}

@Suppress("unused")
val unblurProfilePatch = bytecodePatch(
    name = "Unblur profile content",
    description = "Disables the Compose blur overlay Meetup applies to gated profile fields, group lists, and member rows so the underlying data is visible.",
) {
    compatibleWith("com.meetup"("2026.04.10.2881"))

    apply {
        // Each overload takes the source Modifier as p0 and returns a Modifier.
        // Returning p0 unchanged short-circuits the blur graphics layer.
        val passthrough = """
            return-object p0
        """

        blur1fqSgwMethod.addInstructions(0, passthrough)
        blur1fqSgwDefaultMethod.addInstructions(0, passthrough)
        blurF8QBwvsMethod.addInstructions(0, passthrough)
        blurF8QBwvsDefaultMethod.addInstructions(0, passthrough)
    }
}
