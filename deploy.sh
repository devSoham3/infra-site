#!/bin/bash

set -euo pipefail

DOMAIN=$1

if [[ -z "${DOMAIN:-}" ]]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

# Basic domain validation (letters, numbers, dashes, dots)
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "Invalid domain name: $DOMAIN"
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
docker compose run --rm certbot

# Step 3: Use HTTPS config
if [[ ! -f ./nginx/default.https.conf ]]; then
  echo "Missing ./nginx/default.https.conf"
  exit 1
fi
cp ./nginx/default.https.conf ./nginx/default.conf
docker compose restart nginx

echo "SSL setup complete for $DOMAIN"