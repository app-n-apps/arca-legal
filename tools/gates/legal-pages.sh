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

  # Parse HTML rather than counting markup or matching comments/CSS/scripts.
  # Python runs isolated and uses only the standard library, without temp files.
  if ! visible=$(printf '%s' "$body" | python3 -I -c '
from html.parser import HTMLParser
import re
import sys

class VisibleText(HTMLParser):
    blocked = {"head", "style", "script", "template"}
    blocks = {"p", "div", "li", "h1", "h2", "h3", "br", "header", "footer", "main", "nav", "section"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.depth = 0
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in self.blocked:
            self.depth += 1
        if not self.depth and tag in self.blocks:
            self.parts.append(" ")

    def handle_endtag(self, tag):
        if tag in self.blocked:
            self.depth = max(0, self.depth - 1)
        if not self.depth and tag in self.blocks:
            self.parts.append(" ")

    def handle_data(self, data):
        if not self.depth:
            self.parts.append(data)

parser = VisibleText()
parser.feed(sys.stdin.read())
parser.close()
sys.stdout.write(re.sub(r"\s+", " ", "".join(parser.parts)).strip())
'); then
    fail "$page: could not extract visible text"
    continue
  fi
  bytes=$(printf '%s' "$visible" | wc -c)
  if (( bytes < 2048 )); then
    fail "$page: $bytes visible-text bytes (minimum 2048)"
  fi
  if ! grep -qw 'Arca' <<< "$visible"; then
    fail "$page: missing Arca"
  fi
  if [[ $page == privacy-policy.html ]]; then
    for required in 'Google Gemini' OpenAI OpenRouter eBay Firebase \
      'Apple DeviceCheck' 'App Attest' Apphud AppsFlyer Amplitude \
      Crashlytics iCloud 'photos are not stored' 'Delete my data'; do
      if [[ $visible != *"$required"* ]]; then
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
