#!/bin/bash
# Toggles unrestricted outbound HTTP/HTTPS (ports 80/443) on top of the default-deny
# firewall set up by init-firewall.sh. Off by default — the fixed allowlist in
# init-firewall.sh still covers normal tool/package-manager traffic. Turn this on only
# for the duration of a research task, then back off: while on, a compromised
# dependency can exfiltrate to any host over 80/443, indistinguishable from legitimate
# web traffic. Every other port/protocol stays blocked regardless of this toggle.
set -euo pipefail

usage() {
    echo "Usage: web-research-toggle.sh {on|off|status}" >&2
    exit 1
}

rule_present() {
    iptables -C OUTPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null
}

case "${1:-}" in
    on)
        rule_present 80 || iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT
        rule_present 443 || iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT
        echo "Web research mode ON — outbound HTTP/HTTPS allowed to any destination."
        ;;
    off)
        iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        echo "Web research mode OFF — back to the fixed allowlist only."
        ;;
    status)
        if rule_present 443; then
            echo "Web research mode: ON"
        else
            echo "Web research mode: OFF"
        fi
        ;;
    *)
        usage
        ;;
esac
