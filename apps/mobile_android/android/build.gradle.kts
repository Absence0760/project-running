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
