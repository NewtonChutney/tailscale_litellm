#!/bin/sh
. ./.env
TS_PID="$(podman inspect litellm_tailscale_1 --format '{{.State.Pid}}')"
podman run --rm \
    --network "ns:/proc/$TS_PID/ns/net" \
    --dns 100.100.100.100 \
    docker.io/curlimages/curl:latest \
    -s \
    -H "Authorization: Bearer $MACBOOK_PRO_LMSTUDIO_KEY" \
    http://nitins-macbook-pro:1234/api/v1/models
