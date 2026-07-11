#!/usr/bin/env bash
#
# lambda-logs.sh — tail the coach Lambda's CloudWatch logs.
#
# Usage:
#   bin/lambda-logs.sh                  # preview, last hour
#   bin/lambda-logs.sh prod
#   bin/lambda-logs.sh preview --tail   # follow (Ctrl-C to stop)
#   bin/lambda-logs.sh prod --since 24h

set -euo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

ENV_NAME="${1:-preview}"
case "$ENV_NAME" in
	preview|prod) ;;
	*) fatal "Unknown env: $ENV_NAME (expected preview or prod)" ;;
esac
shift || true

SINCE="1h"
FOLLOW=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		--tail|-f) FOLLOW=1; shift ;;
		--since)   SINCE="$2"; shift 2 ;;
		*)         fatal "Unknown flag: $1" ;;
	esac
done

need_cmd aws
need_aws_auth

LOG_GROUP="/aws/lambda/threkir-web-${ENV_NAME}-coach"

step "Tailing $LOG_GROUP (since $SINCE)"
if [[ $FOLLOW -eq 1 ]]; then
	exec aws logs tail "$LOG_GROUP" --since "$SINCE" --format short --follow
else
	aws logs tail "$LOG_GROUP" --since "$SINCE" --format short
fi
