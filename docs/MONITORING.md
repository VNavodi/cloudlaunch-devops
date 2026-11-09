# CloudWatch — approval-ready configuration, live unverified

සරලව: EC2 CPU/status metrics වලින් server තත්ත්වය බලනවා. `/health` probe එකෙන් API එක පිළිතුරු දෙනවාද බලනවා. Logs diagnosis සඳහා තබනවා. මේවා AWS තුළ තවම activate කරලා නැහැ.

Existing AWS monitoring could not be inspected because the available profile is expired. Before any activation, verify the correct account and inventory current log groups, alarms, agents and policies. Never create duplicates.

## Prepared implementation

- Default `enable_monitoring=false`: no CloudWatch resource creation in the normal Terraform root.
- 14-day `/cloudlaunch/application` log group, deletion protection.
- EC2 `StatusCheckFailed >=1` for two five-minute periods; CPU average >80% for three five-minute periods. Uses existing basic metrics, no detailed monitoring enabled.
- `scripts/health-log.sh` writes JSON health events locally; `monitoring/cloudlaunch-health.timer` runs every five minutes when explicitly installed/enabled. Logs-only CloudWatch Agent configuration collects these events; metric filter extracts numeric `Healthy`, alarm triggers below 1 for two five-minute periods.
- Missing data remains INSUFFICIENT_DATA, appropriate for an intentionally stopped instance. This is NOT a missing-heartbeat outage alarm. Review a maintenance-aware heartbeat alarm if continuous uptime is later required.
- No SNS topic is created. Optional existing, approved same-account topic ARNs enable alarm notifications. Empty list means alarms have no notifications.

## Activation plan — approval required

Review estimated usage/cost and a targeted Terraform plan first. After approval, create the three alarms, metric filter and log group only if absent. Approve the narrow [EC2 logs policy](../monitoring/ec2-logs-policy.json) for the existing role; no broad CloudWatchFullAccess.

With separate EC2 startup/SSM authorization: install the official CloudWatch Agent, install the health script at `/opt/cloudlaunch/health-log.sh` mode 0755, create `/var/log/cloudlaunch` mode 0750, install the provided service/timer and logrotate configuration, validate the agent JSON using the installed agent, and enable only after review. No host install commands were executed here. Agent runs as root to read the root-owned probe log; no custom memory/disk metrics are enabled.

Application stdout/stderr can use Docker's `awslogs` driver on an explicitly approved future container recreation: region `ap-southeast-2`, group `/cloudlaunch/application`, stream `<instance-id>/application`, `awslogs-create-group=false`. Configure bounded non-blocking buffering after choosing an acceptable log-loss policy. The current deploy script intentionally does not enable this driver automatically; existing containers and backup logging configuration remain intact. Docker uses the EC2 role; no keys inside containers. Do not log credentials or request bodies.

Verify agent delivery, log retention, real healthy/unhealthy events, alarm state transitions and SNS delivery. Save evidence. A mocked metric-filter plan is not live monitoring evidence. If rollout fails, stop the new timer/agent only with approval, preserve logs, inspect IAM/network connectivity, and avoid deleting the log group.

## Cost review before activation

Budget for three standard-resolution alarms, one custom health metric, log ingestion/storage, API requests, and optional SNS. Docker application log volume is workload-dependent; cap retention and local log rotation. Agent downloads/traffic, NAT or private endpoints can add costs depending on the existing subnet. Do not add endpoints, dashboards, detailed monitoring, Container Insights, tracing or paid anomaly detection by default. Confirm current Sydney rates and free-tier eligibility; no free-tier assumption or fixed monthly promise is made.

References: [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/), [Docker awslogs options](https://docs.docker.com/engine/logging/drivers/awslogs/).

Baseline sizing: a five-minute probe emits about 288 events/day, or 8,640 events per 30-day month. At roughly 100 bytes/event that is under 1 MB of raw health events/month before service overhead. Application stdout can dominate ingestion, so estimate it separately. Monthly estimate = three alarm charges + one custom metric + log ingestion + retained storage + optional SNS/network/KMS charges at approved Sydney rates. The log-group `prevent_destroy` guard intentionally blocks deleting the group by simply toggling the variable off after provisioning; retention or decommissioning requires a separate review.
