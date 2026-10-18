#!/usr/bin/env bash
set -euo pipefail

failures=0
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

mode=remote
if [[ $# -eq 2 && $1 == --local ]]; then
  mode=local
  base=$2
elif [[ $# -eq 1 && $1 != --* ]]; then
  base=${1%/}
else
  printf 'Usage: %s <base-url> | --local <directory>\n' "$0" >&2
  exit 1
fi

for page in privacy-policy.html terms-of-use.html support.html; do
  body=''
  if [[ $mode == local ]]; then
    if [[ ! -f "$base/$page" || ! -r "$base/$page" ]]; then
      fail "$page: missing or unreadable file"
      continue
    fi
    body=$(cat -- "$base/$page")
  else
    # Keep response and status in memory; do not create temporary files.
    if response=$(curl -sL --max-time 20 --write-out $'\n%{http_code}' "$base/$page"); then
      status=${response##*$'\n'}
      body=${response%$'\n'*}
      if [[ $status != 200 ]]; then
        fail "$page: HTTP $status (expected 200)"
      fi
    else
      fail "$page: curl failed"
      continue
    fi
  fi

  # Count the original file locally; the appended HTTP status preserves body
  # newlines in the remote response until we separate the status above.
  if [[ $mode == local ]]; then
    bytes=$(wc -c < "$base/$page")
  else
    bytes=$(printf '%s' "$body" | wc -c)
  fi
  if (( bytes < 2048 )); then
    fail "$page: $bytes bytes (minimum 2048)"
  fi
  if [[ $body != *Arca* ]]; then
    fail "$page: missing Arca"
  fi
  if [[ $page == privacy-policy.html ]]; then
    for required in 'Google Gemini' OpenAI OpenRouter eBay Firebase \
      'Apple DeviceCheck' 'App Attest' Apphud AppsFlyer Amplitude \
      Crashlytics iCloud 'photos are not stored' 'Delete my data'; do
      if [[ $body != *"$required"* ]]; then
        fail "$page: missing $required"
      fi
    done
  fi
done

if (( failures > 0 )); then
  printf 'Legal pages gate: FAIL (%d failures)\n' "$failures" >&2
  exit 1
fi
printf 'Legal pages gate: PASS (3 pages)\n'
