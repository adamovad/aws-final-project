set -euo pipefail
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $REGISTRY
docker pull $IMAGE
DB_PASSWORD=$(aws ssm get-parameter --region $REGION --name $DB_PARAM \
  --with-decryption --query Parameter.Value --output text)
docker rm -f visits-service 2>/dev/null || true
docker run -d --name visits-service --restart unless-stopped -p 8080:8080 \
  -e DB_HOST=$DB_HOST -e DB_NAME=$DB_NAME -e DB_USER=$DB_USER \
  -e DB_PASSWORD="$DB_PASSWORD" -e PGSSLMODE=require \
  -e ALLOWED_ORIGIN=$ALLOWED_ORIGIN \
  $IMAGE
sleep 3
docker ps --filter name=visits-service --format '{{.Names}} {{.Image}} {{.Status}}'
echo "started_at: $(docker inspect -f '{{.State.StartedAt}}' visits-service)"
curl -sf localhost:8080/health
