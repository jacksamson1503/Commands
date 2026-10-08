# 📘 Zero-Downtime Blue/Green CI/CD Pipeline Guide
### Repository: `https://github.com/jacksamson1503/Commands.git`
### Target: AWS EC2 (`t3.micro` + 8 GB Storage) & Amazon ECR via GitHub Actions

This guide explains the exact, step-by-step method to run automated zero-downtime **Blue/Green deployments** for your **Ops Notebook (`Commands`)** application on AWS EC2.

---

## 🧠 1. How Blue/Green Works on Your EC2

```
                       Visitors (Port 80 HTTP)
                                  ↓
                        [ Nginx on your EC2 ]
                                  ↓
                   ┌──────────────┴──────────────┐
                   ▼                             ▼
        [ Slot BLUE: 8081 ]            [ Slot GREEN: 8082 ]
         (Currently Live)               (Next Version Test)
```

1. **Host Nginx** listens on port `80` (public web).
2. Two container slots exist:
   - **`commands-app-blue`** running on internal port `8081`
   - **`commands-app-green`** running on internal port `8082`
3. When you push code to GitHub:
   - GitHub Actions checks out code, builds the Docker image, and pushes it to **Amazon ECR**.
   - It SSHes into your EC2 server.
   - It runs the new version in the **idle slot** (e.g., Green on `8082`).
   - It checks `/health` to verify the container is running and healthy.
   - Once healthy, Nginx upstream flips to Green in **0 milliseconds** (Zero Downtime).
   - Old Blue container is stopped to save RAM on `t3.micro`.
   - Old Docker images are automatically pruned to protect your **8 GB disk space**.

---

## 📁 2. Files Added to this Repository

| File | Purpose |
|---|---|
| `Dockerfile` | Builds your `index.html` inside lightweight `nginx:alpine` (~25MB total image size). |
| `nginx.conf` | In-container Nginx config with `/health` route and asset caching. |
| `.dockerignore` | Keeps build context small and fast. |
| `.github/workflows/deploy.yml` | GitHub Actions pipeline (Checkout ➔ ECR ➔ Blue/Green Deploy on EC2). |
| `scripts/setup-ec2.sh` | 1-time script to set up Docker, AWS CLI, Nginx, and **2GB swap space** on EC2. |
| `scripts/deploy.sh` | Automated zero-downtime deployment script with health checks and cleanup. |
| `scripts/nginx-host.conf` | Host Nginx reverse proxy configuration. |

---

## 🚀 3. Step-by-Step Instructions

Follow these 4 simple steps:

### Step 1: AWS Setup (5 Minutes)

#### A. Create Private ECR Repository
1. In the AWS Console, open **Amazon ECR** -> **Repositories**.
2. Click **Create repository**.
3. Select **Private**, enter repository name: `commands-app`.
4. Click **Create repository**.

#### B. Create IAM User for GitHub Actions
1. In the AWS Console, open **IAM** -> **Users** -> **Create user**.
2. Name: `github-actions-deployer`.
3. Choose **Attach policies directly** -> Search and check:
   - `AmazonEC2ContainerRegistryFullAccess`
4. Click **Next** -> **Create user**.
5. Click on `github-actions-deployer` -> **Security credentials** tab.
6. Under **Access keys**, click **Create access key** (Application running outside AWS).
7. Save the **Access Key ID** and **Secret Access Key**.

#### C. EC2 Security Group
In your EC2 instance's Security Group, verify Inbound rules:
- **Port 22 (SSH)**: Source `0.0.0.0/0` (or your IP + GitHub Actions).
- **Port 80 (HTTP)**: Source `0.0.0.0/0` (public visitors).

---

### Step 2: One-Time EC2 Server Preparation (2 Minutes)

SSH into your EC2 instance:
```bash
ssh -i your-key.pem ubuntu@<YOUR-EC2-PUBLIC-IP>
```

Run this command to install Docker, Nginx, and configure 2GB swap space:
```bash
curl -sSL https://raw.githubusercontent.com/jacksamson1503/Commands/main/scripts/setup-ec2.sh | bash
newgrp docker
```

---

### Step 3: Add GitHub Secrets (2 Minutes)

In your GitHub repository (`https://github.com/jacksamson1503/Commands`):
1. Go to **Settings** -> **Secrets and variables** -> **Actions**.
2. Click **New repository secret** and add:

| Secret Name | Example Value | Description |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | `AKIA...` | IAM User Access Key |
| `AWS_SECRET_ACCESS_KEY` | `wJalrX...` | IAM User Secret Key |
| `AWS_REGION` | `ap-south-1` *(or your region)* | AWS Region of ECR & EC2 |
| `ECR_REPOSITORY_NAME` | `commands-app` | ECR repository name |
| `EC2_HOST` | `13.232.xxx.xxx` | Public IP of your EC2 |
| `EC2_USER` | `ubuntu` | Ubuntu AMI user |
| `EC2_SSH_KEY` | `-----BEGIN RSA PRIVATE KEY-----...` | Entire text of your `.pem` key |

---

### Step 4: Commit and Push to Deploy!

Push the files to GitHub:

```bash
git add .
git commit -m "feat: Add zero-downtime Blue/Green CI/CD with Docker and ECR"
git push origin main
```

1. Open your repository's **Actions** tab on GitHub.
2. Watch the pipeline build the image, push to ECR, and execute the Blue/Green deployment on EC2.
3. Open `http://<YOUR-EC2-PUBLIC-IP>` in your browser to view your Ops Notebook live!

---

## 🔍 4. Verification & Testing Zero Downtime

1. Check running container on EC2:
   ```bash
   docker ps
   ```
   You will see `commands-app-blue` on port `8081`.

2. Edit a word or title in `index.html` and push to GitHub.
3. Watch EC2 while GitHub Actions runs:
   - `commands-app-green` starts on `8082`.
   - Passes health check.
   - Nginx switches traffic to green.
   - `commands-app-blue` is gracefully stopped.
   - Old Docker images are pruned so your 8 GB storage never runs out of space!
