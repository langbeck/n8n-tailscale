# n8n + Tailscale Sidecar Deployment

A production-grade Docker Compose setup that pairs **n8n** with a **Tailscale** container sidecar using shared network namespaces (`network_mode`). 

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
* **Self-Healing / Single-File:** An inline initialization script defined directly inside `docker-compose.yaml` configures Tailscale Serve and Funnel rules automatically on container startup using Docker Compose `configs` and `post_start` hooks.

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
| `N8N_SANDBOX_VERSION` | Docker tag for the sandbox overlay images (`sandbox` companion only) | No | `latest` |

## 📍 Endpoint Access Summary

Once the stack is up and Tailscale finishes initialization (approx. 5 seconds):

* **Admin UI (Private):**  
  `http://n8n-automation-node` *(Accessible only when connected to your Tailnet)*

* **Production Webhook (Public):**  
  `https://n8n-automation-node.your-tailnet.ts.net/prod-secret-path/<webhook-id>`

* **Test Webhook (Public):**  
  `https://n8n-automation-node.your-tailnet.ts.net/test-secret-path/<webhook-id>`

## 🧪 Optional: AI Sandbox (Code Execution Companion)

`docker-compose.sandbox.yaml` is an additive overlay that enables n8n's **Instance AI** code-execution sandbox. It layers the official sandbox service alongside the base stack, so n8n can run generated code in a disposable, isolated container instead of in-process.

The overlay defines four services and extends the base `n8n` service:

| Service | Image | Purpose |
| :--- | :--- | :--- |
| `sandbox-keygen` | `alpine` | One-shot. Generates the shared API keys and runner registration token into the `sandbox-keys` volume. Idempotent — skips if keys already exist. |
| `sandbox-certs` | `n8n-sandbox-service-api` | One-shot. Bootstraps the mutual-TLS CA and certificate chain into the `sandbox-tls` volume. |
| `sandbox-api` | `n8n-sandbox-service-api` | The sandbox control plane (HTTP `:8080`, gRPC `:9090`). |
| `sandbox-runner-1` | `n8n-sandbox-service-runner-dind` | Privileged Docker-in-Docker runner that actually spawns sandbox containers. |

It also adds `N8N_INSTANCE_AI_SANDBOX_ENABLED`, `N8N_INSTANCE_AI_SANDBOX_PROVIDER`, `N8N_SANDBOX_SERVICE_URL`, and the `sandbox-keys` volume to the base `n8n` service. The overlay is fully additive: the base `network_mode: service:tailscale` and all Tailscale Funnel routing are unchanged, and the sandbox services stay on the internal Compose network (no host ports, not reachable from the Tailnet or the internet).

### Launch with the sandbox

    docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml up -d

### Activation is required after first boot

Setting `N8N_INSTANCE_AI_SANDBOX_ENABLED=true` in the environment is **not** by itself enough to turn the sandbox on. n8n persists sandbox state in its database, and the persisted value takes precedence over the environment on every subsequent start — n8n logs this explicitly:

    Sandbox: enabled=false provider=n8n-sandbox (DB override; env was enabled=true provider=n8n-sandbox)

`(DB override; ...)` means n8n started from a stored value instead of your env vars. To activate the sandbox, in the n8n UI open the **Instance AI** setup panel and enable/complete the sandbox step. That runs a live sandbox test and saves the setting (`sandboxEnabled`, plus a `setupCompletedAt` marker) to the database. After that, startup logs report the sandbox as enabled and no longer print the `DB override` note.

From then on the database is the source of truth, so changing `N8N_INSTANCE_AI_SANDBOX_ENABLED` in `.env` will not flip the sandbox back off — use the UI setting instead.

### Sandbox volumes

* `sandbox-keys` — generated API keys and runner registration token (shared by `n8n`, `sandbox-api`, `sandbox-runner-1`).
* `sandbox-tls` — mTLS CA and service certificates.

Both persist across restarts and are regenerated only if removed. To force fresh keys and certificates, delete the volumes and bring the stack up again:

    docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml down
    docker volume rm n8n-tailscale_sandbox-keys n8n-tailscale_sandbox-tls
    docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml up -d

### Sandbox requirements

`sandbox-runner-1` uses `privileged: true` for Docker-in-Docker. This is inherent to the official runner image (it launches nested sandbox containers), and it is why the overlay is opt-in rather than part of the base stack. The runner is the most privileged component in the deployment, so review that trade-off before enabling it on a shared host.

## 🛠️ Verification & Troubleshooting

### Check Tailscale Routing Rules
To verify that Tailscale correctly configured the background Funnel and Serve proxies:

    docker compose exec tailscale tailscale serve status

### Inspect Container Logs

    docker compose logs -f tailscale

### Verify the Sandbox Overlay

Check that the API is healthy and that the runner registered successfully:

    docker compose -f docker-compose.yaml -f docker-compose.sandbox.yaml logs -f sandbox-api sandbox-runner-1

In the `sandbox-api` logs, a healthy setup shows `api listening` followed by `runner registered`. If the runner never registers, the mTLS certificates are usually the cause — re-check that `sandbox-certs` completed successfully and regenerate the `sandbox-tls` volume if needed.

If the sandbox still appears disabled in the UI, confirm n8n's startup line no longer contains `(DB override; ...)`; see [Activation is required after first boot](#activation-is-required-after-first-boot).