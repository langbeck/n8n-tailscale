#!/bin/sh
set -e

echo "========================================================"
echo "       n8n + Tailscale Sidecar Deployment Setup         "
echo "========================================================"
echo ""

# 1. Verify Prerequisites
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Error: Docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "❌ Error: Docker Compose is not installed or not responding."
    exit 1
fi

echo "Prerequisites met. Please provide your Tailscale configuration."
echo ""

# 2. Collect Mandatory Variables (Reading from /dev/tty allows curl | sh)
TS_AUTH_KEY=""
while [ -z "$TS_AUTH_KEY" ]; do
    printf "Tailscale Auth Key (tskey-auth-...): "
    read -r TS_AUTH_KEY < /dev/tty
done

TS_DNS_NAME=""
while [ -z "$TS_DNS_NAME" ]; do
    printf "Tailscale DNS Name (e.g., your-tailnet.ts.net): "
    read -r TS_DNS_NAME < /dev/tty
done

# 3. Generate Random Webhook Prefixes
# Generates a 10-character random alphanumeric string safely
RAND_STR=$(LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 10)
export N8N_ENDPOINT_WEBHOOK="wh-${RAND_STR}-prod"
export N8N_ENDPOINT_WEBHOOK_TEST="wh-${RAND_STR}-test"

echo ""
echo "🔐 Generated Unique Webhook Paths:"
echo "   Production: /${N8N_ENDPOINT_WEBHOOK}/"
echo "   Test:       /${N8N_ENDPOINT_WEBHOOK_TEST}/"
echo ""
echo "🚀 Starting containers directly from GitHub..."

# 4. Export variables and launch
export TAILSCALE_AUTH_KEY="$TS_AUTH_KEY"
export TAILSCALE_DNS_NAME="$TS_DNS_NAME"

docker compose -f https://github.com/langbeck/n8n-tailscale.git up -d

echo ""
echo "⏳ Waiting for Tailscale to authenticate and apply routing rules..."
docker compose -p n8n-tailscale exec -T tailscale tailscale wait

echo ""
echo "========================================================"
echo "✅ Deployment successfully initialized!"
echo "========================================================"
echo ""
echo "Current Tailscale Routing Status:"
docker compose -p n8n-tailscale exec -T tailscale tailscale serve status
