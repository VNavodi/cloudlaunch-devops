#!/usr/bin/env bash
# Source only immediately before authorized AWS operations. Never print credentials.
cloudlaunch_identity() {
  : "${AWS_PROFILE:?Set AWS_PROFILE to an approved CloudLaunch short-lived credential profile}"
  local account arn
  account=$(aws --profile "$AWS_PROFILE" --region ap-southeast-2 sts get-caller-identity --query Account --output text) || return
  [[ "$account" == 636621822646 ]] || { echo 'ERROR: Wrong AWS account; refusing operation.' >&2; return 1; }
  arn=$(aws --profile "$AWS_PROFILE" --region ap-southeast-2 sts get-caller-identity --query Arn --output text) || return
  [[ "$arn" != *:root && "$arn" == arn:aws:* ]] || { echo 'ERROR: Root or invalid identity rejected.' >&2; return 1; }
}
