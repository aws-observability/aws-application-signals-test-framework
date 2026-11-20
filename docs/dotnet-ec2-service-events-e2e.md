# .NET EC2 Service Events E2E Test

Validates that a Service Events-capable ADOT .NET distro, paired with the CloudWatch Agent, emits
the five Service Events signals from an EC2-hosted ASP.NET sample application.

Workflow: `.github/workflows/dotnet-ec2-service-events-test.yml`
Infrastructure: `terraform/dotnet/ec2/service-events/`

## Distro requirements

Service Events for .NET lives in
[aws-otel-dotnet-instrumentation](https://github.com/aws-observability/aws-otel-dotnet-instrumentation).

It is **loaded by the AWS distro plugin itself**, so `OTEL_DOTNET_AUTO_PLUGINS` carries only the
single standard entry the distro's own launch scripts set:

```text
AWS.Distro.OpenTelemetry.AutoInstrumentation.Plugin, AWS.Distro.OpenTelemetry.AutoInstrumentation
```

Naming a Service Events-specific plugin would reference a type that does not exist and fail plugin
loading. Keeping this list identical to the default is also what proves the customer-does-nothing
path works.

Service Events does ship as its own assembly, so provisioning checks that
`AWS.Distro.OpenTelemetry.ServiceEvents.dll` is present in order to fail fast against a distro build
that predates the feature.

The test deliberately does **not** set `OTEL_AWS_SERVICE_EVENTS_ENABLED`. It verifies the bundled
enablement contract: on EC2, enabling Application Signals via
`OTEL_AWS_APPLICATION_SIGNALS_ENABLED=true` enables Service Events when the explicit flag is unset.

## How traffic is generated

A single instance runs the instrumented frontend; there is no remote service, because Service Events
emits autonomously from the frontend. A tmux loop on the instance drives three routes serially:

| Route | Result | Signals it gates |
|---|---|---|
| `/` | 200 | baseline traffic |
| `/success` | 200 | FunctionCall `status=success`, and the latency IncidentSnapshot |
| `/failed-call` | 200 | FunctionCall `status=error` |
| `/exception` | 500 | exception IncidentSnapshot, EndpointErrorMetric |

`/success` makes an in-process `HttpClient` call to the application's own `/health` route. That
keeps a real downstream span in the picture while removing DNS, TLS, and egress from the test
outcome. The application binds to loopback, since all traffic originates on the instance and the
validators query CloudWatch rather than the app.

`/failed-call` targets a closed loopback port so the connection is refused immediately. It exists
because `/exception` cannot produce a FunctionCall error: it throws inside the controller without
making an outbound call, so no `HttpClient` activity is created for FunctionCall to record. The
request itself returns 200, which keeps it distinct from `/exception`.

The DeploymentEvent is emitted once, at startup.

## Signals validated

| Validation | Type | Asserts |
|---|---|---|
| `deployment-event-validation.yml` | cw-log | scope `serviceevents` v1.0, `startup` trigger, VCS provenance |
| `incident-snapshot-validation.yml` | cw-log | `exception` trigger, HTTP 500, exception type, trace/span IDs |
| `incident-snapshot-latency-validation.yml` | cw-log | `latency` trigger, HTTP 200, trace/span IDs |
| `endpoint-error-metric-validation.yml` | promql | `count`, operation, exception dimension |
| `function-call-metric-validation.yml` | promql | `service.function.duration`, function name, caller, `status=success` and `status=error` |

### What FunctionCall covers on .NET, and what it does not

The function name asserted is `System.Net.Http.HttpRequestOut` — an OpenTelemetry `ActivitySource`,
not application code. That is the extent of what .NET can instrument: it derives FunctionCall from
Activities, whereas the Java agent applies bytecode advice to arbitrary methods and Python rewrites
ASTs, so those cells assert real application methods. Same signal name, materially different
coverage; do not read the .NET cell as equivalent.

The practical consequence is in `OTEL_AWS_SERVICE_EVENTS_PACKAGES_INCLUDE`. In Java and Python it
takes code-package prefixes. In .NET it matches the derived
`{ActivitySource.Name}.{OperationName}`, which is why this module defaults it to `System.Net.Http*`.
A configuration ported over from Java would match nothing and present as an absence of traffic
rather than as a misconfiguration.

Log signals land in `/aws/service-events/<service.name>`, which Terraform manages with a one-day
retention so a run does not leave a never-expiring log group behind.

Two details worth knowing when editing the templates:

- The operation key and `url.route` carry **no leading slash** under MVC attribute routing:
  `[Route("/exception")]` resolves to `GET exception` / `exception`. The templates match either
  spelling so they also hold for a minimal-API sample app.
- `duration_ms`, `is_partial`, and `http.response.status_code` arrive as JSON numbers and booleans,
  so template regexes are matched against their string form.

`CWLogValidatorServiceEventsTest` runs the shipped templates against captured records offline, so
template regressions surface without needing an AWS run.

## Workflow inputs

| Input | Default | Notes |
|---|---|---|
| `aws-region` | required | |
| `caller-workflow-name` | required | |
| `dotnet-version` | `8.0` | `8.0`, `9.0`, `10.0` |
| `distro-source` | `release` | `release` or `staging` |
| `staging-distro-name` | glibc-x64 zip | used when `distro-source: staging` |
| `adot-distro-uri` | derived | `s3://` or `https://` override |
| `sample-app-zip` | regional prod ZIP | `s3://` or `https://` override |
| `sample-app-git-commit-sha` | caller's SHA | source revision of the sample-app ZIP |
| `cw-agent-rpm-uri` | derived | `s3://` or `https://` override |
| `framework-ref` | caller SHA, or `main` externally | framework revision to check out |

Inputs are validated before AWS credentials are requested, and artifact locations are passed as URIs
rather than shell commands, so nothing a caller supplies is executed on the instance.

Callers must use `secrets: inherit`.

`sample-app-git-commit-sha` is stamped on every emitted event as `vcs.ref.head.revision`, and the log
templates pin it exactly. Supply it when you built the ZIP yourself; otherwise it defaults to the
caller's SHA and provenance is nominal rather than artifact-derived.

## Prerequisites

The published sample-app ZIP must contain `/health`, `/success`, and `/exception`. It is built by
`dotnet-sample-app-s3-deploy.yml`, which runs on manual dispatch, so a source change to the sample
app is not reflected until that workflow is run. Provisioning verifies each route's status code and
fails early with an explicit message when the artifact predates them.

That ZIP is shared with the other .NET tests — see `sample-apps/README.md` before republishing.

Consumer repositories run `validate-e2e-tests-are-accounted-for.yml`, which requires every
`dotnet-*-test.yml` in this repository to either be called or be listed in that workflow's
`exclusions` input.

## Running it manually

```bash
./gradlew :validator:run --args='-c dotnet/ec2/service-events/incident-snapshot-validation.yml
  --region <region>
  --log-group /aws/service-events/<service-name>
  --service-name <service-name>
  --service-events-git-commit-sha <40-hex>
  --rollup'
```

The validator requires JDK 17.
