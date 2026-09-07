#!/usr/bin/env bash
# Check the LiteLLM/Tailscale network path and upstream provider connectivity.

set -uo pipefail

TAILSCALE_CONTAINER=${TAILSCALE_CONTAINER:-litellm_tailscale_1}
LITELLM_CONTAINER=${LITELLM_CONTAINER:-litellm_litellm_1}

failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

printf '%s\n' "Checking containers: $TAILSCALE_CONTAINER, $LITELLM_CONTAINER"

if podman container exists "$TAILSCALE_CONTAINER" 2>/dev/null &&
    [[ "$(podman inspect --format '{{.State.Status}}' "$TAILSCALE_CONTAINER" 2>/dev/null)" == running ]]; then
    pass "Tailscale container is running"
else
    fail "Tailscale container is not running"
fi

if podman container exists "$LITELLM_CONTAINER" 2>/dev/null &&
    [[ "$(podman inspect --format '{{.State.Status}}' "$LITELLM_CONTAINER" 2>/dev/null)" == running ]]; then
    pass "LiteLLM container is running"
else
    fail "LiteLLM container is not running"
fi

status=$(podman exec "$TAILSCALE_CONTAINER" tailscale status --json 2>/dev/null || true)
if grep -q '"BackendState": "Running"' <<<"$status" &&
    grep -q '"Online": true' <<<"$status" &&
    grep -q '"Health": \[\]' <<<"$status"; then
    pass "Tailscale is running, online, and reports no health errors"
else
    fail "Tailscale is not fully healthy"
    printf '%s\n' "$status" | grep -E 'BackendState|Online|Health' >&2 || true
fi

printf '%s\n' '--- resolver configuration ---'
podman exec "$LITELLM_CONTAINER" cat /etc/resolv.conf 2>/dev/null || {
    fail "Could not read LiteLLM resolver configuration"
}

printf '%s\n' '--- DNS and HTTPS checks ---'
if podman exec "$LITELLM_CONTAINER" python -u -c '
import socket
import sys
import urllib.error
import urllib.request

checks = {
    "api.openai.com": "https://api.openai.com/v1/models",
    "oauth2.googleapis.com": "https://oauth2.googleapis.com/token",
}
failed = False

for host, url in checks.items():
    try:
        addresses = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
        print(f"PASS: DNS resolves {host}: {addresses}")
    except Exception as exc:
        print(f"FAIL: DNS lookup for {host}: {exc}")
        failed = True
        continue

    try:
        response = urllib.request.urlopen(url, timeout=8)
        print(f"PASS: HTTPS reaches {host}: HTTP {response.status}")
    except urllib.error.HTTPError as exc:
        # 401/403/405/etc. proves the remote HTTPS endpoint was reached.
        print(f"PASS: HTTPS reaches {host}: HTTP {exc.code}")
    except Exception as exc:
        print(f"FAIL: HTTPS connection to {host}: {exc}")
        failed = True

sys.exit(1 if failed else 0)
'; then
    pass "Upstream DNS and HTTPS checks passed"
else
    fail "One or more upstream DNS/HTTPS checks failed"
fi

if (( failures > 0 )); then
    printf 'Network checks failed: %d check(s)\n' "$failures" >&2
    exit 1
fi

printf '%s\n' 'All network checks passed.'
