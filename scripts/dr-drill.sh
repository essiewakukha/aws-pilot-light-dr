#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# NON-DESTRUCTIVE DR drill. Run it monthly.
#
# Proves the DR Region can boot and serve the app WITHOUT promoting the
# replica (it stays read-only, so /health works but writes would fail).
#   1. Check replica lag is inside the RPO
#   2. Scale the DR ASG 0 -> 1
#   3. Time how long until the DR ALB returns 200 on /health
#   4. Scale back to 0 (pilot light again)
# ---------------------------------------------------------------------------
set -euo pipefail

: "${DR_REGION:?}" "${DR_REPLICA_ID:?}" "${DR_ASG_NAME:?}" "${DR_ALB_DNS:?}"
log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

cleanup() {
  log "Scaling DR ASG back to 0 (pilot light)"
  aws autoscaling update-auto-scaling-group --region "$DR_REGION" \
    --auto-scaling-group-name "$DR_ASG_NAME" --min-size 0 --desired-capacity 0
}
trap cleanup EXIT

"$(dirname "$0")/check-rpo.sh"

START=$(date +%s)
log "Scaling DR ASG to 1 instance"
aws autoscaling update-auto-scaling-group --region "$DR_REGION" \
  --auto-scaling-group-name "$DR_ASG_NAME" --min-size 1 --desired-capacity 1

log "Polling http://${DR_ALB_DNS}/health"
until curl -sf -o /dev/null "http://${DR_ALB_DNS}/health"; do
  sleep 15
  (( $(date +%s) - START > 1800 )) && { log "FAIL: not healthy after 30 min"; exit 1; }
done

ELAPSED=$(( $(date +%s) - START ))
log "PASS: DR Region served healthy traffic in $((ELAPSED / 60))m $((ELAPSED % 60))s"
curl -s "http://${DR_ALB_DNS}/health"; echo
echo "Add DB promotion time (typically 5-15 min) to estimate full RTO."