#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   LOKI_URL, LOKI_USER, LOKI_TOKEN (basic auth)
#   STREAM_LABELS (JSON) e.g. {"job":"calculator-tests","repo":"jmiguelcheq/calculator-test-demo-jenkins"}
#   LOG_MESSAGE   (string)
#
# Optional:
#   EXTRA_FIELDS (JSON) merged into log line as key=value pairs

ts_ns() { date +%s%N; }

json_escape() {
  # escape for JSON string
  python3 - <<'PY'
import json, sys
print(json.dumps(sys.stdin.read()))
PY
}

main() {
  local ts="$(ts_ns)"
  local msg="$(echo -n "${LOG_MESSAGE:-}" | json_escape)"
  local labels="${STREAM_LABELS:-{}}"
  local extras="${EXTRA_FIELDS:-{}}"

  # Format key=value extras right inside the log line
  # Turn {"a":1,"b":"x"} -> a=1 b="x"
  local kv=$(python3 - <<PY
import json,sys
d=json.loads(sys.argv[1]) if sys.argv[1] else {}
def fmt(v):
  return str(v) if isinstance(v,(int,float)) else '"%s"'%str(v).replace('"','\\"')
print(" ".join([f"{k}="+fmt(v) for k,v in d.items()]))
PY
"${extras}")
  )

  local line=$(python3 - <<PY
import json,sys
labels=json.loads(sys.argv[1])
print(json.dumps(labels))
PY
"${labels}")

  cat > /tmp/loki-payload.json <<EOF
{
  "streams": [
    {
      "stream": ${line},
      "values": [
        [ "${ts}", $(echo -n "${kv} " ; echo -n "msg=" ; echo -n "${msg}") ]
      ]
    }
  ]
}
EOF

  curl -sSf -u "${LOKI_USER}:${LOKI_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST "${LOKI_URL}" \
    --data-binary @/tmp/loki-payload.json

  echo "✅ Pushed to Loki"
}

main "$@"
