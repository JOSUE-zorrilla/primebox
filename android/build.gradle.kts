// android/build.gradle.kts (root)
import org.gradle.api.file.Directory

plugins {
    // No declares AGP / Kotlin aquí para no chocar con lo que trae Flutter
    // Solo deja Google Services si lo usas
    id("com.google.gms.google-services") version "4.4.0" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Redirige build/ como ya hacías
val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Forzar jvmTarget=11 en todos los subproyectos
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions { jvmTarget = "11" }
    }

    // Si lo necesitas:
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
