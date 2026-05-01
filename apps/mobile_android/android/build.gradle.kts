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

// sentry_flutter 8.x pins its Kotlin source compatibility to 1.6 to
// support older AGP/Kotlin combos. The Kotlin 2.x compiler used by this
// project (see settings.gradle.kts: org.jetbrains.kotlin.android 2.2.20)
// rejects languageVersion = "1.6" with:
//   "Language version 1.6 is no longer supported; please, use version
//    1.8 or greater"
// causing :sentry_flutter:compileDebugKotlin to fail. Override the
// language + api version for that one module so the plugin's bytecode
// keeps building. Removable when we bump sentry_flutter to 9.x (see
// pubspec.yaml — pinned at ^8.0.0; 9.x is a breaking-API release).
subprojects {
    if (project.name == "sentry_flutter") {
        afterEvaluate {
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions {
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                    apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
