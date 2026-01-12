#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

LOCKFILE="/run/allowed-domains-refresh.lock"
mkdir -p /run

# Prevent concurrent refresh runs (requires util-linux for flock)
exec 9>"$LOCKFILE"
flock -n 9 || { echo "Another refresh is running; exiting." >&2; exit 0; }

DOMAINS=(
  "registry.npmjs.org"
  "pypi.org"
  "files.pythonhosted.org"
  "api.anthropic.com"
  "sentry.io"
  "statsig.anthropic.com"
  "statsig.com"
  "marketplace.visualstudio.com"
  "vscode.blob.core.windows.net"
  "update.code.visualstudio.com"
  "auth.openai.com"
  "api.openai.com"
  "chatgpt.com"
)

# Ensure base set exists
ipset list allowed-domains >/dev/null 2>&1 || ipset create allowed-domains hash:net family inet

# Create temp set (clean up any leftover from prior crash)
ipset destroy allowed-domains-new 2>/dev/null || true
ipset create allowed-domains-new hash:net family inet

added=0

# --- GitHub CIDRs ---
gh_ranges="$(curl -fsS --connect-timeout 5 --max-time 15 https://api.github.com/meta)"
echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null

cidr_stream="$(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]')"

# If aggregate exists, use it; otherwise add raw CIDRs as-is
if command -v aggregate >/dev/null 2>&1; then
  cidr_stream="$(echo "$cidr_stream" | aggregate -q)"
fi

while read -r cidr; do
  [ -n "$cidr" ] || continue
  ipset add allowed-domains-new "$cidr" -exist
  added=$((added + 1))
done <<<"$cidr_stream"

# --- Domain A records -> IPs ---
dns_failures=0
for domain in "${DOMAINS[@]}"; do
  ips="$(dig +time=2 +tries=2 +noall +answer A "$domain" \
        | awk '$4=="A"{print $5}' \
        | sort -u || true)"

  if [ -z "${ips:-}" ]; then
    echo "WARN: no A records for $domain; not adding this refresh" >&2
    dns_failures=$((dns_failures + 1))
    continue
  fi

  while read -r ip; do
    [ -n "$ip" ] || continue
    ipset add allowed-domains-new "$ip" -exist
    added=$((added + 1))
  done <<<"$ips"
done

# Sanity gate: don't swap if we ended up with an unusually small set
# Tune thresholds to your environment. The goal is "fail open" on bad refreshes.
if [ "$added" -lt 20 ]; then
  echo "ERROR: Refresh produced too few entries ($added). Keeping existing allowed-domains." >&2
  ipset destroy allowed-domains-new
  exit 1
fi

# Optional stricter gate: if DNS is very flaky, keep old set
# (For example, if more than half the domains failed.)
if [ "$dns_failures" -gt $(( ${#DOMAINS[@]} / 2 )) ]; then
  echo "ERROR: Too many DNS failures ($dns_failures). Keeping existing allowed-domains." >&2
  ipset destroy allowed-domains-new
  exit 1
fi

# Atomic cutover
ipset swap allowed-domains-new allowed-domains
ipset destroy allowed-domains-new

echo "allowed-domains-refresh complete (entries added: $added, dns failures: $dns_failures)"
