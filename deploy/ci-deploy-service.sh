#!/usr/bin/env bash
# Usage: deploy/ci-deploy-service.sh visits|stats
# Runs on the GitHub Actions runner: build -> push to ECR -> deploy via SSM Run Command.
set -euo pipefail

SVC="$1"
case "$SVC" in
  visits) INSTANCE_ID="$VISITS_INSTANCE_ID" ;;
  stats)  INSTANCE_ID="$STATS_INSTANCE_ID" ;;
  *) echo "unknown service: $SVC"; exit 1 ;;
esac
REPO="$ECR_REGISTRY/final-project-$SVC-service"
TAG="${GITHUB_SHA:-manual}"

echo "==> [1/3] Build & push $REPO:$TAG"
aws ecr get-login-password --region "$AWS_REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"
docker build -t "$REPO:$TAG" -t "$REPO:latest" "workloads/$SVC-service"
docker push "$REPO:$TAG"
docker push "$REPO:latest"

echo "==> [2/3] Build the remote script (config + logic, no secrets)"
REMOTE=$(mktemp)
cat > "$REMOTE" <<CFG
REGION=$AWS_REGION
REGISTRY=$ECR_REGISTRY
IMAGE=$REPO:$TAG
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PARAM=$DB_PARAM
VISITS_SERVICE_URL=http://$VISITS_PRIVATE_IP:8080
ALLOWED_ORIGIN=$ALLOWED_ORIGIN
CFG
cat "deploy/remote-$SVC.sh" >> "$REMOTE"

echo "==> [3/3] Deploy via SSM to $INSTANCE_ID"
CMD_ID=$(aws ssm send-command --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript \
  --comment "deploy $SVC ${TAG:0:12}" \
  --parameters "$(jq -n --rawfile s "$REMOTE" '{commands: [$s]}')" \
  --query 'Command.CommandId' --output text)
echo "CommandId: $CMD_ID"

sleep 3
aws ssm wait command-executed --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" || true
STATUS=$(aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query Status --output text)
echo "--- remote stdout ---"
aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
  --query StandardOutputContent --output text
echo "--- status: $STATUS ---"
if [ "$STATUS" != "Success" ]; then
  aws ssm get-command-invocation --command-id "$CMD_ID" --instance-id "$INSTANCE_ID" \
    --query StandardErrorContent --output text
  exit 1
fi
