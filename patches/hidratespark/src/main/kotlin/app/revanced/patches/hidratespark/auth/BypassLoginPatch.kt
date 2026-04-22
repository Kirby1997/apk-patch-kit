package app.revanced.patches.hidratenow.auth

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

val BytecodePatchContext.noDisplayOnCreateMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PROTECTED)
    returnType("V")
    parameterTypes("Landroid/os/Bundle;")
    definingClass("Lhidratenow/com/hidrate/hidrateandroid/activities/NoDisplayActivity;")
    name("onCreate")
}

val BytecodePatchContext.needsToUpdateUserParamsMethod by gettingFirstMethodDeclaratively {
    accessFlags(AccessFlags.PUBLIC)
    returnType("Z")
    parameterTypes()
    definingClass("Lhidratenow/com/hidrate/hidrateandroid/parse/User;")
    name("needsToUpdateUserParams")
}

@Suppress("unused")
val bypassLoginPatch = bytecodePatch(
    name = "Bypass login",
    description = "Skips the login screen and goes directly to the main activity.",
) {
    compatibleWith("hidratenow.com.hidrate.hidrateandroid"("4.6.9"))

    apply {
        // Patch NoDisplayActivity.onCreate to always navigate to MainActivity.
        val instructionCount = noDisplayOnCreateMethod.implementation!!.instructions.size
        noDisplayOnCreateMethod.removeInstructions(0, instructionCount)
        noDisplayOnCreateMethod.addInstructions(
            0,
            """
                # Call super.onCreate(savedInstanceState)
                invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V

                # Create intent for MainActivity
                new-instance v0, Landroid/content/Intent;
                const-class v1, Lhidratenow/com/hidrate/hidrateandroid/activities/main/MainActivity;
                invoke-direct {v0, p0, v1}, Landroid/content/Intent;-><init>(Landroid/content/Context;Ljava/lang/Class;)V

                # Start MainActivity
                invoke-virtual {p0, v0}, Lhidratenow/com/hidrate/hidrateandroid/activities/NoDisplayActivity;->startActivity(Landroid/content/Intent;)V

                # Finish this activity
                invoke-virtual {p0}, Lhidratenow/com/hidrate/hidrateandroid/activities/NoDisplayActivity;->finish()V

                return-void
            """,
        )

        // Also patch needsToUpdateUserParams() to return false, so if any other
        // code path hits it (e.g. after a real login), onboarding is skipped.
        needsToUpdateUserParamsMethod.addInstructions(
            0,
            """
                const/4 v0, 0x0
                return v0
            """,
        )
    }
}
