#!/bin/bash

# Long Query Monitor Script
# Sends GET /api/sleep_query every 10 seconds to test in-flight query behavior
# using the Rails API endpoint.

RAILS_HOST=localhost
RAILS_PORT=3000
ENDPOINT="http://${RAILS_HOST}:${RAILS_PORT}/api/sleep_query"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          LONG QUERY (SLEEP) MONITOR                         ║"
echo "║     Sends GET /api/sleep_query (sleeps for 20s)             ║"
echo "║     Press Ctrl+C to stop                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

while true; do
    timestamp=$(date +%H:%M:%S)
    
    echo "[$timestamp] Sending 4 concurrent sleep_query requests..."
    
    for i in {1..4}; do
        (
            response=$(curl -s --max-time 25 "$ENDPOINT" 2>/dev/null)
            
            if [ -z "$response" ]; then
                echo "    [$timestamp Q$i Result] ERROR: No response or timeout"
            else
                node=$(echo "$response" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)
                if [ -n "$node" ]; then
                    echo "    [$timestamp Q$i Result] Executed on node: $node"
                else
                    echo "    [$timestamp Q$i Result] ERROR: Parsing failed -> $response"
                fi
            fi
        ) &
    done
    
    echo "Waiting for all 4 queries to finish..."
    wait
    
done
