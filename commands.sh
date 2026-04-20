curl http://localhost:3000/api/db_info

docker compose exec rails-app getent hosts pg-replicas

docker run --rm --network distribute_reads_poc_default alpine sh -c "apk add --no-cache bind-tools >/dev/null && dig pg-replicas +short"

