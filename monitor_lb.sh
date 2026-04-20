#!/bin/bash

# Load Balancing Monitor Script
# Sends CONCURRENT requests to force Rails to open new connections
# so Docker's DNS round-robin distributes traffic across both replicas.

RAILS_HOST=localhost
RAILS_PORT=3000
ENDPOINT="http://${RAILS_HOST}:${RAILS_PORT}/api/db_info"
CONCURRENT=10   # Number of parallel requests per round (> pool size to force new connections)
TMPDIR_PREFIX="/tmp/monitor_lb_$$"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       DISTRIBUTE_READS LOAD BALANCING MONITOR               ║${NC}"
echo -e "${BOLD}║  Concurrent requests to force DNS round-robin distribution  ║${NC}"
echo -e "${BOLD}║     Press Ctrl+C to stop                                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Show current container IPs for reference
echo "Current Nodes:"
docker ps --format "{{.Names}}" | grep -E "^pg-" | while read name; do
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null)
    echo "  $name -> $ip"
done
echo ""
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Sending ${CONCURRENT} concurrent requests per round..."
echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get node name from IP
get_node() {
    local ip=$1
    local found=""
    while IFS= read -r name; do
        node_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name" 2>/dev/null)
        if [ "$node_ip" = "$ip" ]; then
            found="$name"
            break
        fi
    done < <(docker ps --format "{{.Names}}" | grep -E "^pg-")
    echo "${found:-$ip}"
}

# Cleanup handler
cleanup() {
    rm -f "${TMPDIR_PREFIX}_"* 2>/dev/null
    echo ""
    echo -e "${BOLD}Stopped.${NC}"
    exit 0
}
trap cleanup INT TERM

replica1_total=0
replica2_total=0
primary_total=0
error_total=0
round=0

while true; do
    round=$((round + 1))
    timestamp=$(date +%H:%M:%S)

    # Send CONCURRENT requests in parallel, save each to a temp file
    pids=()
    tmpfiles=()
    for i in $(seq 1 $CONCURRENT); do
        tmpfile="${TMPDIR_PREFIX}_${i}"
        tmpfiles+=("$tmpfile")
        curl -s --max-time 3 "$ENDPOINT" > "$tmpfile" 2>/dev/null &
        pids+=($!)
    done

    # Wait for all requests to finish
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    replica1_count=0
    replica2_count=0
    primary_count=0
    error_count=0
    round_results=""

    # Process results
    for tmpfile in "${tmpfiles[@]}"; do
        response=$(cat "$tmpfile" 2>/dev/null)
        rm -f "$tmpfile"

        if [ -z "$response" ] || echo "$response" | grep -q '"error"'; then
            error_count=$((error_count + 1))
            round_results="${round_results}${RED}ERR${NC} "
            continue
        fi

        server_ip=$(echo "$response"  | grep -o '"server_ip":"[^"]*"'   | cut -d'"' -f4)
        is_replica=$(echo "$response" | grep -o '"is_replica":[^,}]*'   | cut -d':' -f2 | tr -d ' ')
        lag=$(echo "$response"        | grep -o '"replication_lag_seconds":[^,}]*' | cut -d':' -f2 | tr -d ' ')
        connected=$(echo "$response"  | grep -o '"connected_to":"[^"]*"' | cut -d'"' -f4)

        node=$(get_node "$server_ip")
        short=$(echo "$node" | sed 's/pg-//')

        if [ "$is_replica" = "true" ]; then
            case "$node" in
                *replica1*) replica1_count=$((replica1_count + 1)); round_results="${round_results}${GREEN}r1${NC} " ;;
                *replica2*) replica2_count=$((replica2_count + 1)); round_results="${round_results}${GREEN}r2${NC} " ;;
                *)          round_results="${round_results}${GREEN}rep${NC} " ;;
            esac
        else
            primary_count=$((primary_count + 1))
            round_results="${round_results}${YELLOW}pri${NC} "
        fi
    done

    # Update totals
    replica1_total=$((replica1_total + replica1_count))
    replica2_total=$((replica2_total + replica2_count))
    primary_total=$((primary_total + primary_count))
    error_total=$((error_total + error_count))
    total=$((replica1_total + replica2_total + primary_total + error_total))

    # Print round summary
    printf "${BOLD}[${timestamp}] #${round}${NC}  ${round_results}  ${GREEN}r1:${replica1_count}${NC} ${GREEN}r2:${replica2_count}${NC} ${YELLOW}pri:${primary_count}${NC} ${RED}err:${error_count}${NC}\n"

    sleep 1
done
