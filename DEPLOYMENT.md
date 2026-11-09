# CloudLaunch deployment implementation

## What is implemented

- `scripts/deploy.sh IMAGE_TAG`: resolve immutable ECR digest, send a single SSM command to the designated EC2 instance, acquire remote `flock`, skip already-deployed image, log into ECR using the **EC2 instance IAM role**, pull the digest, test a loopback-only candidate on port 3001, and promote it on port 3000.
- `scripts/promote-container.sh IMAGE_DIGEST_URI`: verify production and image, preserve stopped previous container as `cloudlaunch-app-previous`, launch replacement, check `/health`, and attempt rollback on failure or handled termination.
- `scripts/rollback-container.sh`: explicitly gated manual rollback; preserves the failed deployment as `cloudlaunch-app-failed`.
- `Jenkinsfile`: parameterized manual CD for an **already-published ECR image**; default deployment is off.

## Requirements / setup

1. EC2 must be running and SSM Online; AWS CLI and Docker must be installed on EC2. EC2 instance role needs ECR read permissions, and SSM Agent needs its managed permissions. The production container must be healthy and listening only on `127.0.0.1:3000`.
2. The operator or Jenkins execution environment needs AWS CLI with short-lived, authorized credentials to call `ecr:DescribeImages`, `ssm:SendCommand`, `ssm:GetCommandInvocation`, and `sts:GetCallerIdentity` (Jenkins). **Do not copy a personal AWS CLI session or admin keys into the Jenkins image or Git.** Prefer an approved short-lived identity/credential broker for Jenkins. The repository does not provision that identity.
3. The Jenkins agent requires Bash, Python 3, AWS CLI and `base64`. Rebuild the custom Jenkins image to include Python 3. The Jenkins pipeline only deploys images already present in ECR. A separately gated GitHub publisher now reuses the CI-scanned image artifact; live publishing remains unverified.
4. Review `INSTANCE_ID`, AWS account and region in scripts before use. Both deploy and rollback are disruptive operations, not zero-downtime deployments.

## Safe commands

```bash
# Local no-change preview; invalid image is deliberately rejected:
./scripts/promote-container.sh invalid-image

# Validate tag and scripts locally; NO AWS calls or container changes:
./scripts/deploy.sh v1

# Only after approved AWS credentials, a new immutable image, and maintenance window:
AWS_PROFILE=cloudlaunch DEPLOY_ENABLED=true ./scripts/deploy.sh v2
```

Jenkins: **Build with Parameters**, specify an existing ECR `IMAGE_TAG`, and only select `DEPLOY_TO_EC2` when intentionally authorizing production changes. The default false setting performs no EC2 modification.

## Rollback / recovery

A successful promotion **retains** `cloudlaunch-app-previous` to support rollback. This intentionally blocks subsequent promotions until the operator explicitly reviews and resolves that backup; do not delete it automatically. The manual rollback script is meant to run **on EC2** only, with `ROLLBACK_ENABLED=true`; do not run it on the laptop with production defaults. Isolated local Docker testing is supported using explicit APP_NAME, PREVIOUS_NAME, FAILED_NAME, HEALTH_PORT, and LOCK_FILE overrides. It retains the replaced container as `cloudlaunch-app-failed`. If recovery fails, inspect container state and logs manually before further changes.

The automatic recovery trap is best-effort: it cannot protect against EC2 power loss, forced kill, or every Docker daemon failure. SSM command timeouts can leave the remote command still running; check the command ID and EC2 state before retrying. Do not start concurrent deployments. A failed promotion may cause temporary downtime.

## Not yet complete

- Jenkins short-lived AWS authentication provisioning and permission validation
- Administrator-approved activation and live verification of the implemented ECR publisher
- Live EC2 end-to-end promotion/rollback verification
- Activation/live verification of optional monitoring and notifications

## Jenkins rollback pipeline

Jenkins job: `CloudLaunch-Rollback-Pipeline`

- Pipeline definition: Pipeline script from SCM
- Repository: https://github.com/VNavodi/cloudlaunch-devops.git
- Branch: `*/main`
- Script path: `Jenkinsfile.rollback`
- Parameter: `ROLLBACK_TO_PREVIOUS` (default: false)

The default build is a dry-run. It validates rollback scripts without
sending AWS commands or modifying production.

Setting `ROLLBACK_TO_PREVIOUS=true` explicitly authorizes a real
rollback through AWS Systems Manager. This must only be done after
reviewing the current EC2 state and backup container.

## Historical verified local rollback tests

The following historical tests were reported before this audit using isolated Docker containers. See [current verification](docs/VERIFICATION.md) for fresh results:

| Test | Result |
|---|---|
| Successful rollback from v2 to v1 | Passed |
| Restored v1 health check | Passed |
| Unhealthy backup rollback failure | Passed |
| Automatic recovery of original healthy v2 | Passed |
| Failed rollback exit code equals 1 | Passed |
| Jenkins rollback dry-run on commit fd79ca4 | Passed |

Local tests used configurable container names, host ports and lock files.
The default production settings remain unchanged.

These results validate the tested local scenarios only. Real AWS EC2
rollback, unexpected Docker failures, and all recovery edge cases
have not been fully verified.

Do not run production rollback without explicit authorization.

## Terraform integration of existing AWS infrastructure

