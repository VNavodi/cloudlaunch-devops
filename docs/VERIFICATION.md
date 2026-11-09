# Completion and verification report — 2026-11-09

## Outcome

Locally implemented improvements preserve the existing architecture. Cloud activation remains blocked/approval-dependent. No AWS resource mutation, Terraform apply/destroy/import, real Jenkins deployment/rollback, Git staging, commit or push was performed. Branch remains `test`; initial HEAD `c53f619`.

### Completed work

1. Audited existing source, historical achievements and clean initial Git status; [component table](AUDIT.md).
2. Retained seven existing Terraform data sources and both provider locks. Added account allowlists and legacy ECR lifecycle/ownership guards; documented remote state and import preparation without migration/import.
3. Kept Trivy HIGH/CRITICAL exit-code 1. Pinned Actions to resolved official commit hashes, added CI concurrency/timeouts, all-root Terraform validation, mock monitoring tests and expanded shell tests. Added Dependabot and digest-pinned the observed Node base.
4. Replaced ECR rebuild with exact scanned-image artifact transfer; added trusted-main checks, opt-in environment gate, account checks, immutable rerun comparison, evidence summary and narrow IAM templates. No cloud publication claimed.
5. Made default deploy/check previews credential-free; added explicit-profile account/root guards to wrappers and Jenkins, bounded HTTP probes and explicit Bash execution for SSM. Existing Jenkins runtime dependencies were reviewed.
6. Added direct promotion locking, rollback signal handling and retained failed promotion diagnostics. Expanded stateful mock coverage; no zero-downtime or guaranteed recovery claim.
7. Prepared default-off logs/alarms, a local health probe, optional agent/timer/log rotation, IAM template and cost/activation runbook. No live monitoring enabled.
8. Refreshed and pinned the official Node base to remediate three HIGH OS findings without suppressions. Fixed fresh npm findings: body-parser 2.3.0 → 2.4.0 (HIGH), qs 6.16.0 → 6.17.1 (MODERATE). Added graceful API shutdown.
9. Updated README and operational guides with architecture, status boundaries, portfolio bullets and simple Sinhala explanations.

## Exact checks and evidence

Commands are from repository root unless stated. PASS describes only the listed scope. Initial sandbox/network failures were retried with approved local access; they are not cloud failures.

