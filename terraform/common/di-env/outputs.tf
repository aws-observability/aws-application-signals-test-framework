# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------

# DI environment variables rendered as newline-joined `export K=V` lines, ready to
# drop into a bash user-data heredoc. The per-language adot-di EC2 modules consume
# this single output so the DI knobs live in one place.
output "export_lines" {
  description = "Shared DI environment variables as bash `export K=V` lines."
  value = join("\n", [
    "export OTEL_AWS_DYNAMIC_INSTRUMENTATION_ENABLED=${var.enabled ? "true" : "false"}",
    "export OTEL_AWS_DYNAMIC_INSTRUMENTATION_PROBE_POLL_INTERVAL=${var.probe_poll_interval}",
    "export OTEL_AWS_DYNAMIC_INSTRUMENTATION_BREAKPOINT_POLL_INTERVAL=${var.breakpoint_poll_interval}",
    "export OTEL_SERVICE_NAME=${var.service_name}",
    "export OTEL_RESOURCE_ATTRIBUTES=\"deployment.environment.name=${var.environment}\"",
  ])
}
