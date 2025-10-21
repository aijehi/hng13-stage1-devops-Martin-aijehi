#!/bin/bash

# ===============================================
# Automated Dockerized Application Deployment
# Author: Aston
# Description: Automates setup, deployment, and configuration
# ===============================================

# --- CONFIGURATION ---
LOG_FILE="deploy_$(date +%Y%m%d).log"

# --- LOGGING FUNCTION ---
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# --- ERROR HANDLING ---
set -e
trap 'log "❌ Error occurred on line $LINENO. Exiting."; exit 1;' ERR

# --- 1. COLLECT USER INPUT ---
read -p "Enter Git Repository URL: " GIT_URL
read -p "Enter Personal Access Token (PAT): " PAT
read -p "Enter Branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}

read -p "Enter Remote SSH Username: " SSH_USER
read -p "Enter Remote Server IP: " SERVER_IP
read -p "Enter SSH Key Path (e.g. /home/aston/huawei-test.pem): " SSH_KEY
read -p "Enter Application Port (container internal port): " APP_PORT

# --- VALIDATION ---
if [[ -z "$GIT_URL" || -z "$PAT" || -z "$SSH_USER" || -z "$SERVER_IP" || -z "$SSH_KEY" || -z "$APP_PORT" ]]; then
  log "⚠️ Missing required inputs. Please check and try again."
  exit 1
fi

log "✅ All parameters collected successfully."

# --- 2. CLONE OR UPDATE REPO ---
REPO_NAME=$(basename -s .git "$GIT_URL")

if [[ -d "$REPO_NAME" ]]; then
  log "📂 Repository exists. Pulling latest changes..."
  cd "$REPO_NAME"
  git pull origin "$BRANCH" | tee -a "$LOG_FILE"
else
  log "📥 Cloning repository..."
  git clone -b "$BRANCH" "https://${PAT}@${GIT_URL#https://}" | tee -a "$LOG_FILE"
  cd "$REPO_NAME"
fi

log "✅ Repository ready."

# --- 3. VERIFY DOCKERFILE/COMPOSE ---
if [[ -f "Dockerfile" ]]; then
  log "✅ Dockerfile found."
elif [[ -f "docker-compose.yml" ]]; then
  log "✅ docker-compose.yml found."
else
  log "❌ No Dockerfile or docker-compose.yml found. Exiting."
  exit 1
fi

# --- 4. TEST REMOTE SSH CONNECTION ---
log "🔗 Testing SSH connection..."
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" "echo Connection successful

" || {
  log "❌ SSH connection failed."
  exit 1
}

log "✅ SSH connection successful."

# --- Next Steps (To Be Added Later) ---
# - Install Docker, Docker Compose, Nginx
# - Transfer project and deploy containers
# - Configure reverse proxy
# - Validate deployment and log results

# --- 5. SET UP REMOTE SERVER ENVIRONMENT ---
echo "⚙️ Setting up Docker, Docker Compose, and Nginx on remote server..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" << 'EOF'

# --- Check for sudo privileges ---
if ! sudo -n true 2>/dev/null; then
  echo "Error: User does not have sudo privileges"
  exit 1
fi

# --- Update and install dependencies ---
echo "Updating package index and installing dependencies..."
sudo apt-get update -y || { echo "Failed to update apt"; exit 1; }
sudo apt-get install -y ca-certificates curl gnupg lsb-release || { echo "Failed to install dependencies"; exit 1; }

# --- Install Docker ---
if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Failed to download Docker GPG key"; exit 1; }
  sudo chmod 644 /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Failed to add Docker repository"; exit 1; }
  sudo apt-get update -y || { echo "Failed to update apt"; exit 1; }
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Failed to install Docker"; exit 1; }
  sudo systemctl enable docker || { echo "Failed to enable Docker"; exit 1; }
  sudo systemctl start docker || { echo "Failed to start Docker"; exit 1; }
else
  echo "✅ Docker already installed."
fi

# --- Verify Docker Compose plugin ---
if ! docker compose version &> /dev/null; then
  echo "Docker Compose plugin not found. Ensuring it is installed..."
  sudo apt-get install -y docker-compose-plugin || { echo "Failed to install Docker Compose plugin"; exit 1; }
else
  echo "✅ Docker Compose plugin already installed."
fi

# --- Install Nginx ---
if ! command -v nginx &> /dev/null; then
  echo "Installing Nginx..."
  sudo apt-get install -y nginx || { echo "Failed to install Nginx"; exit 1; }
  sudo systemctl enable nginx || { echo "Failed to enable Nginx"; exit 1; }
  sudo systemctl start nginx || { echo "Failed to start Nginx"; exit 1; }
  sudo systemctl is-active --quiet nginx || { echo "Nginx is not running"; exit 1; }
else
  echo "✅ Nginx already installed."
fi

echo "✅ Remote server setup completed successfully."
exit 0
EOF

# --- 6. DEPLOY APPLICATION CONTAINER ---
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 Deploying container on remote server..."

