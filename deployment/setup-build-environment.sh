#!/bin/bash
# Setup Ubuntu VPS for building Dittofeed images
# Run with: curl -fsSL https://raw.githubusercontent.com/aymensakka/dittofeed/main/deployment/setup-build-environment.sh | bash

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    log_error "Please run as root or with sudo"
    exit 1
fi

log_info "Setting up build environment on Ubuntu..."

# Update system
log_info "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install basic tools
log_info "Installing basic tools..."
apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release

# Install Docker
if ! command -v docker &> /dev/null; then
    log_info "Installing Docker..."
    
    # Add Docker's official GPG key
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Enable Docker service
    systemctl enable docker
    systemctl start docker
    
    log_info "Docker installed successfully"
else
    log_info "Docker is already installed"
fi

# Install Node.js and Yarn
if ! command -v node &> /dev/null; then
    log_info "Installing Node.js..."
    
    # Install Node.js 18.x
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
    
    log_info "Node.js installed: $(node -v)"
else
    log_info "Node.js is already installed: $(node -v)"
fi

if ! command -v yarn &> /dev/null; then
    log_info "Installing Yarn..."
    npm install -g yarn
    log_info "Yarn installed: $(yarn -v)"
else
    log_info "Yarn is already installed: $(yarn -v)"
fi

# Setup docker group for non-root user (if exists)
if [ -n "$SUDO_USER" ]; then
    log_info "Adding $SUDO_USER to docker group..."
    usermod -aG docker $SUDO_USER
    log_info "User $SUDO_USER added to docker group. Please logout and login for changes to take effect."
fi

# Increase some system limits for building
log_info "Optimizing system for Docker builds..."
cat >> /etc/sysctl.conf <<EOF

# Increase inotify limits for Docker
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=524288
EOF

sysctl -p

log_info "Build environment setup complete!"
log_info "Next steps:"
echo "  1. Clone the repository: git clone https://github.com/aymensakka/dittofeed.git"
echo "  2. cd dittofeed"
echo "  3. Run: ./deployment/build-and-push-images.sh"

# Check Docker
docker --version
node --version
yarn --version