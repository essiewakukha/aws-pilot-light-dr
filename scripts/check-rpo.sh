#!/usr/bin/env bash
# Reports cross-Region replica lag over the last 24 h against the 15-minute RPO.
set -euo pipefail
: "${DR_REGION:?}" "${DR_REPLICA_ID:?}"
RPO="${RPO_SECONDS:-900}"

read -r MAX AVG < <(aws cloudwatch get-metric-statistics --region "$DR_REGION" \
  --namespace AWS/RDS --metric-name ReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value="$DR_REPLICA_ID" \
  --start-time "$(date -u -d '-24 hours' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 86400 --statistics Maximum Average \
  --query 'Datapoints[0].[Maximum,Average]' --output text)

printf 'Replica lag (24h): max=%ss avg=%ss  RPO target=%ss\n' "$MAX" "$AVG" "$RPO"
if [[ "$MAX" == "None" ]]; then
  echo "WARN: no ReplicaLag data. Is replication running?"; exit 2
elif (( $(printf '%.0f' "$MAX") > RPO )); then
  echo "FAIL: RPO breached in the last 24h"; exit 1
else
  echo "PASS: RPO met"
fi