# ------------------------------------------------------------------------
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0
# -------------------------------------------------------------------------
#
# Shared, language-agnostic Dynamic Instrumentation (DI) environment variables.
# Consumed by the per-language adot-di EC2 test modules (python, java, and
# eventually js) so the DI knobs live in exactly one place. Each caller renders
# the `env_map` output in its own shell style (python: `export K=V`, java: inline
# `K=V \` before the agent command).

variable "service_name" {
  description = "Value for OTEL_SERVICE_NAME (typically <prefix>-<test_id>)."
  type        = string
}

variable "environment" {
  description = "deployment.environment.name value for OTEL_RESOURCE_ATTRIBUTES."
  type        = string
}

variable "enabled" {
  description = "Whether Dynamic Instrumentation is enabled."
  type        = bool
  default     = true
}

variable "probe_poll_interval" {
  description = "Seconds between PROBE config polls. Dropped from the 600s default so the test does not wait minutes."
  type        = number
  default     = 15
}

variable "breakpoint_poll_interval" {
  description = "Seconds between BREAKPOINT config polls. Dropped from the 60s default so the test does not wait minutes."
  type        = number
  default     = 15
}
