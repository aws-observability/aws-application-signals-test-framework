# Java EC2 profiler e2e: local run

Runs the same checks as `.github/workflows/java-ec2-profiler-test.yml` from your machine, without
EC2 or Terraform. The four profiled sample-app variants (main, cpu, unsampled, none) and the OTel
Collector run in one Docker container, export real profiles to CloudWatch Profiles, and the
validator checks them.

```
terraform/java/ec2/profiler/local-run/run-local.sh \
  --profile <aws-profile> \
  --java-repo ~/path/to/aws-otel-java-instrumentation   # or: --agent-jar <agent jar>
```

- `--profile`: an AWS CLI profile in an account enabled for CloudWatch Profiles (or add
  `--profiles-role-arn` for a role in one). No AWS resources are created; only profile data under a
  unique service name (`java-sample-application-local-…`).
- `--java-repo` builds the agent from that checkout (`:otelagent:assemble`); `--agent-jar` uses a
  jar you already have.
- `--checks wall-profile,identity` runs only some checks; `--keep` leaves the container running.

Needs Docker (or Finch: set `DOCKER=finch`), the AWS CLI, Python 3 and JDK 17. A full run takes
about 25 minutes; each enforced check retries for up to ~10 minutes while CloudWatch ingests the
profiles. It prints PASS/FAIL per check and exits non-zero if any failed. Report-only checks (the
workflow's NOT ENFORCED steps) retry for about a minute, always pass, and show what they measured,
e.g. `[NOT ENFORCED: would FAIL; see the reason in its log]`. Logs are under the work directory it
prints.

Differences from the EC2 run (see `container-setup.sh`): the apps get fake AWS credentials so
`/aws-sdk-call` makes a real S3 round trip, and `host.id` is `local` because a container has no
instance metadata.

If `docker run` fails with "authorization token has expired" for `public.ecr.aws`, run
`docker logout public.ecr.aws` (the image is public).
