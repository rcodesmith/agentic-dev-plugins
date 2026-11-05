#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# ---------------------------------------------------------------------------
# CUSTOMIZE HERE: add your project's own package-registry / toolchain domains.
# Examples (uncomment / add what your project actually needs):
#   "pypi.org" "files.pythonhosted.org" "astral.sh"   # Python / uv / pip
#   "crates.io" "index.crates.io" "static.crates.io" "sh.rustup.rs" # Rust / cargo
#   "proxy.golang.org" "sum.golang.org"               # Go
#   "rubygems.org"                                    # Ruby / bundler
#   "objects.githubusercontent.com" "release-assets.githubusercontent.com"
#                                                     # GitHub release-asset downloads
#   "media.githubusercontent.com"                     # Git LFS objects
# registry.npmjs.org is already covered below (Claude Code itself needs it).
#
# Entries are matched against the TLS SNI of each outbound HTTPS connection:
#   "example.com"   that exact name only (not www.example.com)
#   ".example.com"  example.com and every subdomain of it
# A name that doesn't resolve only produces a warning. A malformed entry fails closed.
# Only port 443 is proxied; an allowlisted host on any other port stays blocked.
EXTRA_DOMAINS=(
)
# ---------------------------------------------------------------------------

# The base set Claude Code itself needs, plus GitHub over HTTPS. Same matching rules.
# Anthropic's domains are wildcards because login, MCP connectors and version checks
# use several hosts (api.anthropic.com, platform.claude.com, mcp-proxy.anthropic.com,
# downloads.claude.ai, code.claude.com and others), and all but a few share one IP that
# the old IP allowlist let through. raw.githubusercontent.com: plugin marketplaces.
# .github.com: github.com, api. (gh), codeload. (tarballs), uploads., lfs., gist.
# The documentation block lets the agent read reference docs without the web-research
# toggle.
BASE_DOMAINS=(
    "registry.npmjs.org"
    ".anthropic.com"
    ".claude.ai"
    ".claude.com"
    "clau.de"
    ".github.com"
    "raw.githubusercontent.com"
    "sentry.io"
    "statsig.com"
    "marketplace.visualstudio.com"
    "vscode.blob.core.windows.net"
    "update.code.visualstudio.com"
    # Documentation
    "docs.aws.amazon.com"
    "aws.amazon.com"
    "developer.hashicorp.com"
    "zitadel.com"
    "caddyserver.com"
    "letsencrypt.org"
    "fastapi.tiangolo.com"
    "pnpm.io"
    "vite.dev"
    "react.dev"
    "developer.mozilla.org"
    "nodejs.org"
    "grafana.com"
)

# User and port of the SNI proxy (the user is created in the Dockerfile).
SNI_PROXY_USER="sniproxy"
SNI_PROXY_PORT=15443
SNI_PROXY_CONF="/etc/sniproxy/nginx.conf"
SNI_PROXY_RUN_DIR="/run/sniproxy"
SNI_PROXY_LOG_DIR="/var/log/sniproxy"

# Ignores zombies: PID 1 in these containers may never reap the old proxy.
proxy_running() {
    ps -u "$SNI_PROXY_USER" -o stat= 2>/dev/null | grep -qv '^Z'
}

stop_proxy() {
    pkill -TERM -u "$SNI_PROXY_USER" -x nginx 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        proxy_running || return 0
        sleep 0.2
    done
    pkill -KILL -u "$SNI_PROXY_USER" -x nginx 2>/dev/null || true
}

# Fail closed: if anything below aborts (set -e), remove every allow rule and the proxy,
# leaving loopback only. A DROP policy alone wouldn't do: allow rules outrank it.
fail_closed() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        set +e
        for ipt in iptables ip6tables; do
            "$ipt" -P INPUT DROP
            "$ipt" -P FORWARD DROP
            "$ipt" -P OUTPUT DROP
            "$ipt" -F
            "$ipt" -A INPUT -i lo -j ACCEPT
            "$ipt" -A OUTPUT -o lo -j ACCEPT
        done
        stop_proxy
        echo "ERROR: init-firewall.sh failed (exit $rc) — all egress blocked. Fix, then re-run." >&2
    fi
    exit "$rc"
}
trap fail_closed EXIT

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Stop any proxy from a previous run while its rules still stand, so clients get its
# close. Under the DROP below they'd never see it, and an idle read would hang forever.
stop_proxy

# Block first, so neither a fresh container nor a re-run is ever open while this runs.
# Nothing below needs egress except DNS and the final verification.
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Flush existing rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# 2. Selectively restore ONLY internal Docker DNS resolution
if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
# Allow outbound DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# Allow inbound DNS responses
iptables -A INPUT -p udp --sport 53 -j ACCEPT
# Allow outbound SSH
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# Allow inbound SSH responses
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
# Allow localhost
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# NOTE: unrestricted web (80/443) access is NOT baked in here — this script only runs
# once, at container start (postStartCommand), so it's not a convenient place for
# something meant to be toggled during a session. See web-research-toggle.sh for an
# on-demand `sudo web-research-toggle.sh on|off` switch instead.

