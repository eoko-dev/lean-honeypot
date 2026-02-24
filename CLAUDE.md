# lean-honeypot

Lightweight honeypot deployment stack using cloud-init + Docker Compose on Debian 12.

## Project Structure

- `cloud-init.yaml` — VPS bootstrap: installs Docker, moves SSH to port 64295, clones repo to `/root/lean-honeypot`, starts the stack
- `docker-compose.yml` — All services on `honeypot-net` bridge network
- `config/` — Per-service configuration files (mounted read-only into containers)
- `dashboards/` — Grafana dashboard JSON (auto-provisioned)

## Services

| Service | Image | Role |
|-----------|-------|------|
| Cowrie | `cowrie/cowrie` | SSH/Telnet honeypot (ports 22, 23) |
| Dionaea | `dinotools/dionaea:0.11.0` | Multi-protocol honeypot (FTP, HTTP, SMB, MSSQL, MySQL, SIP) |
| Opencanary | `opencanary/opencanary:0.9.3` | Lightweight listeners (SMTP, POP3, VNC, Redis, HTTP-alt, MongoDB) |
| Loki | `grafana/loki:2.9.0` | Log aggregation (internal only, no host port) |
| Promtail | `grafana/promtail:2.9.0` | Log shipper — scrapes Cowrie + Opencanary JSON logs |
| Grafana | `grafana/grafana:10.2.0` | Dashboard UI on host port 64296 |

## Key Conventions

- No Terraform, Ansible, or Kubernetes — cloud-init and Docker Compose only
- All Docker image versions are pinned (except Cowrie which lacks stable tags)
- No placeholders in configs except `GF_SECURITY_ADMIN_PASSWORD` (defaults to `changeme`)
- Real SSH runs on port 64295; port 22 belongs to Cowrie
- Grafana on port 64296
- Log pipeline: Cowrie/Opencanary write JSON to `/var/log/` → Promtail ships to Loki → Grafana queries Loki
- Dionaea data is in a named volume; review via `docker exec` + sqlite3
- Runs as root — this is a dedicated throwaway VPS, no separate user needed
- Target environment: 2 GB RAM Debian 12 VPS

## Editing Guidelines

- Keep configs minimal — no over-commenting
- When adding a new honeypot service, add its ports to the README port table and configure Promtail scraping if it outputs JSON logs
- Dashboard changes go in `dashboards/honeypot-overview.json`; Grafana auto-reloads from that path
