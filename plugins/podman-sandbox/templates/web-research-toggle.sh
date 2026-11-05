#!/bin/bash
# Toggles unrestricted outbound HTTP/HTTPS (ports 80/443) on top of the default-deny
# firewall set up by init-firewall.sh. Off by default — the fixed allowlist in
# init-firewall.sh still covers normal tool/package-manager traffic. Turn this on only
# for the duration of a research task, then back off: while on, a compromised
# dependency can exfiltrate to any host over 80/443, indistinguishable from legitimate
# web traffic. Every other port/protocol stays blocked regardless of this toggle.
#
# Port 443 normally gets redirected to the SNI proxy in the nat table before the filter
# table sees it, so turning this on takes both: a nat rule that skips the redirect, and
# filter rules that let the now-direct traffic out.
set -euo pipefail

usage() {
    echo "Usage: web-research-toggle.sh {on|off|status}" >&2
    exit 1
}

# Without root, iptables -C fails and every rule would look absent.
if [ "$(id -u)" -ne 0 ]; then
    echo "web-research-toggle.sh must run as root (use sudo)." >&2
    exit 1
fi

filter_rule_present() {
    iptables -C OUTPUT -p tcp --dport "$1" -j ACCEPT 2>/dev/null
}

redirect_bypass_present() {
    iptables -t nat -C OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null
}

case "${1:-}" in
    on)
        filter_rule_present 80 || iptables -I OUTPUT -p tcp --dport 80 -j ACCEPT
        filter_rule_present 443 || iptables -I OUTPUT -p tcp --dport 443 -j ACCEPT
        redirect_bypass_present || iptables -t nat -I OUTPUT -p tcp --dport 443 -j ACCEPT
        echo "Web research mode ON — outbound HTTP/HTTPS allowed to any destination."
        ;;
    off)
        iptables -t nat -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
        iptables -D OUTPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
        echo "Web research mode OFF — back to the fixed allowlist only."
        ;;
    status)
        if filter_rule_present 80 && filter_rule_present 443 && redirect_bypass_present; then
            echo "Web research mode: ON"
        elif ! filter_rule_present 80 && ! filter_rule_present 443 && ! redirect_bypass_present; then
            echo "Web research mode: OFF"
        else
            echo "Web research mode: INCONSISTENT (partial rules; run 'off' to reset)"
            exit 1
        fi
        # Ignores zombies: PID 1 in these containers may never reap the old proxy.
        if ps -u sniproxy -o stat= 2>/dev/null | grep -qv '^Z'; then
            echo "SNI proxy: running"
        else
            echo "SNI proxy: NOT running — allowlisted HTTPS will fail; re-run init-firewall.sh"
        fi
        ;;
    *)
        usage
        ;;
esac
