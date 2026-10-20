# CloudLaunch — Automated DevOps CI/CD Pipeline

CloudLaunch is a hands-on DevOps project demonstrating a containerized Node.js application, automated CI validation, infrastructure-as-code checks, container security scanning, and controlled deployment and rollback workflows.

## Technology stack

- **Application:** Node.js, Express
- **Containerization:** Docker (multi-stage production build)
- **Continuous integration:** GitHub Actions
- **Continuous delivery:** Jenkins (manually authorized workflows)
- **Infrastructure:** AWS EC2, ECR, Systems Manager (SSM), Terraform
- **Security:** Trivy vulnerability scanning

## CI pipeline

GitHub Actions validates the application, builds a production Docker image, runs Trivy container scanning, validates Terraform infrastructure, and runs deployment safety/recovery tests.

The Trivy security gate is configured to return a failing exit code when the scan detects **HIGH** or **CRITICAL** vulnerabilities.

## 🔐 DevSecOps Security

CloudLaunch integrates automated container vulnerability scanning into its GitHub Actions CI pipeline to help detect security risks before deployment.

### Security controls implemented

- **Multi-stage Docker build:** Installs dependencies in a build stage separately from the production runtime.
- **Reduced attack surface:** Removes unnecessary npm tooling from the production Docker image.
- **Non-root container:** Runs the Node.js application using the `node` user.
- **Automated vulnerability scanning:** Uses Trivy to inspect operating-system packages and Node.js dependencies in the Docker image.
- **Enforced security gate:** The Trivy step returns a failing status for detected HIGH or CRITICAL vulnerabilities.
- **Runtime verification:** The hardened Docker image was successfully launched and checked locally.

### Vulnerability remediation results

| Security metric | Before | After |
|---|---:|---:|
| HIGH vulnerability findings | 4 | 0 |
| CRITICAL vulnerability findings | 0 | 0 |
| Production image npm tooling | Included | Removed |
| Trivy CI behavior | Report only | Fails on HIGH/CRITICAL findings |

**Verification:** GitHub Actions CloudLaunch CI Pipeline **#21** passed on commit `5c119a7` with the enforced vulnerability gate enabled.

### Trivy GitHub Actions configuration

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

A passing scan indicates no detected findings at the selected severities at scan time; it does **not** guarantee the absence of all security risks.

**Relevant commits:**
- `4167a61` — Harden Docker runtime with a multi-stage build
- `5c119a7` — Enforce Trivy vulnerability gate in CI

[View GitHub Actions runs](https://github.com/VNavodi/cloudlaunch-devops/actions)

## Deployment and rollback

The repository includes gated Jenkins deployment and rollback workflows, immutable ECR image digest resolution, SSM-driven remote deployment, candidate health checks, and local rollback/recovery tests.

**Production deployment is not automatic.** Jenkins defaults to no deployment, and real deployment or rollback requires explicit authorization. Local rollback scenarios have been tested; live AWS EC2 promotion/rollback remains to be verified.

For prerequisites, operational safety, commands, and test details, read [DEPLOYMENT.md](DEPLOYMENT.md).

## Current limitations

- Jenkins short-lived AWS authentication is not yet provisioned and validated.
- Automated build and publication of immutable images to ECR is not complete.
- Live EC2 promotion and rollback have not been verified end to end.
- Monitoring, notifications, and broader DevSecOps controls are still pending.

The Trivy HIGH/CRITICAL vulnerability gate is implemented; broader security work remains in progress.
