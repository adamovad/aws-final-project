set -euo pipefail
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
docker pull $IMAGE
docker rm -f stats-service 2>/dev/null || true
docker run -d --name stats-service --restart unless-stopped -p 8081:8081 \
  -e VISITS_SERVICE_URL=$VISITS_SERVICE_URL \
  -e ALLOWED_ORIGIN=$ALLOWED_ORIGIN \
  $IMAGE
sleep 3
docker ps --filter name=stats-service --format '{{.Names}} {{.Image}} {{.Status}}'
echo "started_at: $(docker inspect -f '{{.State.StartedAt}}' stats-service)"
curl -sf localhost:8081/health
