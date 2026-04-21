docker-compose up -d --force-recreate

docker exec pg-replica1 psql -U postgres -d appdb -t -c "SELECT state, query, count(*) FROM pg_stat_activity WHERE application_name = 'psql' group by state, query;"

docker exec pg-replica1 psql -U postgres -d appdb -t -c "SELECT calls, total_exec_time, mean_exec_time, rows, query FROM pg_stat_statements ORDER BY mean_exec_time DESC;"

docker exec pg-primary psql -U postgres -d appdb -c "\dx" 

curl http://localhost:3000/api/db_info

docker compose exec rails-app getent hosts pg-replicas

docker run --rm --network distribute_reads_poc_default alpine sh -c "apk add --no-cache bind-tools >/dev/null && dig pg-replicas +short"

docker compose exec rails-app bin/rails runner 'ActiveRecord::Base.clear_all_connections!; puts :cleared'

