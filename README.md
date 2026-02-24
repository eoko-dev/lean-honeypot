# lean-honeypot

Lightweight honeypot stack deployed via cloud-init and Docker Compose on Debian 12. No Terraform, no Kubernetes.

## Requirements

- Debian 12 VPS with at least **2 GB RAM**
- Cloud provider that supports cloud-init (DigitalOcean, Vultr, etc.)
- Cloud firewall must allow **all inbound TCP ports** (honeypot ports + management ports)

### Ports to open in your cloud firewall

| Port | Service | Purpose |
|-------|-----------|-----------|
| 21 | Dionaea | FTP honeypot |
| 22 | Cowrie | SSH honeypot |
| 23 | Cowrie | Telnet honeypot |
| 25 | Opencanary | SMTP honeypot |
| 80 | Dionaea | HTTP honeypot |
| 110 | Opencanary | POP3 honeypot |
| 443 | Dionaea | HTTPS honeypot |
| 445 | Dionaea | SMB honeypot |
| 1433 | Dionaea | MSSQL honeypot |
| 3306 | Dionaea | MySQL honeypot |
| 5060 | Dionaea | SIP honeypot |
| 5900 | Opencanary | VNC honeypot |
| 6379 | Opencanary | Redis honeypot |
| 8080 | Opencanary | HTTP proxy honeypot |
| 27017 | Opencanary | MongoDB honeypot |
| 64295 | OpenSSH | Real SSH (management) |
| 64296 | Grafana | Dashboard UI |

## Deployment

1. Create a Debian 12 VPS at your cloud provider
2. Paste the contents of `cloud-init.yaml` into the user-data / cloud-init field
3. **Before deploying**, edit the `git clone` URL in `cloud-init.yaml` to point to your fork
4. Launch the VPS and wait for cloud-init to finish (the server will reboot once at the end)
5. SSH in on port **64295**: `ssh -p 64295 honeypot@<ip>`
6. Access Grafana at `http://<ip>:64296` (default login: `admin` / `changeme`)

## Post-Deploy Checklist

- [ ] Change the Grafana admin password (Settings > Change Password, or set `GF_SECURITY_ADMIN_PASSWORD` env var)
- [ ] Verify all containers are running: `docker ps`
- [ ] Confirm Cowrie logs are flowing: `tail -f /var/log/cowrie/cowrie.json`
- [ ] Confirm Opencanary logs are flowing: `tail -f /var/log/opencanary/opencanary.log`
- [ ] Check the Grafana dashboard for incoming data

## Useful Commands

```bash
# Check running containers
docker ps

# Follow logs for a specific service
docker logs -f cowrie
docker logs -f dionaea
docker logs -f opencanary

# Resource usage
docker stats

# Restart the entire stack
cd /home/honeypot/lean-honeypot && docker compose restart

# Restart a single service
docker compose restart cowrie

# Pull updated images and recreate
docker compose pull && docker compose up -d

# Access Dionaea SQLite database for manual review
docker exec -it dionaea sqlite3 /opt/dionaea/var/lib/dionaea/dionaea.sqlite

# View Promtail targets and status
curl -s http://localhost:9080/targets
```

## Gotchas

- **Firewall**: Your cloud firewall must allow all inbound ports listed above. If attackers can't reach the honeypot ports, you won't collect any data.
- **Real SSH is on port 64295**: The default port 22 is taken by Cowrie. If you lock yourself out, use your cloud provider's console.
- **Grafana takes ~60s to start**: Don't panic if port 64296 doesn't respond immediately after boot.
- **Loki retention runs nightly, not instantly**: Old logs (>30 days) are cleaned up by the compactor on a schedule, not in real time.
- **Cowrie image tag**: The `cowrie/cowrie` image doesn't publish versioned tags consistently. Pin to `latest` and note the digest after pulling if reproducibility matters.
