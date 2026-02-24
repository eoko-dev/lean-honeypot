#!/bin/bash
set -euo pipefail

LOG="/var/log/lean-honeypot-install.log"
exec > >(tee -a "$LOG") 2>&1

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: run as root (sudo ./install.sh)"
  exit 1
fi

# Must be Debian or Ubuntu
if [ ! -f /etc/os-release ]; then
  echo "Error: Debian 12 or Ubuntu 24.04+ required"
  exit 1
fi
# shellcheck source=/dev/null
. /etc/os-release
if [ "$ID" != "debian" ] && [ "$ID" != "ubuntu" ]; then
  echo "Error: Debian 12 or Ubuntu 24.04+ required (detected: ${ID:-unknown})"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== lean-honeypot install: $(date) ==="

# Install dependencies
apt-get update
apt-get install -y git curl wget ca-certificates gnupg psmisc

# Install Docker CE if not present, or add compose plugin if missing
if ! command -v docker &>/dev/null; then
  echo "Installing Docker CE..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "Docker installed."
elif ! docker compose version &>/dev/null; then
  echo "Docker found but compose plugin missing, installing..."
  apt-get update
  apt-get install -y docker-compose-plugin
  echo "Compose plugin installed."
else
  echo "Docker and compose plugin already installed, skipping."
fi

systemctl enable docker
systemctl start docker

# Wait for Docker daemon
echo "Waiting for Docker daemon..."
TRIES=0
until docker info >/dev/null 2>&1; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 30 ]; then
    echo "Error: Docker daemon failed to start after 60s"
    exit 1
  fi
  sleep 2
done
echo "Docker is ready."

# Move real SSH to port 64295
mkdir -p /etc/ssh/sshd_config.d
if ! grep -q "Port 64295" /etc/ssh/sshd_config.d/port.conf 2>/dev/null; then
  echo "Port 64295" > /etc/ssh/sshd_config.d/port.conf
  echo "SSH will move to port 64295 after reboot."
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

# Build images and start the stack so Docker tracks container state.
# restart: unless-stopped then handles all future reboots automatically.
echo "Building container images..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" build

echo "Starting honeypot stack..."
docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d

# Create systemd service for auto-start on boot
echo "Creating systemd service for honeypot stack..."
cat > /etc/systemd/system/lean-honeypot.service <<EOF
[Unit]
Description=Lean Honeypot Docker Compose Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$SCRIPT_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable lean-honeypot.service
echo "Systemd service created and enabled."

echo ""
echo "=== Install complete: $(date) ==="
echo ""
echo "The system will now reboot to:"
echo "  - Move SSH to port 64295 (reconnect on that port after reboot)"
echo "  - Free port 22 for the Cowrie honeypot"
echo "  - Auto-start the honeypot stack via systemd"
echo ""
echo "After reboot:"
echo "  ssh -p 64295 root@<your-ip>"
echo "  Grafana: http://<your-ip>:64296"
echo ""
echo "Log saved to $LOG"
echo ""
echo "Rebooting in 5 seconds..."
sleep 5
reboot
