# Infrastructure boundaries and approval plan

## Existing infrastructure

Account **636621822646**, region **ap-southeast-2** only. Personal account **599915810877** is never a fallback. Main Terraform root retains data sources for VPC, subnet, SG, EC2, role, instance profile and ECR. Default monitoring is disabled. Provider `allowed_account_ids` is an additional guard, not a substitute for an explicit profile and STS check.

The initial default profile STS attempt on 2026-11-09 reported an expired login. No account identity, current instance power state, OIDC provider, IAM role/policy, network rule, ECR setting or live monitoring configuration was verified in this session. The last known instance state is stopped.

## Terraform ownership

- `terraform/`: data-source integration, not lifecycle management of existing resources. Optional monitoring definitions create NEW resources only after approval.
- `terraform-ecr/`: legacy resource root retained, not consolidated or applied. `ownership_review_approved=false` prevents a normal plan from proceeding and `prevent_destroy` guards deletion/replacement. Do not flip this flag to make checks green. Neither flag is an authorization mechanism for an operator who edits configuration.
- Lock files pin AWS 6.68.0 and 6.69.1 respectively; both satisfy `~> 6.0`. Preserve independent locks until consolidation is reviewed. CI uses `-lockfile=readonly`; no automatic provider upgrades.
- No state contents were displayed, no import occurred, and ownership is unknown. Do not infer ownership from a source file, `.terraform/` directory or successful validation.

Future import preparation: locate the authoritative state securely; inventory IDs and current settings with the correct identity; decide one root per resource; back up state securely; match configuration including ECR immutability/encryption/scanning; request approval for exact import addresses/IDs; import only then; review a no-change plan. Stop on unexpected create/update/delete/replacement. Do not apply to recreate existing resources.

## Read-only verification after authentication

Use a separately configured approved short-lived `cloudlaunch` profile; do not overwrite `default`. First source `scripts/aws-identity.sh` and call `cloudlaunch_identity` with `AWS_PROFILE=cloudlaunch`. Then inspect EC2/SSM/ECR/IAM/CloudWatch using that profile and region. Check IMDSv2 `HttpTokens=required`, security-group ingress, SSM Online state, instance role attachments and ECR `IMMUTABLE`. No SSH/public port 3000 rule is needed. Check existing alarms/log groups before approving monitoring creation.

Only after identity is verified: `AWS_PROFILE=cloudlaunch terraform -chdir=terraform plan -input=false`. Do not save a plan to Git; plan/state may contain sensitive values. Default plan should read existing data and create **zero resources**. Outputs may change. Stop on resource changes; do not apply.

## Proposed remote state (not installed)

Use a dedicated private S3 bucket in this account/region, versioning, Block Public Access, TLS-only bucket policy, encryption at rest, and narrow role access per state prefix. Choose SSE-S3 for low operational cost or customer-managed KMS after reviewing key policy and key/request costs. Enable native S3 locking with `use_lockfile=true`; standardize Terraform >=1.10 for this future backend. CI currently pins 1.16.5. No backend block or migration is active.

Permissions: scoped bucket `ListBucket`; `GetObject`/`PutObject` for state; `GetObject`/`PutObject`/`DeleteObject` for the `.tflock` object. State deletion is not a routine permission. KMS requires explicitly scoped encryption/decryption/data-key permissions if selected. Separate read-only plan and approved apply roles, log access, prohibit public access and Git storage.

Recovery: stop concurrent runs, identify a known-good S3 object version, preserve the latest version, obtain recovery approval, restore the selected version, run a read-only plan and reconcile drift. Never force-unlock until the lock owner is confirmed inactive. Retain noncurrent versions with a reviewed lifecycle policy. Costs include S3 storage/versions, requests, optional KMS and audit delivery; no bucket/paid feature was created.

Reference: [HashiCorp S3 backend and lock permissions](https://developer.hashicorp.com/terraform/language/backend/s3).
