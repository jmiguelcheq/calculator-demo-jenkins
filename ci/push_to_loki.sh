#!/usr/bin/env sh
# Minimal, POSIX-safe Loki pusher. Requires: jq, curl.
# Inputs:
#   LOKI_URL, LOKI_USER, LOKI_TOKEN
#   STREAM_LABELS  (JSON object, e.g. {"job":"calculator-tests","branch":"main"})
#   LOG_MESSAGE    (string)
#   EXTRA_FIELDS   (JSON object, optional; merged into the log line JSON)

set -eu

# ns timestamp (Linux busybox and GNU date both support %N on Jenkins agents)
ts_ns="$(date +%s%N)"

# Defaults
: "${STREAM_LABELS:={}}"
: "${EXTRA_FIELDS:={}}"
: "${LOG_MESSAGE:=}"

# Compose Loki payload.
# We send the log line as a JSON string so you can parse it with `| json` or `| logfmt` in Grafana.
payload="$(jq -cn \
  --arg ts "$ts_ns" \
  --argjson labels "$STREAM_LABELS" \
  --arg msg "$LOG_MESSAGE" \
  --argjson extras "$EXTRA_FIELDS" '
  {
    streams: [
      {
        stream: $labels,
        values: [
          [ $ts, ( $extras + {msg: $msg} | @json ) ]
        ]
      }
    ]
  }')"

curl -sSf -u "${LOKI_USER}:${LOKI_TOKEN}" \
  -H "Content-Type: application/json" \
  -X POST "${LOKI_URL}" \
  --data-binary "${payload}"

echo "✅ Pushed to Loki"