# 3. Build the SNI allowlist and start the proxy.
# Validated because these names go straight into the nginx config.
ALLOWED_DOMAINS=$(printf '%s\n' "${BASE_DOMAINS[@]}" ${EXTRA_DOMAINS[@]+"${EXTRA_DOMAINS[@]}"} | sort -u)
while read -r domain; do
    if [[ ! "$domain" =~ ^\.?([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]]; then
        echo "ERROR: Invalid domain in allowlist (lowercase names only): '$domain'"
        exit 1
    fi
done <<< "$ALLOWED_DOMAINS"

# nginx's resolver is the container's DNS; IPv4 only, since IPv6 is blocked below.
RESOLVERS=$(awk '$1 == "nameserver" && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {print $2}' /etc/resolv.conf | paste -sd' ')
if [ -z "$RESOLVERS" ]; then
    echo "ERROR: No IPv4 nameserver in /etc/resolv.conf"
    exit 1
fi

mkdir -p "$(dirname "$SNI_PROXY_CONF")"
{
    cat <<CONF
# Generated by init-firewall.sh; edit the domain lists there instead.
load_module /usr/lib/nginx/modules/ngx_stream_module.so;
worker_processes 1;
worker_rlimit_nofile 8192;
pid $SNI_PROXY_RUN_DIR/nginx.pid;
error_log $SNI_PROXY_LOG_DIR/error.log warn;
events { worker_connections 4096; }
stream {
    log_format sni '\$time_iso8601 denied sni="\$ssl_preread_server_name"';
    map \$ssl_preread_server_name \$sni_allowed {
        hostnames;
        default 0;
CONF
    while read -r domain; do
        printf '        %s 1;\n' "$domain"
    done <<< "$ALLOWED_DOMAINS"
    cat <<CONF
    }
    map \$sni_allowed \$sni_upstream {
        1 \$ssl_preread_server_name:443;
        default unix:$SNI_PROXY_RUN_DIR/reject.sock;
    }
    map \$sni_allowed \$sni_denied {
        1 0;
        default 1;
    }
    server {
        listen 127.0.0.1:$SNI_PROXY_PORT;
        ssl_preread on;
        preread_timeout 10s;
        resolver $RESOLVERS ipv6=off valid=10s;
        resolver_timeout 5s;
        proxy_connect_timeout 10s;
        # Idle limit (default 10m). Claude Code holds long connections.
        proxy_timeout 24h;
        proxy_socket_keepalive on;
        proxy_pass \$sni_upstream;
        access_log $SNI_PROXY_LOG_DIR/denied.log sni if=\$sni_denied;
    }
    # Denied connections land here and are closed without a response.
    server {
        listen unix:$SNI_PROXY_RUN_DIR/reject.sock;
        return "";
        access_log off;
    }
}
CONF
} > "$SNI_PROXY_CONF"
chmod 644 "$SNI_PROXY_CONF"

rm -rf "$SNI_PROXY_RUN_DIR"
install -d -m 755 -o "$SNI_PROXY_USER" -g "$SNI_PROXY_USER" "$SNI_PROXY_RUN_DIR" "$SNI_PROXY_LOG_DIR"

run_as_proxy_user() {
    setpriv --reuid="$SNI_PROXY_USER" --regid="$SNI_PROXY_USER" --clear-groups \
        --no-new-privs --bounding-set=-all "$@"
}
echo "Starting SNI proxy on 127.0.0.1:$SNI_PROXY_PORT..."
run_as_proxy_user nginx -t -q -c "$SNI_PROXY_CONF" -e "$SNI_PROXY_LOG_DIR/error.log"
run_as_proxy_user nginx -c "$SNI_PROXY_CONF" -e "$SNI_PROXY_LOG_DIR/error.log"
if ! proxy_running; then
    echo "ERROR: SNI proxy exited right after starting; see $SNI_PROXY_LOG_DIR/error.log"
    exit 1
fi

# Report names that don't resolve now; they may resolve later, so this isn't fatal.
printf '%s\n' "$ALLOWED_DOMAINS" | sed 's/^\.//' | xargs -P 16 -I{} sh -c \
    'dig +short +time=2 +tries=1 A "{}" | grep -q . || echo "WARNING: {} does not resolve right now" >&2' || true

# Get host IP from default route
HOST_IP=$(ip route | grep default | cut -d" " -f3)
if [ -z "$HOST_IP" ]; then
    echo "ERROR: Failed to detect host IP"
    exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed "s/\.[0-9]*$/.0\/24/")
echo "Host network detected as: $HOST_NETWORK"

# Set up remaining iptables rules
iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# 4. Send outbound HTTPS through the proxy; only the proxy's own uid may connect out.
# Loopback and the host network keep their existing direct access.
iptables -t nat -A OUTPUT -d 127.0.0.0/8 -j RETURN
iptables -t nat -A OUTPUT -d "$HOST_NETWORK" -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$SNI_PROXY_USER" -j RETURN
iptables -t nat -A OUTPUT -p tcp --dport 443 -j REDIRECT --to-ports "$SNI_PROXY_PORT"
iptables -A OUTPUT -p tcp --dport 443 -m owner --uid-owner "$SNI_PROXY_USER" -j ACCEPT
# A redirected packet still shows its original interface here, so `-o lo` doesn't match.
iptables -A OUTPUT -d 127.0.0.1 -p tcp --dport "$SNI_PROXY_PORT" -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# IPv6: nothing is proxied or allowlisted over v6, so drop it all except loopback —
# otherwise any v6 route would bypass the rules above.
ip6tables -F
ip6tables -X
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 --max-time 10 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Any one is enough: this tests the proxy, and shouldn't fail because one site is down.
for url in https://api.github.com/zen https://registry.npmjs.org/ https://api.anthropic.com/; do
    if curl -s -o /dev/null --connect-timeout 5 --max-time 10 "$url"; then
        echo "Firewall verification passed - able to reach $url through the proxy"
        exit 0
    fi
done
echo "ERROR: Firewall verification failed - no allowlisted host reachable through the proxy"
exit 1
