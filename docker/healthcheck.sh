#!/bin/sh
# /healthz is behind basic auth; 200 = healthy, 503 = no agent data.
code=$(curl -s -o /dev/null -w '%{http_code}' -u "${WEBUI_USERNAME}:${WEBUI_PASSWORD}" "http://127.0.0.1:${WEBUI_PORT:-7340}/healthz")
[ "$code" = "200" ]
