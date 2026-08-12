#!/usr/bin/env bash
set -euo pipefail

if [[ "${BSMART_ENV:-}" != "internal-alpha" ]]; then
  echo "The Alpha image must run with BSMART_ENV=internal-alpha." >&2
  exit 2
fi

if [[ "${BSMART_READ_MODEL_MODE:-}" != "database" ]]; then
  echo "The Alpha image requires BSMART_READ_MODEL_MODE=database." >&2
  exit 2
fi

python -m services.client_api.materialize_fixtures

exec python -m uvicorn services.client_api.main:create_app \
  --factory \
  --host 0.0.0.0 \
  --port "${PORT:-8080}" \
  --proxy-headers \
  --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-*}"
