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

buildCache {
    local {
        isEnabled = true
    }
}


// End to end tests
include(":validator")
include(":sample-apps:java:8:springboot-main-service")
include(":sample-apps:java:8:springboot-remote-service")
include(":sample-apps:java:11+:springboot-main-service")
include(":sample-apps:java:11+:springboot-remote-service")

//id("com.diffplug.spotless") version "6.22.0"
//id("com.github.ben-manes.versions") version "0.50.0"
//id("com.github.jk1.dependency-license-report") version "2.5"
//id("com.github.johnrengelman.shadow") version "8.1.1"
//id("com.google.cloud.tools.jib") version "3.4.0"
//id("io.github.gradle-nexus.publish-plugin") version "1.3.0"
//id("nebula.release") version "18.0.6"
//id("org.springframework.boot") version "2.7.17"
//id("org.owasp.dependencycheck") version "8.4.0"
//
//
//id("org.springframework.boot")
//id("io.spring.dependency-management") version "1.1.0"
//id("com.google.cloud.tools.jib")
