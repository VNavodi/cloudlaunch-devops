# CloudLaunch deployment implementation

## What is implemented

- `scripts/deploy.sh IMAGE_TAG`: resolve immutable ECR digest, send a single SSM command to the designated EC2 instance, acquire remote `flock`, skip already-deployed image, log into ECR using the **EC2 instance IAM role**, pull the digest, test a loopback-only candidate on port 3001, and promote it on port 3000.
- `scripts/promote-container.sh IMAGE_DIGEST_URI`: verify production and image, preserve stopped previous container as `cloudlaunch-app-previous`, launch replacement, check `/health`, and attempt rollback on failure or handled termination.
- `scripts/rollback-container.sh`: explicitly gated manual rollback; preserves the failed deployment as `cloudlaunch-app-failed`.
- `Jenkinsfile`: parameterized manual CD for an **already-published ECR image**; default deployment is off.

## Requirements / setup

1. EC2 must be running and SSM Online; AWS CLI and Docker must be installed on EC2. EC2 instance role needs ECR read permissions, and SSM Agent needs its managed permissions. The production container must be healthy and listening only on `127.0.0.1:3000`.
2. The operator or Jenkins execution environment needs AWS CLI with short-lived, authorized credentials to call `ecr:DescribeImages`, `ssm:SendCommand`, `ssm:GetCommandInvocation`, and `sts:GetCallerIdentity` (Jenkins). **Do not copy a personal AWS CLI session or admin keys into the Jenkins image or Git.** Prefer an approved short-lived identity/credential broker for Jenkins. The repository does not provision that identity.
3. The Jenkins agent requires Bash, Python 3, AWS CLI and `base64`. Rebuild the custom Jenkins image to include Python 3. The Jenkins pipeline only deploys images that are already present in ECR; image build/push automation is **not** included.
4. Review `INSTANCE_ID`, AWS account and region in scripts before use. Both deploy and rollback are disruptive operations, not zero-downtime deployments.

## Safe commands

```bash
# Local no-change preview; no AWS credentials needed until the image is resolved:
./scripts/promote-container.sh invalid-image

# Resolve image in ECR, but make NO EC2 changes:
./scripts/deploy.sh v1

# Only after approved AWS credentials, a new immutable image, and maintenance window:
DEPLOY_ENABLED=true ./scripts/deploy.sh v2
```

Jenkins: **Build with Parameters**, specify an existing ECR `IMAGE_TAG`, and only select `DEPLOY_TO_EC2` when intentionally authorizing production changes. The default false setting performs no EC2 modification.

## Rollback / recovery

A successful promotion **retains** `cloudlaunch-app-previous` to support rollback. This intentionally blocks subsequent promotions until the operator explicitly reviews and resolves that backup; do not delete it automatically. The manual rollback script is meant to run **on EC2** only, with `ROLLBACK_ENABLED=true`; do not run it on the laptop. It retains the replaced container as `cloudlaunch-app-failed`. If recovery fails, inspect container state and logs manually before further changes.

The automatic recovery trap is best-effort: it cannot protect against EC2 power loss, forced kill, or every Docker daemon failure. SSM command timeouts can leave the remote command still running; check the command ID and EC2 state before retrying. Do not start concurrent deployments. A failed promotion may cause temporary downtime.

## Not yet complete

- Jenkins short-lived AWS authentication provisioning and permission validation
- Automated build/push of new immutable image tags to ECR
- Live EC2 end-to-end promotion/rollback verification
- Monitoring, notifications, and full DevSecOps security gates
