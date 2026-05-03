plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    implementation(libs.revanced.patcher)
    implementation(libs.smali)
}

kotlin {
    jvmToolchain(17)
    compilerOptions {
        freeCompilerArgs.addAll("-Xcontext-receivers", "-Xskip-prerelease-check")
    }
}

tasks.jar {
    archiveBaseName.set("tinder-patches")
}
