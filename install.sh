#!/bin/bash
set -euo pipefail

LOG="/var/log/lean-honeypot-install.log"
exec > >(tee -a "$LOG") 2>&1

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root (sudo ./install.sh)"
  exit 1
fi

# Must be Debian
if [ ! -f /etc/debian_version ]; then
  echo "Error: Debian 12 required"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== lean-honeypot install: $(date) ==="

# Install dependencies
apt-get update
apt-get install -y git curl wget ca-certificates gnupg

# Install Docker CE if not present
if ! command -v docker &>/dev/null; then
  echo "Installing Docker CE..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "Docker installed."
else
  echo "Docker already installed, skipping."
fi

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
until docker info >/dev/null 2>&1; do sleep 2; done
echo "Docker is ready."

# Move real SSH to port 64295
if ! grep -q "Port 64295" /etc/ssh/sshd_config.d/port.conf 2>/dev/null; then
  echo "Port 64295" > /etc/ssh/sshd_config.d/port.conf
  echo "SSH moved to port 64295. Will take effect after reboot."
fi

# Stop services that conflict with honeypot ports
echo "Stopping conflicting services..."
for svc in exim4 postfix sendmail; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

# Create log directories
mkdir -p /var/log/cowrie /var/log/opencanary
chown 1000:1000 /var/log/cowrie

# Create .env if it doesn't exist
if [ ! -f "$SCRIPT_DIR/.env" ]; then
  cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
  echo "Created .env from .env.example — edit GF_SECURITY_ADMIN_PASSWORD before going live."
fi

# Start the stack
echo "Starting containers..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d --build

echo ""
echo "=== Install complete: $(date) ==="
echo ""
echo "Next steps:"
echo "  1. Edit .env and set a real Grafana password"
echo "  2. Reboot to move SSH to port 64295"
echo "  3. Access Grafana at http://<your-ip>:64296"
echo ""
echo "Log saved to $LOG"
