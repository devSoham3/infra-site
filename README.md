# infra-site

Docker-based infrastructure for hosting a personal portfolio website and work applications, served via Nginx reverse proxy with automatic HTTPS using Let's Encrypt.

## Architecture

```
Internet
   │
   ├── sohamdeo.com          ──► Portfolio app (Docker, port 3000)
   ├── www.sohamdeo.com      ──► 301 → sohamdeo.com
   ├── portfolio.sohamdeo.com──► 301 → sohamdeo.com
   ├── sub1.sohamdeo.com     ──► Host VM port 8500
   ├── sub2.sohamdeo.com     ──► Host VM port 8600
   └── sub3.sohamdeo.com     ──► Host VM port 8700
          │
     [ Nginx reverse proxy ]
          │
    ┌─────┴──────────────────────────────┐
    │  Monitoring (internal-only)        │
    │  ├── Grafana      (port 3001)      │
    │  ├── Prometheus   (port 9090)      │
    │  └── cAdvisor     (port 8080)      │
    └────────────────────────────────────┘
```

## Services

| Service | Image | Description |
|---------|-------|-------------|
| `portfolio-site` | `ghcr.io/devsoham3/portfolio-site:latest` | Next.js portfolio app |
| `nginx` | Custom build (nginx:latest) | Reverse proxy + SSL termination |
| `certbot` | `certbot/certbot:latest` | SSL certificate issuance and renewal |
| `prometheus` | `prom/prometheus:latest` | Metrics scraping (internal only) |
| `grafana` | `grafana/grafana:latest` | Metrics dashboard (internal only) |
| `cadvisor` | `gcr.io/cadvisor/cadvisor:latest` | Container metrics (internal only) |
| `node-exporter` | `prom/node-exporter:latest` | Host metrics |

Monitoring services are exposed only on `127.0.0.1` (not publicly accessible) and are reachable through the `/grafana/`, `/prometheus/`, and `/cadvisor/` paths on the main domain — behind basic auth.

## SSL Strategy

A single **SAN (Subject Alternative Names) certificate** issued by Let's Encrypt covers the root domain and all subdomains. All Nginx server blocks reference the same cert at:

```
/etc/letsencrypt/live/yourdomain.com/fullchain.pem
/etc/letsencrypt/live/yourdomain.com/privkey.pem
```

Certificates are stored in `./certbot/conf/` and mounted into both the `certbot` and `nginx` containers.

## Prerequisites

- Docker + Docker Compose
- Ports `80` and `443` open on your VM/firewall
- DNS A records for your root domain and all subdomains pointing to your server's public IP

## Setup

### 1. Environment Variables

```bash
cp .env.example .env
# Edit .env with your credentials
```

Required variables:

```env
GF_SECURITY_ADMIN_USER=          # Grafana admin username
GF_SECURITY_ADMIN_PASSWORD=      # Grafana admin password
GF_SERVER_ROOT_URL=              # Full URL to Grafana, e.g. https://yourdomain.com/grafana
MONITORING_USER=                 # Basic auth user for Prometheus & cAdvisor
MONITORING_PASSWORD=             # Basic auth password for Prometheus & cAdvisor
```

### 2. Issue SSL Certificates

The `SSL-gen.sh` script handles the ACME challenge workflow for a single domain. For a **multi-domain SAN cert** (recommended), run certbot directly:

```bash
# Step 1: Switch to HTTP-only config so certbot can complete the ACME challenge
cp ./nginx/default.http.conf ./nginx/default.conf
docker compose up -d nginx

# Step 2: Issue the certificate — add one -d flag per domain/subdomain
docker compose run --rm certbot certonly \
  --webroot --webroot-path=/var/www/certbot \
  --email you@example.com --agree-tos --no-eff-email \
  -d yourdomain.com \
  -d www.yourdomain.com \
  -d sub1.yourdomain.com \
  -d sub2.yourdomain.com
  # Add as many -d flags as you need

# Step 3: Switch to full HTTPS config
cp ./nginx/default.https.conf ./nginx/default.conf
docker compose restart nginx
```

> **Adding subdomains later:** Re-run Step 2 with **all** previous `-d` flags **plus** the new domain. Certbot will expand and re-issue the cert. Then restart nginx.

### 3. Start All Services

```bash
docker compose up -d
```

### 4. Verify

```bash
# Nginx config syntax check
docker compose exec nginx nginx -t

# Confirm cert covers all your domains
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -text | grep "DNS:"
```

## Nginx Configuration

| File | Purpose |
|------|---------|
| `nginx/default.conf` | **Active config** — loaded by the running nginx container |
| `nginx/default.https.conf` | Full HTTPS config template — copied to `default.conf` after cert issuance |
| `nginx/default.http.conf` | HTTP-only template — used during ACME challenge (no SSL required) |
| `nginx/nginx.conf` | Global nginx settings (worker processes, logging, timeouts) |
| `nginx/Dockerfile` | Custom nginx image — installs `apache2-utils` for `htpasswd` |
| `nginx/generate-htpasswd.sh` | Entrypoint script that generates `.htpasswd` from env vars at startup |

### Proxying to Host VM Ports

Subdomains that reverse-proxy to applications running directly on the host VM (outside Docker) use the special hostname `host-gateway`, which is mapped in `docker-compose.yml`:

```yaml
extra_hosts:
  - "host-gateway:host-gateway"
```

This lets nginx route `proxy_pass http://host-gateway:8500` to port `8500` on the host machine, without exposing that port publicly or changing the app's configuration.

WebSocket support (`Upgrade` / `Connection` headers) is pre-configured on these proxy blocks, making them compatible with Streamlit and other WebSocket-based apps out of the box.

> [!IMPORTANT]
> **Apps must bind to `0.0.0.0`, not `127.0.0.1`.**
> The nginx container routes to the host via the Docker bridge network. The loopback interface (`127.0.0.1`) on the host is not reachable from inside the container, so apps bound only to loopback will return a 502.
>
> ```bash
> # FastAPI/uvicorn — default is 127.0.0.1, must override
> uvicorn main:app --host 0.0.0.0 --port 8500
>
> # Streamlit — default is already 0.0.0.0, no change needed
> streamlit run app.py --server.port 8600
>
> # docker run — publishes to 0.0.0.0 by default
> docker run -p 8700:8700 your-image
> ```
>
> This applies regardless of which OS user starts the process — nginx routes by port number at the network level, not by user.

## Certificate Renewal

Certbot auto-renewal is handled by the `certbot` container. To manually trigger a renewal:

```bash
docker compose run --rm certbot renew
docker compose restart nginx
```

## Directory Structure

```
infra-site/
├── docker-compose.yml        # Service definitions
├── .env                      # Secrets (not committed)
├── .env.example              # Template for .env
├── SSL-gen.sh                # Helper script for single-domain cert issuance
├── nginx/
│   ├── Dockerfile            # Custom nginx image
│   ├── nginx.conf            # Global nginx config
│   ├── default.conf          # Active virtual host config (gitignored during ACME)
│   ├── default.https.conf    # HTTPS template
│   ├── default.http.conf     # HTTP-only template (ACME challenge phase)
│   └── generate-htpasswd.sh  # Generates basic auth credentials at startup
├── certbot/
│   ├── conf/                 # Let's Encrypt certs and config (mounted read-only by nginx)
│   └── www/                  # ACME challenge webroot
└── prometheus/
    └── prometheus.yml        # Prometheus scrape config
```
