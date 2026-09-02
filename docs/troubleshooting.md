# Troubleshooting

Everything in this file actually happened while building this project. It is
kept because the fix is rarely obvious from the error message.

## Builds and Jenkins


| Symptom | Cause |
|---|---|
| Kaniko: `denied: User is not authorized to perform ecr:PutImage` | The pod is not using `jenkins-sa`, or the IRSA annotation is missing. Check `kubectl -n jenkins get sa jenkins-sa -o yaml`. |
| Kaniko: `no basic auth credentials` | The `kaniko-docker-config` ConfigMap is not mounted, so Kaniko does not know to use the ECR credential helper. |
| Git stage: `Authentication failed` | The PAT is wrong, expired, or missing the `repo` scope. |
| Git stage: `nothing to commit` | Not a failure. The tag is already what the build produced. The pipeline skips the commit on purpose. |
| Agent pod stuck `Pending` | The two nodes are full. Either raise `desired_size` or lower the Jenkins resource requests. |
| `jenkins-0` stuck in `Init:Error`, init log says `Multiple plugin prerequisites not met` | The Jenkins core shipped by the pinned chart is older than the plugins the init container downloads. Bump `jenkins_chart_version`. This happened on the first run with chart 5.8.27, core 2.492.2, against plugins that wanted 2.504.3. |
| `helm_release.jenkins` fails with `context deadline exceeded` | The controller never became ready inside the timeout. The real reason is in the init container: `kubectl -n jenkins logs jenkins-0 -c init`. |
| Node group fails with `InvalidParameterCombination ... not eligible for Free Tier` | The account is on the AWS Free Plan. See the note on the instance type further down. |
| seed-job fails with `script not yet approved for use` | Job DSL script security is on. The JCasC block `job-dsl-security` in `modules/jenkins/values.yaml` turns it off. |
| Pipeline fails to compile with `Invalid option type "timestamps"` | The `timestamper` plugin is missing from `installPlugins`. Every option used in the Jenkinsfile needs its plugin listed there. |
