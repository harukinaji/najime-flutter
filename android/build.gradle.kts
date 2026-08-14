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
    afterEvaluate {
        val ext = project.extensions.findByName("android") ?: return@afterEvaluate
        try {
            val getter = ext.javaClass.getMethod("getCompileSdkVersion")
            val current = getter.invoke(ext) as? Int ?: 0
            if (current < 36) {
                val setter = ext.javaClass.getMethod("setCompileSdk", Int::class.javaPrimitiveType)
                setter.invoke(ext, 36)
            }
        } catch (_: Exception) {}
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
