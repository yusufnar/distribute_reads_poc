#!/usr/bin/env bash

set -euo pipefail

URL="${URL:-http://localhost:3000/api/db_info}"
REQUESTS="${REQUESTS:-100}"
CONCURRENCY="${CONCURRENCY:-5}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-5}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-1}"

usage() {
  cat <<'EOF'
Usage: ./measure_latency.sh [options]

Options:
  -u, --url URL                Endpoint URL (default: http://localhost:3000/api/db_info)
  -r, --requests N             Requests per summary window (default: 100)
  -c, --concurrency N          Parallel request count (default: 20)
  -t, --timeout-seconds N      Per-request timeout seconds (default: 5)
  -i, --interval-seconds N     Summary interval seconds (default: 10)
  -h, --help                   Show this help

You can also set env vars:
  URL, REQUESTS, CONCURRENCY, TIMEOUT_SECONDS, INTERVAL_SECONDS
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url) URL="$2"; shift 2 ;;
    -r|--requests) REQUESTS="$2"; shift 2 ;;
    -c|--concurrency) CONCURRENCY="$2"; shift 2 ;;
    -t|--timeout-seconds) TIMEOUT_SECONDS="$2"; shift 2 ;;
    -i|--interval-seconds) INTERVAL_SECONDS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

echo "Continuous latency monitor started"
echo "  url=$URL"
echo "  requests/window=$REQUESTS"
echo "  concurrency/window=$CONCURRENCY"
echo "  timeout=${TIMEOUT_SECONDS}s"
echo "  summary_interval=${INTERVAL_SECONDS}s"
printf "%-19s %8s %8s %8s %10s %10s %10s %10s %10s\n" \
  "timestamp" "success" "timeout" "total" "min_ms" "avg_ms" "p50_ms" "p95_ms" "max_ms"

while true; do
  window_start="$(date +%s)"
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  tmp_file="$(mktemp)"
  sorted_file="$(mktemp)"

  seq 1 "$REQUESTS" | xargs -I{} -P"$CONCURRENCY" sh -c \
    "curl -sS -o /dev/null --max-time \"$TIMEOUT_SECONDS\" -w '%{time_total}\n' \"$URL\" || echo timeout" \
    > "$tmp_file"

  total_count="$(wc -l < "$tmp_file" | tr -d ' ')"
  success_count="$(awk '$1 != "timeout" {c++} END {print c+0}' "$tmp_file")"
  timeout_count=$(( total_count - success_count ))

  if [ "$success_count" -eq 0 ]; then
    printf "%-19s %8d %8d %8d %10s %10s %10s %10s %10s\n" \
      "$timestamp" 0 "$timeout_count" "$total_count" "-" "-" "-" "-" "-"
    rm -f "$tmp_file" "$sorted_file"
  else
    awk '$1 != "timeout" {printf "%.6f\n", $1 * 1000.0}' "$tmp_file" | sort -n > "$sorted_file"

    p50_idx=$(( (success_count * 50 + 99) / 100 ))
    p95_idx=$(( (success_count * 95 + 99) / 100 ))
    min_ms="$(awk 'NR==1 {print $1}' "$sorted_file")"
    max_ms="$(awk 'END {print $1}' "$sorted_file")"
    p50_ms="$(awk -v idx="$p50_idx" 'NR==idx {print $1}' "$sorted_file")"
    p95_ms="$(awk -v idx="$p95_idx" 'NR==idx {print $1}' "$sorted_file")"
    avg_ms="$(awk '{sum+=$1} END {if (NR>0) printf "%.6f", sum/NR; else print "0"}' "$sorted_file")"

    printf "%-19s %8d %8d %8d %10.2f %10.2f %10.2f %10.2f %10.2f\n" \
      "$timestamp" "$success_count" "$timeout_count" "$total_count" \
      "$min_ms" "$avg_ms" "$p50_ms" "$p95_ms" "$max_ms"
    rm -f "$tmp_file" "$sorted_file"
  fi

  elapsed=$(( $(date +%s) - window_start ))
  if [ "$elapsed" -lt "$INTERVAL_SECONDS" ]; then
    sleep $(( INTERVAL_SECONDS - elapsed ))
  fi
done
