#!/bin/bash

set -euo pipefail

DOMAIN=${1:-}
EMAIL=${2:-}

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Usage: $0 <domain> <email>"
  exit 1
fi

# Basic domain validation (letters, numbers, dashes, dots)
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "Invalid domain name: $DOMAIN"
  exit 1
fi

# Basic email validation
if ! [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
  echo "Invalid email address: $EMAIL"
  exit 1
fi

# Step 1: Use HTTP-only config
if [[ ! -f ./nginx/default.http.conf ]]; then
  echo "Missing ./nginx/default.http.conf"
  exit 1
fi
cp ./nginx/default.http.conf ./nginx/default.conf
docker compose up -d nginx

# Step 2: Run Certbot
docker compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot --email "$EMAIL" --agree-tos --no-eff-email -d "$DOMAIN"

# Step 3: Use HTTPS config
if [[ ! -f ./nginx/default.https.conf ]]; then
  echo "Missing ./nginx/default.https.conf"
  exit 1
fi
cp ./nginx/default.https.conf ./nginx/default.conf
docker compose restart nginx

echo "SSL setup complete for $DOMAIN"