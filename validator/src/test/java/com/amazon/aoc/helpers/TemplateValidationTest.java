package com.amazon.aoc.helpers;

import com.github.mustachejava.DefaultMustacheFactory;
import com.github.mustachejava.MustacheFactory;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.FileReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

/**
 * Validates template and configuration files to catch syntax errors before they reach production.
 * These tests prevent issues like PR #556/#557 where comments in mustache files broke parsing.
 */
public class TemplateValidationTest {

    /**
     * Validates that all mustache template files can be compiled.
     * Uses the same MustacheFactory that production code uses to ensure consistency.
     */
    @Test
    public void testAllMustacheFilesCompile() throws Exception {
        MustacheFactory mf = new DefaultMustacheFactory();
        Path resourcesPath = Paths.get("src/main/resources");

        try (Stream<Path> paths = Files.walk(resourcesPath)) {
            paths.filter(Files::isRegularFile)
                 .filter(p -> p.toString().endsWith(".mustache"))
                 .forEach(path -> {
                     assertDoesNotThrow(() -> {
                         try (FileReader reader = new FileReader(path.toFile())) {
                             mf.compile(reader, path.toString());
                         }
                     }, "Failed to compile mustache template: " + path);
                 });
        }
    }

    /**
     * Validates that all YAML configuration files parse correctly.
     * Catches syntax errors in validation config files before they cause runtime failures.
     */
    @Test
    public void testAllYamlFilesParseCorrectly() throws Exception {
        Yaml yaml = new Yaml();
        Path resourcesPath = Paths.get("src/main/resources");

        try (Stream<Path> paths = Files.walk(resourcesPath)) {
            paths.filter(Files::isRegularFile)
                 .filter(p -> p.toString().endsWith(".yml") || p.toString().endsWith(".yaml"))
                 .forEach(path -> {
                     assertDoesNotThrow(() -> {
                         try (FileReader reader = new FileReader(path.toFile())) {
                             yaml.load(reader);
                         }
                     }, "Failed to parse YAML file: " + path);
                 });
        }
    }
}
