pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

val gprUser: String? by settings
val gprKey: String? by settings

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("https://maven.pkg.github.com/revanced/revanced-patcher")
            credentials {
                username = gprUser ?: System.getenv("GITHUB_ACTOR")
                password = gprKey ?: System.getenv("GITHUB_TOKEN")
            }
        }
    }
}

rootProject.name = "claude-apk-patches"

// Each app is its own Gradle subproject under patches/<app>/ producing its own jar.
// Add new apps here as they are written.
include(":patches:hidratenow")
include(":patches:meetup")
include(":patches:hidratespark")
