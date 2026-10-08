#!/usr/bin/env bash
set -e

# ==============================================================================
# Zero-Downtime Blue/Green Deployment Script for AWS EC2 (t3.micro friendly)
# Application: commands-app (Ops Notebook)
# ==============================================================================

IMAGE_URI="$1"

if [ -z "$IMAGE_URI" ]; then
    echo "❌ Error: Docker Image URI is required as first argument."
    echo "Usage: ./deploy.sh <IMAGE_URI>"
    exit 1
fi

echo "=============================================="
echo "🚀 Starting Blue/Green Deployment"
echo "Target Image: $IMAGE_URI"
echo "Time: $(date)"
echo "=============================================="

# 1. Determine which color is currently active
if docker ps --format '{{.Names}}' | grep -q "^commands-app-blue$"; then
    CURRENT_COLOR="blue"
    CURRENT_PORT=8081
    TARGET_COLOR="green"
    TARGET_PORT=8082
elif docker ps --format '{{.Names}}' | grep -q "^commands-app-green$"; then
    CURRENT_COLOR="green"
    CURRENT_PORT=8082
    TARGET_COLOR="blue"
    TARGET_PORT=8081
else
    # Fresh deployment / First time run
    CURRENT_COLOR="none"
    CURRENT_PORT=0
    TARGET_COLOR="blue"
    TARGET_PORT=8081
fi

echo "📍 Current Active Slot : ${CURRENT_COLOR} (Port: ${CURRENT_PORT})"
echo "🎯 Deploying Target Slot: ${TARGET_COLOR} (Port: ${TARGET_PORT})"

# 2. Pull the latest Docker image from ECR
echo "📦 Pulling new image from ECR..."
docker pull "$IMAGE_URI"

# 3. Clean up any existing container with the target name
echo "🧹 Cleaning up old target container if present..."
docker rm -f "commands-app-${TARGET_COLOR}" 2>/dev/null || true

# 4. Start the new container on target port
echo "▶️  Starting commands-app-${TARGET_COLOR} on 127.0.0.1:${TARGET_PORT}..."
docker run -d \
    --name "commands-app-${TARGET_COLOR}" \
    -p 127.0.0.1:${TARGET_PORT}:80 \
    --restart unless-stopped \
    "$IMAGE_URI"

# 5. Health Check: verify the new container is responding
echo "🩺 Running health checks on port ${TARGET_PORT}..."
HEALTHY=false
for i in {1..10}; do
    echo "   Attempt $i/10: checking http://127.0.0.1:${TARGET_PORT}/health ..."
    if curl -sf "http://127.0.0.1:${TARGET_PORT}/health" >/dev/null 2>&1; then
        HEALTHY=true
        echo "   ✅ Health check PASSED!"
        break
    fi
    sleep 2
done

if [ "$HEALTHY" = false ]; then
    echo "❌ Health check FAILED! Rolling back..."
    docker stop "commands-app-${TARGET_COLOR}" 2>/dev/null || true
    docker rm "commands-app-${TARGET_COLOR}" 2>/dev/null || true
    echo "⚠️ Kept ${CURRENT_COLOR} running. Deployment aborted safely."
    exit 1
fi

# 6. Switch Traffic by updating Nginx Upstream
echo "🔄 Switching Nginx traffic to ${TARGET_COLOR} (Port ${TARGET_PORT})..."
echo "upstream active_backend { server 127.0.0.1:${TARGET_PORT}; }" | sudo tee /etc/nginx/conf.d/upstream.conf > /dev/null

# Validate and reload Nginx (Zero Downtime)
sudo nginx -t
sudo nginx -s reload
echo "✅ Nginx traffic successfully switched to ${TARGET_COLOR}!"

# 7. Gracefully stop and remove the old active container
if [ "$CURRENT_COLOR" != "none" ]; then
    echo "🛑 Stopping old container: commands-app-${CURRENT_COLOR}..."
    sleep 2
    docker stop "commands-app-${CURRENT_COLOR}" 2>/dev/null || true
    docker rm "commands-app-${CURRENT_COLOR}" 2>/dev/null || true
    echo "✅ Old container stopped and cleaned up."
fi

# 8. Clean up unused docker images to protect 8GB EBS disk
echo "🧹 Pruning unused Docker images (protecting 8GB storage)..."
docker image prune -af --filter "until=24h" >/dev/null 2>&1 || true

echo "=============================================="
echo "🎉 SUCCESS: Blue/Green Deployment Complete!"
echo "Active Container : commands-app-${TARGET_COLOR}"
echo "Active Port      : ${TARGET_PORT}"
echo "Server URL       : http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'localhost')"
echo "=============================================="
