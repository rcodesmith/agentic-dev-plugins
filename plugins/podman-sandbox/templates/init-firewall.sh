#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, and pipeline failures
IFS=$'\n\t'       # Stricter word splitting

# ---------------------------------------------------------------------------
# CUSTOMIZE HERE: add your project's own package-registry / toolchain domains.
# Examples (uncomment / add what your project actually needs):
#   "pypi.org" "files.pythonhosted.org" "astral.sh"   # Python / uv / pip
#   "crates.io" "static.crates.io" "sh.rustup.rs"     # Rust / cargo
#   "proxy.golang.org" "sum.golang.org"               # Go
#   "rubygems.org"                                    # Ruby / bundler
#   "objects.githubusercontent.com" "release-assets.githubusercontent.com"
#                                                     # GitHub release-asset downloads
# registry.npmjs.org is already covered below (Claude Code itself needs it).
# Every domain here must resolve, or the script fails (closed — all egress blocked).
EXTRA_DOMAINS=(
)
# ---------------------------------------------------------------------------

# Fail closed: if anything below aborts (set -e), drop all non-loopback traffic rather
# than leave a half-built firewall — which is wide open on a fresh container (ACCEPT
# policies) and silently drops everything on a re-run.
fail_closed() {
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT DROP
        echo "ERROR: init-firewall.sh failed (exit $rc) — all egress blocked. Fix, then re-run." >&2
    fi
    exit "$rc"
}
trap fail_closed EXIT

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Reset policies first: -F/-X don't, so a re-run would otherwise start under the previous
# run's DROP and hang fetching GitHub's ranges below.
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

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

# Create ipset with CIDR support
# `ipset add ... -exist` below (not in upstream Anthropic reference) because
# CDN-backed domains can resolve to the same IP as each other across separate `dig`
# calls — a plain `ipset add` errors on that duplicate and, under `set -e`, aborts the
# whole firewall setup.
ipset create allowed-domains hash:net

# Fetch GitHub meta information and aggregate + add their IP ranges
echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -s --connect-timeout 10 --max-time 30 https://api.github.com/meta)
if [ -z "$gh_ranges" ]; then
    echo "ERROR: Failed to fetch GitHub IP ranges"
    exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
    echo "ERROR: GitHub API response missing required fields"
    exit 1
fi

echo "Processing GitHub IPs..."
while read -r cidr; do
    if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "ERROR: Invalid CIDR range from GitHub meta: $cidr"
        exit 1
    fi
    echo "Adding GitHub range $cidr"
    ipset add allowed-domains "$cidr" -exist
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | aggregate -q)

# Resolve and add other allowed domains — the base set Claude Code itself needs, plus
# whatever this project added to EXTRA_DOMAINS above.
# claude.ai / platform.claude.com: `claude auth login --claudeai` + token refresh;
# mcp-proxy.anthropic.com: claude.ai MCP connectors; downloads.claude.ai: Claude Code
# version checks; raw.githubusercontent.com: plugin marketplaces. Several share an IP
# with api.anthropic.com or GitHub's ranges today — listed so that stays a non-issue.
# The documentation block lets the agent read reference docs without the web-research
# toggle. Most of these sit on shared CDN/Vercel IPs, so allowlisting one also reaches
# whatever else is hosted on the same address — accepted for read-only docs.
BASE_DOMAINS=(
    "registry.npmjs.org"
    "api.anthropic.com"
    "claude.ai"
    "platform.claude.com"
    "mcp-proxy.anthropic.com"
    "downloads.claude.ai"
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
for domain in "${BASE_DOMAINS[@]}" "${EXTRA_DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "ERROR: Failed to resolve $domain"
        exit 1
    fi

    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "Adding $ip for $domain"
        ipset add allowed-domains "$ip" -exist
    done < <(echo "$ips")
done

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

# Set default policies to DROP first
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# First allow established connections for already approved traffic
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Then allow only specific outbound traffic to allowed domains
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT

# Explicitly REJECT all other outbound traffic for immediate feedback
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# IPv6: nothing is allowlisted over v6 (dig above resolves A records only), so drop it
# all except loopback — otherwise any v6 route would bypass the rules above.
ip6tables -F
ip6tables -X
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT DROP
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - was able to reach https://example.com"
    exit 1
else
    echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

# Verify GitHub API access
if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach https://api.github.com"
    exit 1
else
    echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi
