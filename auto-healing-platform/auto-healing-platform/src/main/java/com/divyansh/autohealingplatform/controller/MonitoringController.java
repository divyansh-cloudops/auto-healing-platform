package com.divyansh.autohealingplatform.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
public class MonitoringController {

    private static final String CONTAINER_NAME = "auto-healing-app";
    private final Path logPath = Path.of("recovery.log");

    @GetMapping("/api/monitoring")
    public Map<String, Object> monitoring() {
        Map<String, Object> result = new LinkedHashMap<>();

        String containerStatus = "unknown";
        String healthStatus = "unknown";
        String startedAt = "";
        long uptimeSeconds = 0;

        try {
            Process process = new ProcessBuilder(
                    "docker", "inspect",
                    "--format",
                    "{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}|{{.State.StartedAt}}",
                    CONTAINER_NAME
            ).redirectErrorStream(true).start();

            String output;

            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                output = reader.lines().collect(Collectors.joining());
            }

            int exitCode = process.waitFor();

            if (exitCode == 0 && output.contains("|")) {
                String[] parts = output.split("\\|", 3);

                containerStatus = parts[0];
                healthStatus = parts[1];
                startedAt = parts.length > 2 ? parts[2] : "";

                if ("running".equals(containerStatus)
                        && !startedAt.isBlank()) {
                    Instant start = Instant.parse(startedAt);
                    uptimeSeconds = Math.max(
                            0,
                            Duration.between(start, Instant.now()).getSeconds()
                    );
                }
            } else {
                containerStatus = "not-found-or-unavailable";
            }

        } catch (Exception e) {
            containerStatus = "monitoring-unavailable";
        }

        List<String> allLogs = readAllLogs();

        long recoveryAttempts = allLogs.stream()
                .filter(line -> line.contains("WARNING:")
                        && (line.contains("Attempting restart")
                        || line.contains("Restarting.")))
                .count();

        long successfulRecoveries = allLogs.stream()
                .filter(line -> line.contains("RECOVERY:")
                        && (line.contains("start command succeeded")
                        || line.contains("restart command succeeded")))
                .count();

        double recoverySuccessRate = recoveryAttempts == 0
                ? 0.0
                : Math.min(
                        100.0,
                        successfulRecoveries * 100.0 / recoveryAttempts
                );

        result.put("container", CONTAINER_NAME);
        result.put("containerStatus", containerStatus);
        result.put("healthStatus", healthStatus);
        result.put("startedAt", startedAt);
        result.put("uptimeSeconds", uptimeSeconds);
        result.put("recoveryCount", successfulRecoveries);
        result.put("recoveryAttempts", recoveryAttempts);
        result.put("successfulRecoveries", successfulRecoveries);
        result.put("recoverySuccessRate", recoverySuccessRate);
        result.put("recoveryLogs", getRecentLogs(allLogs, 20));

        return result;
    }

    @GetMapping("/api/monitoring/history")
    public Map<String, Object> recoveryHistory() {
        Map<String, Object> result = new LinkedHashMap<>();

        List<String> allLogs = readAllLogs();
        List<Map<String, String>> events = new ArrayList<>();

        for (int i = allLogs.size() - 1; i >= 0; i--) {
            String line = allLogs.get(i);

            Map<String, String> event = new LinkedHashMap<>();
            event.put("message", line);
            event.put("type", classifyLog(line));

            events.add(event);
        }

        result.put("container", CONTAINER_NAME);
        result.put("totalLogEntries", allLogs.size());
        result.put("history", events);

        return result;
    }

    private String classifyLog(String line) {
        if (line.contains("RECOVERY:")) {
            return "RECOVERY";
        }

        if (line.contains("WARNING:")) {
            return "WARNING";
        }

        if (line.contains("ERROR:")) {
            return "ERROR";
        }

        return "INFO";
    }

    private List<String> getRecentLogs(List<String> logs, int limit) {
        List<String> recentLogs = new ArrayList<>();
        int startIndex = Math.max(0, logs.size() - limit);

        for (int i = logs.size() - 1; i >= startIndex; i--) {
            recentLogs.add(logs.get(i));
        }

        return recentLogs;
    }

    private List<String> readAllLogs() {
        try {
            if (Files.exists(logPath)) {
                return Files.readAllLines(logPath);
            }
        } catch (Exception ignored) {
            // An empty history is returned when the log cannot be read.
        }

        return List.of();
    }
}