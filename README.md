# n8n + Tailscale Sidecar Deployment

A production-grade, single-file Docker Compose setup that pairs **n8n** with a **Tailscale** container sidecar using shared network namespaces (`network_mode`). 

This architecture allows you to receive external webhooks (e.g., WhatsApp, Meta, GitHub) via **Tailscale Funnel** without opening router ports or using ngrok, while completely hiding the n8n administrative UI behind your private **Tailscale Tailnet**.

## 🏛️ Architecture & Security Model

    +-----------------------------------------------------------------+
    |                    Tailscale Sidecar Container                  |
    |                  (hostname: n8n-automation-node)                |
    |                                                                 |
    |   Public Webhooks      Port 443 (Funnel)                        |
    |   -------------------> /prod-secret-path/ --+                   |
    |   (WhatsApp/Meta)      /test-secret-path/ --+                   |
    |                                             |                   |
    |                                             v                   |
    |                                     Localhost:5678              |
    |                                      (n8n Process)              |
    |                                             ^                   |
    |   Private Tailnet      Port 80 (Serve)      |                   |
    |   -------------------> / (Root UI) ---------+                   |
    |   (Admin Canvas)       (MagicDNS)                               |
    +-----------------------------------------------------------------+

### Key Security Features

* **Zero Host Port Exposure:** n8n maps no ports directly to your host machine (`0.0.0.0`). It exists solely inside the Tailscale container's network namespace.
* **Public Webhook Isolation:** Tailscale Funnel exposes **only** your designated, obscured webhook paths (`/prod-secret-path/` and `/test-secret-path/`) over public HTTPS (port 443).
* **Attacker Defense (404 on Root):** Automated scanners or bots attempting to hit the root URL (`https://your-node.your-tailnet.ts.net/`) will receive a `404 Not Found` from Tailscale's edge. The login UI cannot be brute-forced over the internet.
* **Encrypted Management UI:** You access the admin canvas privately over your Tailnet using MagicDNS (`http://n8n-automation-node/`) over WireGuard-encrypted connections.
* **Self-Healing / Single-File:** An inline initialization script defined directly inside `docker-compose.yml` configures Tailscale Serve and Funnel rules automatically on container startup using Docker Compose `configs` and `post_start` hooks.

## 🚀 Quick Start

### Method 1: The One-Line Remote Installer (Recommended)

'Run the automated interactive installer directly from your terminal. It will prompt for your credentials, deploy directly from GitHub into Docker, and wait for network routes to finalize:

    curl -sSL https://raw.githubusercontent.com/langbeck/n8n-tailscale/main/install.sh | sh

### Method 2: Local Clone

1. Clone the repository:

    git clone https://github.com/langbeck/n8n-tailscale.git
    cd n8n-tailscale

2. Create your `.env` file:

    cp .env.example .env

3. Configure required variables in `.env`:

    TAILSCALE_AUTH_KEY=tskey-auth-XXXXXXXXXXXXXXXXXXXX
    TAILSCALE_DNS_NAME=your-tailnet.ts.net

4. Launch the stack:

    docker compose up -d

## ⚙️ Environment Variables Reference

All configurable options are documented below. Mandatory variables use strict guardrails (`:?`) and will halt deployment if missing.

| Variable | Description | Required | Default Value |
| :--- | :--- | :--- | :--- |
| `TAILSCALE_AUTH_KEY` | Tailscale auth key (`tskey-auth-...`) | **Yes** | *None (Build fails if missing)* |
| `TAILSCALE_DNS_NAME` | Tailscale root domain (`your-tailnet.ts.net`) | **Yes** | *None (Build fails if missing)* |
| `TAILSCALE_HOSTNAME` | Device name as shown in Tailscale Admin | No | `n8n-automation-node` |
| `TAILSCALE_VERSION` | Docker tag for `tailscale/tailscale` | No | `latest` |
| `N8N_VERSION` | Docker tag for `docker.n8n.io/n8nio/n8n` | No | `latest` |
| `N8N_ENDPOINT_WEBHOOK` | Custom obscured prefix for production webhooks | No | `prod-secret-path` |
| `N8N_ENDPOINT_WEBHOOK_TEST` | Custom obscured prefix for test webhooks | No | `test-secret-path` |

## 📍 Endpoint Access Summary

Once the stack is up and Tailscale finishes initialization (approx. 5 seconds):

* **Admin UI (Private):**  
  `http://n8n-automation-node` *(Accessible only when connected to your Tailnet)*

* **Production Webhook (Public):**  
  `https://n8n-automation-node.your-tailnet.ts.net/prod-secret-path/<webhook-id>`

* **Test Webhook (Public):**  
  `https://n8n-automation-node.your-tailnet.ts.net/test-secret-path/<webhook-id>`

## 🛠️ Verification & Troubleshooting

### Check Tailscale Routing Rules
To verify that Tailscale correctly configured the background Funnel and Serve proxies:

    docker compose exec tailscale tailscale serve status

### Inspect Container Logs

    docker compose logs -f tailscale