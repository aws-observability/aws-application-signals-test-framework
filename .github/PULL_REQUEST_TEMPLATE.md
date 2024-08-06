*Issue description:*

*Description of changes:*

*Rollback procedure:*

<Can we safely revert this commit if needed? If not, detail what must be done to safely revert and why it is needed.>

*Ensure you've run the following tests on your changes and include the link below:*

To do so, create a `test.yml` file with `name: Test` and workflow description to test your changes, then remove the file for your PR. Link your test run in your PR description. This process is a short term solution while we work on creating a staging environment for testing.

NOTE: TESTS RUNNING ON A SINGLE EKS CLUSTER CANNOT BE RUN IN PARALLEL. See the [needs](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idneeds) keyword to run tests in succession.
- Run Java EKS on `e2e-playground` in us-east-1 and eu-central-2
- Run Python EKS on `e2e-playground` in us-east-1 and eu-central-2
- Run metric limiter on EKS cluster `e2e-playground` in us-east-1 and eu-central-2
- Run EC2 tests in all regions
- Run K8s on a separate K8s cluster (check IAD test account for master node endpoints; these will change as we create and destroy clusters for OS patching)

By submitting this pull request, I confirm that my contribution is made under the terms of the Apache 2.0 license.
