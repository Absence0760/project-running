allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// AGP 8.13+ requires every Android library to compile against
// compileSdk >= 34. Some Flutter plugins (e.g. flutter_reactive_ble's
// `reactive_ble_mobile` 5.4.2) hardcode `compileSdkVersion 33` in
// their own android/build.gradle, which AGP rejects with
//   "AGP requires compileSdk to be set... is currently compiled
//   against android-33."
// We bump compileSdk on every Android library subproject in
// `afterEvaluate` so it runs *after* the plugin's own `android { }`
// block. This block must register BEFORE the `evaluationDependsOn`
// below — otherwise that forces early eval and the
// `afterEvaluate` registration trips
//   "Cannot run Project.afterEvaluate when the project is already
//   evaluated."
subprojects {
    afterEvaluate {
        val androidLib = extensions.findByType<com.android.build.gradle.LibraryExtension>()
        if (androidLib != null) {
            androidLib.compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

// Several third-party Flutter plugins still pin sourceCompatibility /
// targetCompatibility to JavaVersion.VERSION_1_8, which JDK 17's
// javac warns is obsolete on every build. We can't override
// `compileOptions` post-AGP-config (it's finalized), so suppress
// the obsolete-options warning across all subprojects — the
// canonical fix per the JDK's own message:
//   "To suppress warnings about obsolete options, use -Xlint:-options."
// Java 8 source compiles cleanly on JDK 17; the warning is noise
// until each plugin upstream bumps its own source level.
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
