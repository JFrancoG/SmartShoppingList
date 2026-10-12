#!/usr/bin/env bash
# Exercise the final Linux image with disposable Apple credentials and PostgreSQL.
# A successful /hello requires the IAP root, identity signing key and token vault to load.
set -euo pipefail

image="${1:?Usage: bash scripts/check_server_image.sh IMAGE}"
prefix="smartshoppinglist-image-$(openssl rand -hex 6)"
network="$prefix"
database="$prefix-db"
server="$prefix-server"
postgres_image="postgres:18.6-alpine3.24@sha256:6c538e7206ea40ff740ef27883529390a690b6ead6ba96b44c67a9f7c638e8fd"

cleanup() {
    docker rm -fv "$server" "$database" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create --internal "$network" >/dev/null
docker run --detach --name "$database" --network "$network" \
    --env POSTGRES_USER=image_smoke --env POSTGRES_PASSWORD=image_smoke \
    --env POSTGRES_DB=image_smoke "$postgres_image" >/dev/null

database_ready=false
for _ in {1..30}; do
    if docker exec "$database" pg_isready -h 127.0.0.1 -U image_smoke -d image_smoke >/dev/null 2>&1; then
        database_ready=true
        break
    fi
    sleep 1
done
if [[ "$database_ready" != true ]]; then
    docker logs "$database" >&2
    exit 1
fi

# Generate a new disposable PKCS#8 key. Never read a developer's real .p8 or call Apple.
private_key="$(openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 2>/dev/null)"
refresh_key="$(openssl rand -base64 32)"
refresh_keys_json="$(printf '{"v1":"%s"}' "$refresh_key")"
docker run --detach --name "$server" --network "$network" \
    --env DATABASE_HOST="$database" --env DATABASE_PORT=5432 \
    --env DATABASE_USERNAME=image_smoke --env DATABASE_PASSWORD=image_smoke \
    --env DATABASE_NAME=image_smoke \
    --env APPLE_CLIENT_ID=com.plusprojects.SmartShoppingList \
    --env APPLE_TEAM_ID=SMOKETEST1 --env APPLE_KEY_ID=SMOKETEST1 \
    --env APPLE_PRIVATE_KEY_PEM="$private_key" \
    --env APPLE_REFRESH_ACTIVE_KEY_VERSION=v1 \
    --env APPLE_REFRESH_KEYS_JSON="$refresh_keys_json" \
    --env APP_STORE_BUNDLE_ID=com.plusprojects.SmartShoppingList \
    --env APP_STORE_APP_ID=1 \
    --env APP_STORE_ISSUER_ID=00000000-0000-4000-8000-000000000001 \
    --env APP_STORE_KEY_ID=SMOKETEST1 \
    --env APP_STORE_PRIVATE_KEY_PEM="$private_key" \
    --env APP_STORE_PREMIUM_MONTHLY_PRODUCT_ID=com.plusprojects.SmartShoppingList.premium.monthly \
    --env APP_STORE_PREMIUM_ANNUAL_PRODUCT_ID=com.plusprojects.SmartShoppingList.premium.annual \
    --env APP_STORE_SUBSCRIPTION_GROUP_ID=1 --env APP_STORE_ENVIRONMENT=Sandbox \
    "$image" serve --env sandbox --hostname 0.0.0.0 --port 8080 >/dev/null
unset private_key refresh_key refresh_keys_json

server_ready=false
for _ in {1..60}; do
    if [[ "$(docker inspect --format '{{.State.Running}}' "$server")" != true ]]; then
        break
    fi
    if [[ "$(docker inspect --format '{{.State.Health.Status}}' "$server")" == healthy ]]; then
        server_ready=true
        break
    fi
    sleep 1
done
if [[ "$server_ready" != true ]]; then
    docker logs "$server" >&2
    exit 1
fi

hello="$(docker exec "$server" curl --fail --silent --show-error \
    --connect-timeout 2 --max-time 5 http://127.0.0.1:8080/hello)"
if [[ "$hello" != 'Hello, world!' ]]; then
    echo 'Unexpected /hello response.' >&2
    exit 1
fi
for route in /v1/me /v1/account/subscription; do
    status="$(docker exec "$server" curl --silent --show-error --output /dev/null \
        --connect-timeout 2 --max-time 5 --write-out '%{http_code}' "http://127.0.0.1:8080$route")"
    if [[ "$status" != 401 ]]; then
        echo "Expected 401 for $route; got $status." >&2
        exit 1
    fi
done
for method in GET POST; do
    status="$(docker exec "$server" curl --silent --show-error --output /dev/null \
        --connect-timeout 2 --max-time 5 --request "$method" \
        --write-out '%{http_code}' http://127.0.0.1:8080/todos)"
    if [[ "$status" != 404 ]]; then
        echo "Expected 404 for $method /todos; got $status." >&2
        exit 1
    fi
done
echo 'PASS: Linux runtime image loads Apple resources, identity and vault, migrates PostgreSQL and serves health/auth boundaries.'
