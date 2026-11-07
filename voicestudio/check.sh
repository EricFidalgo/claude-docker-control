#!/usr/bin/env bash
# Checks that VoiceStudio opens without asking for the API key or a PIN, from the PC and the phone.
# Run after changing gate.py, compose.yaml, the tailscale serve rule or apps.yaml. Never prints the key.
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()  { echo "ok    $1"; }
bad() { echo "FAIL  $1"; fail=1; }

line=$(./dock urls 2>/dev/null | grep '^VoiceStudio')
pc=$(sed -n 's/.*pc: \(http[^ ]*\).*/\1/p' <<<"$line")
phone=$(sed -n 's/.*phone: \(https[^ ]*\).*/\1/p' <<<"$line")

# PC: the panel's PC link must open the app without the API key (the gate adds it).
code=$(curl -s -m60 -o /dev/null -w "%{http_code}" "${pc}engines")  # slow for a few seconds after a restart
[ "$code" = 200 ] && ok "PC link $pc opens without a key" || bad "PC link $pc answered $code (the app would ask for the API key)"

# Phone: the panel must show a phone link.
[ -n "$phone" ] && ok "phone link $phone" || bad "no phone link in the panel"

# Phone, locked: API calls must tell the page to reload into the phone lock, not show the app's own PIN box.
hdr=$(curl -s -m10 -o /dev/null -D - -H 'X-Forwarded-For: 100.64.0.9' "${pc}engines" | tr -d '\r')
grep -qi '^x-gate-locked: 1' <<<"$hdr" && ok "locked phone gets the reload signal" || bad "locked phone gets no reload signal (the app shows 'Share on your network')"

# Rendering from the page, at each address it can be opened at (the app refuses when Origin and Host differ).
for o in "${pc%/}" "${phone%/}"; do
  [ -n "$o" ] || continue
  hdrs=(-H "Origin: $o" -H 'Sec-Fetch-Site: same-origin' -H 'X-OmniVoice-CSRF: 1' -H "Host: ${o#*://}")
  [ "${o%%:*}" = https ] && hdrs+=(-H 'X-Forwarded-Proto: https')
  code=$(curl -s -m120 -o /dev/null -w '%{http_code}' "${hdrs[@]}" -F text=Check. -F language=en "http://127.0.0.1:3901/generate")
  [ "$code" = 200 ] && ok "render works from $o" || bad "render from $o answered $code"
done

# Claude's tools: the MCP endpoint in ~/.claude.json must answer with its key.
url=$(python3 -I -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude.json')))['mcpServers']['voicestudio-docker']['url'])")
auth=$(python3 -I -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude.json')))['mcpServers']['voicestudio-docker']['headers']['Authorization'])")
code=$(curl -s -m10 -o /dev/null -w '%{http_code}' -X POST "$url" -H "Authorization: $auth" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"check","version":"1"}}}')
[ "$code" = 200 ] && ok "Claude's VoiceStudio tools reach $url" || bad "Claude's VoiceStudio tools: $url answered $code"

exit $fail
