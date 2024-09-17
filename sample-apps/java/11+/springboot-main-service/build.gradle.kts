/*
 * Copyright Amazon.com, Inc. or its affiliates.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

val javaVersion = if (project.hasProperty("javaVersion")) {
  JavaVersion.toVersion(project.property("javaVersion").toString())
} else {
  JavaVersion.VERSION_11
}

plugins {
  java
  application
  id("org.springframework.boot")
  id("io.spring.dependency-management") version "1.1.0"
  id("com.google.cloud.tools.jib")
  id("org.jetbrains.kotlin.plugin.compose") version "2.0.0"
}


group = "com.amazon.sampleapp"
version = "0.0.1-SNAPSHOT"
java.sourceCompatibility = javaVersion
java.targetCompatibility = javaVersion

repositories {
  mavenCentral()
}

dependencies {
  implementation(platform("software.amazon.awssdk:bom:2.20.78"))
  implementation("org.springframework.boot:spring-boot-starter-web")
  implementation("org.springframework.boot:spring-boot-starter-logging")
  implementation("io.opentelemetry:opentelemetry-api:1.34.1")
  implementation("software.amazon.awssdk:s3")
  implementation("software.amazon.awssdk:sts")
  implementation("com.mysql:mysql-connector-j:8.0.33")
  implementation("org.jetbrains.kotlin:kotlin-stdlib:2.0.20")
  testImplementation("org.jetbrains.kotlin:kotlin-test:2.0.20")
}

jib {
  from {
    image = "openjdk:$javaVersion-jdk"
  }

  to {
    image = "<ECR_IMAGE_LINK>:<TAG>"
  }

  container {
    mainClass = "com.amazon.sampleapp.FrontendService"
    ports = listOf("8080")
  }
}

application {
  mainClass.set("com.amazon.sampleapp.FrontendService")
}