The `terraform/` configuration is currently a read-only inventory of the
existing CloudLaunch infrastructure. It uses data sources for the existing
VPC, subnet, security group, ECR repository, EC2 instance, IAM role, and IAM
instance profile. It does not declare resources for those objects, so it will
not provision a replacement EC2 instance, create another ECR repository, or
create duplicate IAM resources.

The separate `terraform-ecr/` directory still contains an
`aws_ecr_repository` resource. Its Terraform state is not present and its
ownership is not assumed. Do not run `terraform apply` or `terraform destroy`
there unless ownership, state, and the desired management boundary have first
been confirmed. This integration does not import resources into state.

The data-source approach verifies that the supplied IDs and names exist and
exposes read-only outputs. It does not manage drift, update tags or policies,
change EC2 power state, or guarantee that the existing IAM permissions,
security-group rules, and instance configuration meet the intended security
posture. The EC2 instance is expected to remain stopped during this work.

From `terraform/`, the safe checks are:

```bash
terraform fmt -check
terraform validate
# Only after explicit-profile STS identity verification:
AWS_PROFILE=cloudlaunch terraform plan -input=false
```

The plan only reads data sources when credentials and AWS connectivity are
available. Never run `terraform apply`, `terraform destroy`, or `terraform
import` for this read-only integration without a separately approved change.



## 🔐 DevSecOps Security

CloudLaunch integrates automated container vulnerability scanning into its GitHub Actions CI pipeline to help detect security risks before deployment.

### Security Controls Implemented

- **Multi-stage Docker build:** Separates dependency installation from the production runtime.
- **Reduced attack surface:** Removes unnecessary npm tooling from the production Docker image.
- **Non-root container:** Runs the Node.js application using the `node` user.
- **Automated vulnerability scanning:** Uses Trivy to scan Docker images for operating system and application dependency vulnerabilities.
- **Enforced security gate:** GitHub Actions fails the Docker image scanning step when Trivy detects HIGH or CRITICAL vulnerabilities.
- **Production runtime verification:** The hardened Docker image was tested locally to confirm the application still runs correctly.

### Vulnerability Remediation Results

| Security metric | Before | After |
|---|---|---|
| HIGH vulnerabilities | 4 | 0 |
| CRITICAL vulnerabilities | 0 | 0 |
| Docker runtime | npm tooling included | Unnecessary npm tooling removed |
| CI vulnerability scanning | Report-only | Enforced security gate |

**Verification:** GitHub Actions CI Pipeline #21 passed with the enforced Trivy security gate enabled.

### Security Tools

- Docker — Container image building and runtime isolation
- Trivy — Container vulnerability scanning
- GitHub Actions — Automated CI security checks

### Security Gate Configuration

The CI pipeline uses the following Trivy configuration:

```yaml
- name: Scan Docker image with Trivy
  uses: aquasecurity/trivy-action@v0.36.0
  with:
    image-ref: 'cloudlaunch:ci'
    format: 'table'
    severity: 'HIGH,CRITICAL'
    vuln-type: 'os,library'
    exit-code: '1'
```

The pipeline rejects images when the configured Trivy scan detects HIGH or CRITICAL vulnerabilities. A passing scan does not guarantee that the image is free of all security risks.

**Verified commits:**
- `4167a61` — Harden Docker runtime with multi-stage build
- `5c119a7` — Enforce Trivy vulnerability gate in CI

[View successful GitHub Actions workflow](https://github.com/VNavodi/cloudlaunch-devops/actions)

## Current safety and operational notes

See [audit](docs/AUDIT.md), [verification](docs/VERIFICATION.md), [infrastructure](docs/INFRASTRUCTURE.md), [publishing](docs/PUBLISHING.md) and [monitoring](docs/MONITORING.md).

Deploy, rollback and SSM health-check wrappers default to no AWS commands. Real commands require an explicit approved AWS_PROFILE, reject the personal account/root identity and check account before ECR/SSM. Jenkins uses a separately provisioned short-lived cloudlaunch profile; no profile was created or overwritten in this audit. Never inject root keys. The [Jenkins policy template](docs/iam/jenkins-policy.json) scopes SendCommand to the existing instance/document; this still grants powerful remote shell access and requires protected jobs, trusted SCM and authorized operators.

SSM explicitly starts Bash from a base64 payload; a shebang embedded in a shell command is not sufficient. Commands use a 600-second execution timeout and bounded health HTTP requests. Local polling failure does not cancel a remote operation: record the command ID, inspect SSM status with the correct account before retrying. Promotion and rollback share the same host lock, including direct promotion invocation. Catchable signals attempt recovery; SIGKILL/power loss do not.

Production is loopback-only on port 3000. Public access requires a separately reviewed TLS/reverse-proxy or load-balancer architecture, never an automatic 0.0.0.0/0 security-group rule. Candidate is loopback port 3001. Promotion stops production before replacement, so a maintenance window and temporary downtime are expected. Backups deliberately block later deployments; review and separately authorize cleanup rather than deleting evidence automatically. Manual rollback retains the replaced container; automatic promotion recovery retains a failed replacement under a unique diagnostic name before restoring the backup.

The Jenkins image includes Python 3, AWS CLI and util-linux. Its upstream Jenkins tag and AWS CLI download remain floating and installer signature verification is not implemented; pin and validate an approved release/signature before treating that image as a production-hardened agent. No live Jenkins job was run in this audit.
