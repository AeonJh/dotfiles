#!/usr/bin/env bash
set -euo pipefail

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

need_command jq

if [[ $# -gt 0 ]]; then
  if [[ ! -r "$1" ]]; then
    printf 'Cannot read input file: %s\n' "$1" >&2
    exit 1
  fi
  raw=$(<"$1")
else
  need_command curl

  base_url="${CLIPROXY_BASE_URL:-http://127.0.0.1:8317}"
  manage_api_key="${CLIPROXY_MANAGE_API_KEY:-}"
  auth_index="${CLIPROXY_AUTH_INDEX:-}"
  account_id="${CLIPROXY_CHATGPT_ACCOUNT_ID:-}"
  user_agent="${CLIPROXY_CODEX_USER_AGENT:-codex_cli_rs/0.76.0 (Debian 13.0.0; x86_64) WindowsTerminal}"

  if [[ -z "$manage_api_key" || -z "$auth_index" || -z "$account_id" ]]; then
    printf '%s\n' 'Missing CLIPROXY_MANAGE_API_KEY, CLIPROXY_AUTH_INDEX, or CLIPROXY_CHATGPT_ACCOUNT_ID' >&2
    exit 1
  fi

  payload=$(jq -cn \
    --arg authIndex "$auth_index" \
    --arg userAgent "$user_agent" \
    --arg accountId "$account_id" \
    '{
      authIndex: $authIndex,
      method: "GET",
      url: "https://chatgpt.com/backend-api/wham/usage",
      header: {
        Authorization: "Bearer $TOKEN$",
        "Content-Type": "application/json",
        "User-Agent": $userAgent,
        "Chatgpt-Account-Id": $accountId
      }
    }')

  raw=$(curl -fsS \
    --connect-timeout 2 \
    --max-time 10 \
    "${base_url%/}/v0/management/api-call" \
    -H 'Accept: application/json, text/plain, */*' \
    -H "Authorization: Bearer $manage_api_key" \
    -H 'Content-Type: application/json' \
    -H "Origin: ${base_url%/}" \
    -H "Referer: ${base_url%/}/management.html" \
    --data-raw "$payload")
fi

printf '%s\n' "$raw" | jq -c '
  def payload:
    if (.body? | type) == "string" then (.body | fromjson)
    elif (.body? | type) == "object" then .body
    else . end;
  def window($w):
    {
      used_percentage: (($w.used_percent // $w.used_percentage // -1) | tonumber),
      window_seconds: ($w.limit_window_seconds // $w.window_seconds // null),
      reset_after_seconds: ($w.reset_after_seconds // null),
      reset_at: ($w.reset_at // null)
    };
  (payload) as $p
  | {
      rate_limits: {
        five_hour: window($p.rate_limit.primary_window // {}),
        seven_day: window($p.rate_limit.secondary_window // {})
      },
      plan_type: ($p.plan_type // null),
      allowed: ($p.rate_limit.allowed // null),
      limit_reached: ($p.rate_limit.limit_reached // null)
    }
'
