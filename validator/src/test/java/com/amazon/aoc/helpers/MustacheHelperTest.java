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

public class MustacheHelperTest {

    @Test
    public void testAllMustacheFilesCompile() throws Exception {
        MustacheFactory mf = new DefaultMustacheFactory();
        Path resourcesPath = Paths.get("src/main/resources");
        
        if (!Files.exists(resourcesPath)) {
            return;
        }

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

    @Test
    public void testAllYamlFilesParseCorrectly() throws Exception {
        Yaml yaml = new Yaml();
        Path resourcesPath = Paths.get("src/main/resources");
        
        if (!Files.exists(resourcesPath)) {
            return;
        }

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
