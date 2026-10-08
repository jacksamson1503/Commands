#!/usr/bin/env bash
set -e

# ==============================================================================
# Zero-Downtime Blue/Green Deployment Script (Crash-Proof)
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

# 1. Determine which color and port are currently active
if docker ps --format '{{.Names}}' | grep -q "commands-blue"; then
    CURRENT_COLOR="blue"
    CURRENT_PORT=8081
    TARGET_COLOR="green"
    TARGET_PORT=8082
elif docker ps --format '{{.Names}}' | grep -q "commands-green"; then
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

echo "📍 Current Active Slot : commands-${CURRENT_COLOR} (Port: ${CURRENT_PORT})"
echo "🎯 Deploying Target Slot: commands-${TARGET_COLOR} (Port: ${TARGET_PORT})"

# 2. Pull the latest Docker image from ECR
echo "📦 Pulling new image from ECR..."
docker pull "$IMAGE_URI"

# 3. Clean up any stale container in the TARGET slot
echo "🧹 Cleaning up old target container if present..."
docker rm -f "commands-${TARGET_COLOR}" 2>/dev/null || true

# 4. Start the new container on the TARGET slot
echo "▶️  Starting commands-${TARGET_COLOR} on 127.0.0.1:${TARGET_PORT}..."
docker run -d \
    --name "commands-${TARGET_COLOR}" \
    -p 127.0.0.1:${TARGET_PORT}:80 \
    --restart unless-stopped \
    "$IMAGE_URI"

# 5. Health Check: Test the new container in private
echo "🩺 Running health checks on port ${TARGET_PORT}..."
HEALTHY=false
for i in {1..8}; do
    echo "   Attempt $i/8: checking http://127.0.0.1:${TARGET_PORT}/health ..."
    if curl -sf "http://127.0.0.1:${TARGET_PORT}/health" >/dev/null 2>&1; then
        HEALTHY=true
        echo "   ✅ Health check PASSED!"
        break
    fi
    sleep 2
done

# If Health Check FAILED: ABORT and keep current live container running!
if [ "$HEALTHY" = false ]; then
    echo "❌ Health check FAILED! The new code is broken."
    echo "🧹 Removing broken container commands-${TARGET_COLOR}..."
    docker rm -f "commands-${TARGET_COLOR}" 2>/dev/null || true
    echo "🛡️ SAFE ROLLBACK: Keeping live container commands-${CURRENT_COLOR} on port ${CURRENT_PORT} completely untouched!"
    echo "🚨 Pipeline will now fail, but your live website is still 100% online!"
    exit 1
fi

# 6. If Healthy: Switch Traffic by updating Nginx Upstream
echo "🔄 Switching Nginx traffic to ${TARGET_COLOR} (Port ${TARGET_PORT})..."
echo "upstream active_backend { server 127.0.0.1:${TARGET_PORT}; }" | sudo tee /etc/nginx/conf.d/upstream.conf > /dev/null

# Reload Nginx (Zero Downtime)
sudo nginx -t
sudo nginx -s reload
echo "✅ Nginx traffic successfully switched to ${TARGET_COLOR}!"

# 7. Gracefully stop the old container
if [ "$CURRENT_COLOR" != "none" ]; then
    echo "🛑 Stopping old container: commands-${CURRENT_COLOR}..."
    docker rm -f "commands-${CURRENT_COLOR}" 2>/dev/null || true
    echo "✅ Old container cleaned up."
fi

# 8. Clean up unused docker images to protect 8GB storage
docker image prune -af --filter "until=24h" >/dev/null 2>&1 || true

echo "=============================================="
echo "🎉 SUCCESS: Blue/Green Deployment Complete!"
echo "Active Container : commands-${TARGET_COLOR}"
echo "Active Port      : ${TARGET_PORT}"
echo "=============================================="
