#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pilot Light failover: "turn up the gas"
#
#   1. Record replica lag (your real RPO at the moment of failover)
#   2. Promote the cross-Region read replica to a standalone writable DB
#   3. Scale the DR Auto Scaling group from 0 to production size
#   4. Wait until targets are healthy behind the DR ALB
#   5. Print the measured RTO
#
# Route 53 failover routing moves traffic to the DR ALB automatically once
# the primary health check fails. Nothing to change in DNS.
#
# Usage:  eval "$(terraform -chdir=terraform output -raw script_env)"
#         ./scripts/failover.sh            # asks for confirmation
#         ./scripts/failover.sh --yes      # non-interactive
# ---------------------------------------------------------------------------
set -euo pipefail

: "${DR_REGION:?}" "${DR_REPLICA_ID:?}" "${DR_ASG_NAME:?}" "${DR_TG_ARN:?}"
DR_DESIRED="${DR_DESIRED:-2}"

log() { printf '[%s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }

if [[ "${1:-}" != "--yes" ]]; then
  echo "This PROMOTES ${DR_REPLICA_ID} in ${DR_REGION}. Replication from the"
  echo "primary stops for good, and failing back means rebuilding a replica."
  read -r -p "Type FAILOVER to continue: " answer
  [[ "$answer" == "FAILOVER" ]] || { echo "Aborted."; exit 1; }
fi

START=$(date +%s)

log "Step 1/4: measuring replica lag (data loss window = RPO)"
LAG=$(aws cloudwatch get-metric-statistics --region "$DR_REGION" \
  --namespace AWS/RDS --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value="$DR_REPLICA_ID" \
  --start-time "$(date -u -d '-10 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 60 --statistics Maximum \
  --query 'sort_by(Datapoints,&Timestamp)[-1].Maximum' --output text || echo "unknown")
log "  last reported ReplicaLag: ${LAG}s (target RPO: 900s)"

log "Step 2/4: promoting read replica (this enables automated backups)"
aws rds promote-read-replica --region "$DR_REGION" \
  --db-instance-identifier "$DR_REPLICA_ID" \
  --backup-retention-period 7 >/dev/null

# Scale compute WHILE the DB promotes. These run in parallel to cut RTO.
log "Step 3/4: scaling DR ASG ${DR_ASG_NAME} to ${DR_DESIRED} instances"
aws autoscaling update-auto-scaling-group --region "$DR_REGION" \
  --auto-scaling-group-name "$DR_ASG_NAME" \
  --min-size "$DR_DESIRED" --desired-capacity "$DR_DESIRED"

sleep 30 # promotion takes a moment to show up as 'modifying'
aws rds wait db-instance-available --region "$DR_REGION" --db-instance-identifier "$DR_REPLICA_ID"
log "  database promoted and available"

log "Step 4/4: waiting for healthy targets behind the DR ALB"
for _ in $(seq 1 60); do
  HEALTHY=$(aws elbv2 describe-target-health --region "$DR_REGION" \
    --target-group-arn "$DR_TG_ARN" \
    --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" --output text)
  log "  healthy targets: ${HEALTHY}/${DR_DESIRED}"
  [[ "$HEALTHY" -ge "$DR_DESIRED" ]] && break
  sleep 20
done

END=$(date +%s)
RTO_MIN=$(( (END - START) / 60 ))
log "Failover complete. Measured RTO: ${RTO_MIN} min (target: 180 min)"
echo
echo "Next steps:"
echo "  - Set dr_active = true in terraform.tfvars and run 'terraform apply'"
echo "  - Optional: enable Multi-AZ on the promoted DB:"
echo "      aws rds modify-db-instance --region $DR_REGION --db-instance-identifier $DR_REPLICA_ID --multi-az --apply-immediately"
echo "  - Follow docs/runbook-failback.md once the primary Region recovers"