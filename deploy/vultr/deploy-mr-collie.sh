#!/bin/sh
set -eu
rm -rf /tmp/prismo-deploy /tmp/prismo-deploy.tar.gz
mkdir -p /tmp/prismo-deploy
curl -fL https://api.github.com/repos/Conor-711/Prismo/tarball/deploy/mr-collie-20260813 -o /tmp/prismo-deploy.tar.gz
tar -xzf /tmp/prismo-deploy.tar.gz -C /tmp/prismo-deploy --strip-components=1
cp -a /tmp/prismo-deploy/services/client_api/. /opt/prismo/services/client_api/
cp -a /tmp/prismo-deploy/contracts/. /opt/prismo/contracts/
cp -a /tmp/prismo-deploy/deploy/vultr/docker-compose.yml /opt/prismo/deploy/vultr/docker-compose.yml
cp -a /tmp/prismo-deploy/deploy/vultr/Caddyfile /opt/prismo/deploy/vultr/Caddyfile
cp -a /tmp/prismo-deploy/deploy/vultr/.env.production.example /opt/prismo/deploy/vultr/.env.production.example
cd /opt/prismo/deploy/vultr
docker compose build client-api
docker compose up -d --no-deps client-api
docker compose ps client-api
