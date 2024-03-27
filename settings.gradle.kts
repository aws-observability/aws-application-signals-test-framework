pluginManagement {
    plugins {
        id("com.google.cloud.tools.jib") version "3.4.0"
        id("org.springframework.boot") version "2.7.17"

    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        mavenLocal()

        maven {
            setUrl("https://oss.sonatype.org/content/repositories/snapshots")
        }
    }
}


// End to end tests
include(":validator")
include(":sample-apps:springboot")
include(":sample-apps:springboot-remote-service")