| Command / check | Result | Evidence / scope |
|---|---|---|
| `git status --short`; `git branch --show-current` | PASS | Initial tree clean; branch test |
| `env -u PROMOTION_ENABLED -u ROLLBACK_ENABLED bash tests/test-promotion.sh` and equivalent existing mock/failure scripts | PASS | Baseline three existing suites before edits |
| `npm --prefix app test` before dependency installation | FAIL, resolved | Missing supertest; installed locked dependencies |
| `npm ci --prefix app --ignore-scripts` | PASS | 85 packages; initially reported 1 HIGH/1 MODERATE |
| `npm audit --prefix app --json` before fixes | FAIL, resolved | body-parser HIGH and qs MODERATE |
| `npm update --prefix app body-parser qs --ignore-scripts` | PASS | Compatible lockfile update; audit reports 0 vulnerabilities |
| `npm --prefix app test` after fixes/shutdown changes | PASS | 2 API integration tests; local socket access required |
| `bash scripts/validate-local.sh` | PASS | All Bash files parsed individually; isolated tests listed below |
| `bash tests/test-candidate-failure.sh` after SSM failure assertion | PASS | Actual generated remote script rejects candidate; failed SSM returns nonzero |
| `terraform -chdir=terraform fmt -check -recursive` | PASS | Main root and mock tests |
| `terraform -chdir=terraform-ecr fmt -check -recursive` | PASS | Legacy root |
| `terraform -chdir=terraform init -backend=false -input=false -lockfile=readonly` | PASS | Existing AWS 6.68.0 retained |
| `terraform -chdir=terraform-ecr init -backend=false -input=false -lockfile=readonly` | PASS | AWS 6.69.1 installed, signed by HashiCorp; lock unchanged |
| `terraform -chdir=terraform validate -no-color` | PASS | Provider schema validation, no AWS lookup |
| `terraform -chdir=terraform-ecr validate -no-color` | PASS | Configuration valid; ownership gate still false |
| `terraform -chdir=terraform test -no-color` | PASS | 2 mock-provider plans: disabled defaults and enabled design; no AWS calls |
| `docker build -t cloudlaunch:local-audit ./app` | PASS | Final refreshed base pinned to a34ab6d7f6f4813f4d0c5469d74685604b962fbdbf5793a7bc7b4998ecb867c8; image config f7f144e0c93e6f57e5a650d83f9ef80be378ad380196a8888596a762bebfcc69 |
| `bash tests/docker-smoke.sh cloudlaunch:local-audit` | PASS | Repeated on refreshed final base: generated container ID, isolated network, non-root health and graceful SIGTERM exit 0; now included in CI |
| `docker run -d --name cloudlaunch-audit-check --network none cloudlaunch:local-audit` | PASS | Dedicated local container; no host port published |
| `docker exec cloudlaunch-audit-check node -e 'if(process.getuid()===0)process.exit(1);fetch("http://127.0.0.1:3000/health").then(async r=>{if(!r.ok||(await r.json()).status!=="healthy")process.exit(1);console.log("PASS: non-root health endpoint")}).catch(()=>process.exit(1))'` | PASS | Non-root UID and healthy endpoint |
| `docker stop --time 10 cloudlaunch-audit-check`; `docker inspect cloudlaunch-audit-check --format '{{.State.ExitCode}}'`; `docker logs cloudlaunch-audit-check`; `docker rm cloudlaunch-audit-check` | PASS | SIGTERM logged, exit 0; only audit container removed |
| Initial fresh Trivy image scan (HIGH/CRITICAL, exit-code 1) | FAIL, resolved by refreshed base | 3 HIGH / 0 CRITICAL: musl and musl-utils CVE-2026-107891 (1.2.6-r2 → 1.2.6-r3), zlib CVE-2026-85091 (1.3.2-r0 → 1.3.2-r1). Node packages: 0. Gate preserved. |
| `docker run --rm -v "$PWD:/repo:ro" -w /repo rhysd/actionlint@sha256:b1934ee5f1c509618f2508e6eb47ee0d3520686341fec936f3b79331f9315667 -color` | PASS | Both workflows valid; shell quoting diagnostic fixed before passing |
| `git diff --check` | PASS | No whitespace errors |
| Editor diagnostics | PASS | No reported errors |
| Tracked secret-file name review | PASS | No tracked .env/credentials/private-key/state/plan filenames found; not a forensic secret audit |
| `aws configure list-profiles` | PASS | Only default profile available outside sandbox; no profile overwritten |
| `aws --profile default --region ap-southeast-2 sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json` | FAIL / BLOCKED | Session expired; effective account could not be verified; no subsequent AWS resource calls |
| Read-only AWS inventory / Terraform plan | NOT RUN | Correct account authentication unavailable |
| GitHub-hosted updated workflows | NOT RUN | Changes not committed/pushed; no remote CI result claimed |
| Jenkins engine build/dry-run, Jenkins image rebuild | NOT RUN | Shell previews tested locally; no live Jenkins job invoked |
| ECR publication, EC2 deployment/cloud rollback | NOT RUN | Requires identity, permissions and explicit approval |
| CloudWatch delivery, alarm transitions, SNS | NOT RUN | No activation approval; no live access |
| CloudWatch Agent binary schema validation | NOT RUN | Agent not installed; JSON and health-event semantics tested locally |

### Isolated recovery/safety coverage

- Default deploy/rollback/check wrappers make zero AWS calls.
- Invalid tags, wrong account (including personal account), and root identity rejected.
- Existing promotion success/failure/recovery tests retained.
- Generated SSM payload syntax, candidate failure cleanup, no production stop/rename on candidate failure, and failed SSM status propagation.
- Stateful rollback success; unhealthy backup; backup start failure; SIGTERM; missing backup; shared-lock contention; repeated rollback.
- Stateful promotion success and repeated-request refusal while backup exists; replacement start failure; unhealthy replacement; signal recovery; failed image diagnostic retention.
- Monitoring writes healthy=1 and healthy=0 events; agent JSON is logs-only; Terraform mocks verify default-off and bounded retention/target/alarm settings.

