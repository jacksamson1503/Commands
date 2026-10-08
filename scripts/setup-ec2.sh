#!/usr/bin/env bash
set -e

# ==============================================================================
# One-Time EC2 Setup Script for Ubuntu (t3.micro, 8GB storage)
# Application: commands-app (Ops Notebook)
# ==============================================================================

echo "=============================================="
echo "🛠️  Starting 1-Time EC2 Setup for Blue/Green CI/CD"
echo "=============================================="

# 1. Update OS packages
echo "🔄 Updating package lists..."
sudo apt-get update -y
sudo apt-get upgrade -y

# 2. Setup 2GB Swap Memory (CRITICAL for t3.micro 1GB RAM)
if [ ! -f /swapfile ]; then
    echo "🧠 Creating 2GB Swap Memory to prevent OOM errors on t3.micro..."
    sudo fallocate -l 2G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
    echo "✅ Swap memory enabled (2GB)."
else
    echo "ℹ️  Swapfile already exists. Skipping."
fi

# 3. Install Docker
echo "🐳 Installing Docker..."
sudo apt-get install -y ca-certificates curl gnupg lsb-release nginx unzip

if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm -f get-docker.sh
fi

sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker
echo "✅ Docker installed and configured."

# 4. Install AWS CLI v2 (needed for ECR authentication)
if ! command -v aws &> /dev/null; then
    echo "☁️ Installing AWS CLI v2..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    echo "✅ AWS CLI v2 installed."
else
    echo "ℹ️  AWS CLI already installed."
fi

# 5. Configure Nginx Reverse Proxy for Blue/Green
echo "🌐 Configuring Nginx Reverse Proxy..."

# Create upstream definition (default pointing to 8081 Blue)
echo "upstream active_backend { server 127.0.0.1:8081; }" | sudo tee /etc/nginx/conf.d/upstream.conf > /dev/null

# Configure default site
sudo tee /etc/nginx/sites-available/default > /dev/null << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://active_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 3s;
        proxy_read_timeout 60s;
    }
}
EOF

# Test and enable Nginx
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx
echo "✅ Nginx configured and running on port 80."

# 6. Ensure deployment script exists in /home/ubuntu/deploy.sh
echo "📁 Setting up deployment script in /home/ubuntu..."
if [ -f "$(dirname "$0")/deploy.sh" ]; then
    cp "$(dirname "$0")/deploy.sh" /home/ubuntu/deploy.sh
fi
chmod +x /home/ubuntu/deploy.sh 2>/dev/null || true

# 7. Configure automated disk maintenance for 8GB EBS storage
echo "🧹 Setting up weekly Docker disk cleaner in crontab..."
(crontab -l 2>/dev/null | grep -v 'docker system prune' ; echo "0 3 * * 0 docker system prune -af --volumes >/dev/null 2>&1") | crontab -

echo "=============================================="
echo "🎉 EC2 Setup Complete!"
echo "Please log out and log back in (or run 'newgrp docker') to use docker without sudo."
echo "=============================================="
