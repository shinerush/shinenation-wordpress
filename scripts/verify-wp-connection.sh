#!/usr/bin/env bash
# ===========================================================================
# verify-wp-connection.sh — READ-ONLY preflight for the WordPress MCP link.
#
# Performs GET requests only. It never writes, publishes, or modifies
# anything on the site. Run it BEFORE wiring up the MCP server so that a
# failure is diagnosed here rather than inside an opaque MCP handshake.
#
# Usage:
#   set -a; source .env; set +a
#   ./scripts/verify-wp-connection.sh
# ===========================================================================
set -uo pipefail

fail=0
note() { printf '\n\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

note "1. Environment variables"
for v in WORDPRESS_SITE_URL WORDPRESS_USERNAME WORDPRESS_APP_PASSWORD; do
  if [ -z "${!v:-}" ]; then bad "$v is not set"; else ok "$v is set"; fi
done
[ "$fail" -eq 1 ] && { echo; echo "Load them first: set -a; source .env; set +a"; exit 1; }

SITE="${WORDPRESS_SITE_URL%/}"
case "$SITE" in
  https://*) ok "Site URL uses https (Application Passwords are sent via Basic Auth)" ;;
  *) bad "Site URL must start with https:// — WordPress refuses Application Passwords over plain http" ;;
esac

# Application passwords are 24 chars, conventionally shown in 6 groups of 4.
pw_stripped="${WORDPRESS_APP_PASSWORD// /}"
if [ "${#pw_stripped}" -eq 24 ]; then
  ok "Application Password length looks correct (24 chars ignoring spaces)"
else
  warn "Application Password is ${#pw_stripped} chars ignoring spaces; expected 24. Did you paste your login password by mistake?"
fi

note "2. REST API discovery (anonymous GET ${SITE}/wp-json/)"
root=$(curl -sS -m 30 -w '\n%{http_code}' "$SITE/wp-json/" 2>/dev/null)
code="${root##*$'\n'}"; body="${root%$'\n'*}"
if [ "$code" = "200" ]; then
  ok "REST API reachable (HTTP 200)"
  if command -v jq >/dev/null 2>&1; then
    printf '        name: %s\n' "$(printf '%s' "$body" | jq -r '.name // "?"')"
    printf '        home: %s\n' "$(printf '%s' "$body" | jq -r '.home // "?"')"
    if printf '%s' "$body" | jq -e '.namespaces | index("wp/v2")' >/dev/null 2>&1; then
      ok "wp/v2 namespace present"
    else
      bad "wp/v2 namespace missing — core REST routes are disabled or filtered"
    fi
  fi
else
  bad "REST API not reachable (HTTP ${code:-none}). A security plugin, Cloudflare rule, or Hostinger firewall may be blocking /wp-json/."
fi

note "3. Authenticated identity check (GET ${SITE}/wp-json/wp/v2/users/me)"
me=$(curl -sS -m 30 -w '\n%{http_code}' \
      -u "$WORDPRESS_USERNAME:$WORDPRESS_APP_PASSWORD" \
      "$SITE/wp-json/wp/v2/users/me?context=edit" 2>/dev/null)
code="${me##*$'\n'}"; body="${me%$'\n'*}"
case "$code" in
  200)
    ok "Authentication succeeded"
    if command -v jq >/dev/null 2>&1; then
      printf '        user: %s (id %s)\n' \
        "$(printf '%s' "$body" | jq -r '.slug // "?"')" \
        "$(printf '%s' "$body" | jq -r '.id // "?"')"
      printf '        roles: %s\n' "$(printf '%s' "$body" | jq -r '(.roles // []) | join(", ")')"
    fi
    ;;
  401) bad "401 Unauthorized — wrong username, revoked/mistyped Application Password, or the Authorization header is being stripped (common with some Apache/LiteSpeed setups)." ;;
  403) bad "403 Forbidden — request reached WordPress but was rejected. Usually a security plugin or WAF rule." ;;
  *)   bad "Unexpected HTTP ${code:-none} on the authenticated request." ;;
esac

note "4. Capability probe (read-only)"
caps=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' \
        -u "$WORDPRESS_USERNAME:$WORDPRESS_APP_PASSWORD" \
        "$SITE/wp-json/wp/v2/posts?per_page=1&context=edit" 2>/dev/null)
if [ "$caps" = "200" ]; then
  ok "Can read posts in edit context (account has editing capability)"
else
  warn "HTTP $caps reading posts in edit context — the account may lack edit capability."
fi

echo
if [ "$fail" -eq 0 ]; then
  printf '\033[32mAll critical checks passed. Safe to enable the MCP server.\033[0m\n'
else
  printf '\033[31mOne or more critical checks failed — fix these before enabling MCP.\033[0m\n'
fi
exit "$fail"
