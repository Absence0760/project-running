// Top-level build file — applies to no project itself; plugin versions and
// repositories live in `settings.gradle.kts`.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