Mocks do not prove real Docker daemon failure recovery, SSM shell behavior, IAM policy validity, cloud availability or power-loss resilience. Fresh Docker test covers application startup/health/shutdown, not real host promotion/rollback. Historical real local Docker rollback results remain documented separately in DEPLOYMENT.md.

## AWS / external actions requiring explicit approval

| Proposed action | Prerequisite and approval boundary |
|---|---|
| Authenticate approved CloudLaunch profile | User completes short-lived authentication for 636621822646; never substitute personal account/root keys |
| Read-only inventory and safe plan | Verify account first; stop on unexpected resource changes |
| OIDC provider/publisher role setup | Organization admin resolves SCP through approved policy; review existing provider/role, trust and narrow ECR policy |
| Enable ECR publishing | Approve GitHub environment/reviewers/main restriction, role variable and opt-in flag; then capture fresh CI/ECR evidence |
| Jenkins identity setup | Approved short-lived credential source; narrow SSM/ECR policy; protect job and SCM |
| Terraform ownership/import | Identify authoritative state, approve exact resource addresses/IDs, back up securely; no import done |
| S3 backend/KMS/migration | Approve costs, bucket/key/IAM design and migration/recovery plan; none created |
| EC2 startup/configuration changes | Separate approval; verify IMDSv2, IAM, SG, SSM and runtime first; no public 3000 rule |
| Live deployment or rollback | Explicit operator authorization, existing immutable image, maintenance window, backup review and recovery access |
| Monitoring apply/agent/timer/log driver/SNS activation | Inventory existing configuration, cost approval, reviewed plan, narrow IAM; no duplicates |
| Backup/container cleanup | Inspect and obtain separate authorization; preserve evidence |
| Git commit/push | User reviews the specific changed files; nothing staged/committed/pushed |

## Remaining limitations and portfolio readiness

Ready for code review and a portfolio demonstration of local CI/CD safety engineering. Not certified production-ready or cloud-complete. Blockers: expired AWS session; previously reported Organizations SCP restriction (not freshly queried); unverified OIDC/role/variable configuration; unprovisioned Jenkins short-lived identity; no live deployment/rollback/monitoring evidence. Jenkins upstream tag and AWS CLI installer remain floating/unverified by signature; harden before operational use. Default alarms lack notification actions; application stdout shipping is an approval runbook, not enabled code behavior.

Full architecture, project summary, supported CV bullets and Sinhala interview explanation are in [README](../README.md). The accurate end-to-end path is tests/build → enforced scan → exact artifact → gated OIDC publication (unverified) → manual Jenkins/SSM (unverified) → locked candidate/promotion → retained backup/recovery; optional CloudWatch remains disabled.

## Specific files to review before any commit

See [CHANGES.md](CHANGES.md). Generated local logs and image archive are ignored and are not deliverables. No `git add .` was used.

## Final security scan evidence

Final Trivy scan on 2026-11-09: **PASS, 0 HIGH and 0 CRITICAL**, exit code 0, OS and Node packages scanned. Scanner image digest: `sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb`; database freshly downloaded that day. This is a local image result, not a new GitHub CI or ECR deployment result.

```bash
docker save cloudlaunch:local-audit -o verification-image.tar
docker run --rm -v cloudlaunch-trivy-cache:/root/.cache/trivy \
  -v "$PWD/verification-image.tar:/image.tar:ro" \
  aquasec/trivy@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb \
  image --input /image.tar --scanners vuln --severity HIGH,CRITICAL --exit-code 1 --quiet
```

The temporary image archive was removed after scanning; the named local Trivy database cache remains for reuse. Security fixes were verified without `.trivyignore`, severity exclusions or lowering the exit-code gate.
