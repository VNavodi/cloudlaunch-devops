# ECR publishing — implemented, disabled, live unverified

CI builds and scans `cloudlaunch:ci`, then saves that exact image, image ID, tested SHA and archive checksum as a short-lived artifact only for main pushes. Publisher accepts successful main push runs from this repository, downloads the artifact from that exact run ID, validates metadata and revision label, and loads the image without executing it. It does not rebuild from a branch tip.

Archive checksums detect transfer mismatch; they are not independent provenance signatures. The trusted main CI workflow and protected branch remain the security boundary. Protect workflow changes with review. `workflow_run` is privileged: never admit PR/fork artifacts, restore untrusted caches or execute artifact scripts. Actions are pinned to resolved commits; Dependabot proposes updates.

## Administrator checklist (no bypass of SCP)

1. Confirm STS account 636621822646. Inspect existing OIDC provider and role before creating anything.
2. Organization administrator must resolve the previously reported SCP restriction through approved organization policy. Do not bypass it or add long-lived access keys.
3. Review [publisher trust](iam/publisher-trust.json) and [ECR permissions](iam/publisher-policy.json). Existing ECR repository only; no repository creation/deletion grants.
4. Configure GitHub environment `ecr-publish` with required reviewer and main-only deployment branch restriction. The environment-based OIDC subject does not itself restrict the branch. Keep the workflow main/push/repository checks too.
5. Provision/approve the short-lived publisher role and set repository variable `AWS_ECR_PUBLISH_ROLE_ARN`. These settings have NOT been inspected or changed remotely.
6. Review artifact storage costs/retention and IAM permissions. Only then set `ECR_PUBLISH_ENABLED=true` with explicit approval.
7. Run a fresh main CI build, approve the environment, record CI run, commit, artifact ID/digest, image config ID and ECR manifest digest from the summary. Successful configuration validation is not publication evidence.
8. Test rerun: an existing immutable tag is pulled and its config ID compared. A mismatch fails. Only `ImageNotFoundException` permits a push; permission/network errors fail. Failed/competing pushes fail safely; retry verifies the existing tag, never overwrites or deletes it.

Tags use full `sha-<40-character commit>`; deploy resolves ECR manifest digest. Image config ID and registry manifest digest are different identifiers. Artifact expiration requires a fresh CI run. Publishing never deploys EC2 automatically.

Reference: [GitHub workflow_run security warning](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run).