# Debug variables to ensure they are set
echo "DEBUG: SSH_USER=$SSH_USER, SERVER_IP=$SERVER_IP, SSH_KEY=$SSH_KEY, APP_PORT=$APP_PORT"

# SSH to remote server
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=10 "$SSH_USER@$SERVER_IP" << 'EOF' || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Deployment failed on remote server"; exit 1; }

# --- Define variables ---
APP_DIR="/opt/myapp"
REPO_DIR="$APP_DIR/repo"
IMAGE_NAME="myapp:latest"
CONTAINER_NAME="myapp_container"
GITHUB_REPO="https://github.com/aijehi/hng13-stage1-devops-Martin-aijehi"
GIT_PAT=""  # From user input
APP_PORT="8080"  # Use 8080 to avoid conflict with Nginx

# --- Check if Docker is running ---
if ! sudo systemctl is-active --quiet docker; then
  echo "Starting Docker..."
  sudo systemctl start docker || { echo "Failed to start Docker"; exit 1; }
fi

# --- Create app directory ---
sudo mkdir -p "$REPO_DIR" || { echo "Failed to create $REPO_DIR"; exit 1; }
cd "$REPO_DIR" || { echo "Failed to navigate to $REPO_DIR"; exit 1; }

# --- Clone or update repository ---
if [ -d ".git" ]; then
  echo "🔁 Updating existing repository..."
  sudo git fetch origin
  sudo git reset --hard origin/main || { echo "Failed to update repository"; exit 1; }
else
  echo "📦 Cloning repository..."
  sudo git clone "https://$GIT_PAT@github.com/aijehi/hng13-stage1-devops-Martin-aijehi.git" . || { echo "Failed to clone repository"; exit 1; }
fi

# --- Check for Dockerfile ---
if [ ! -f Dockerfile ]; then
  echo "Dockerfile not found in $REPO_DIR"
  exit 1
fi

# --- Verify Dockerfile is not empty ---
if [ ! -s Dockerfile ]; then
  echo "Dockerfile is empty in $REPO_DIR"
  exit 1
fi

# --- Build Docker image ---
echo "🛠️ Building Docker image..."
sudo docker build -t "$IMAGE_NAME" . || { echo "Failed to build Docker image"; exit 1; }

# --- Stop and remove existing container if running ---
if [ "$(sudo docker ps -q -f name=$CONTAINER_NAME)" ]; then
  echo "🧹 Stopping old container..."
  sudo docker stop "$CONTAINER_NAME" || { echo "Failed to stop container"; exit 1; }
  sudo docker rm "$CONTAINER_NAME" || { echo "Failed to remove container"; exit 1; }
fi

# --- Run new container ---
echo "🚀 Starting new container..."
sudo docker run -d --name "$CONTAINER_NAME" -p "$APP_PORT:80" "$IMAGE_NAME" || { echo "Failed to start container"; exit 1; }

# --- Confirm deployment ---
echo "✅ Container deployment successful!"
sudo docker ps --filter "name=$CONTAINER_NAME"
exit 0

EOF

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Container deployed successfully!"

# --- 7. CONFIGURE NGINX AS REVERSE PROXY ---
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🌐 Configuring Nginx reverse proxy..."

ssh -i "$SSH_KEY" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  "$SSH_USER@$SERVER_IP" << 'EOF' || { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Failed to configure Nginx on remote server"; exit 1; }

# --- Variables ---
SERVER_NAME="_"                # Change to your domain if you have one
APP_PORT=8080                  # Must match the Docker container’s host port
NGINX_CONF="/etc/nginx/sites-available/myapp.conf"
NGINX_LINK="/etc/nginx/sites-enabled/myapp.conf"

# --- Create Nginx config ---
echo "📝 Creating Nginx configuration..."
    log_info "Configuring Nginx as a reverse proxy on remote server..."

    sudo bash -c "cat > $NGINX_CONF <<'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8080;  # or the port your container uses
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
    }
}
EOF"


# --- Remove existing default Nginx site (if any) ---
if [ -f /etc/nginx/sites-enabled/default ]; then
  echo "🧹 Removing default Nginx site..."
  sudo rm -f /etc/nginx/sites-enabled/default || { echo "Failed to remove default Nginx site"; exit 1; }
fi

# --- Enable the new configuration ---
echo "🔗 Enabling Nginx configuration..."
sudo ln -sf "$NGINX_CONF" "$NGINX_LINK" || { echo "Failed to enable Nginx configuration"; exit 1; }

# --- Test Nginx configuration ---
echo "🔍 Testing Nginx configuration..."
sudo nginx -t || { echo "Nginx configuration test failed"; exit 1; }

# --- Reload Nginx ---
echo "🔄 Reloading Nginx..."
sudo systemctl reload nginx || { echo "Failed to reload Nginx"; exit 1; }

echo "✅ Nginx configuration completed successfully!"
exit 0

EOF

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Nginx reverse proxy configured successfully!"
