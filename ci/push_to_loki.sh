#!/usr/bin/env sh
# Minimal, POSIX-safe Loki pusher. Requires: jq, curl.
# Inputs:
#   LOKI_URL, LOKI_USER, LOKI_TOKEN
#   STREAM_LABELS  (JSON object, e.g. {"job":"calculator-tests","branch":"main"})
#   LOG_MESSAGE    (string)
#   EXTRA_FIELDS   (JSON object, optional; merged into the log line JSON)

set -eu

# ns timestamp
ts_ns="$(date +%s%N)"

# Defaults
: "${STREAM_LABELS:={}}"
: "${EXTRA_FIELDS:={}}"
: "${LOG_MESSAGE:=}"

# Build Loki payload: labels in 'stream', and JSON log line as the entry text
# (We send a JSON string as the log line so you can parse with:  | json  in LogQL)
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
