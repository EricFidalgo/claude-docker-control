#!/usr/bin/env bash
# Makes a new VoiceStudio API key and updates every place that uses it. Never prints the key.
#  1. the secrets file the container reads
#  2. Claude's connection settings (the speaker button reads the key from there)
#  3. restarts the container
set -euo pipefail
umask 077  # files made below (the .tmp copy of the secrets file) start private

ENVFILE="$HOME/.claude-secrets/env/voicestudio.env"
CLAUDE_JSON="$HOME/.claude.json"
HERE="$(cd "$(dirname "$0")" && pwd)"

KEY="$(openssl rand -hex 24)"

# 1. secrets file (keep any other lines, replace just the key line)
touch "$ENVFILE"; chmod 600 "$ENVFILE"
grep -v '^OMNIVOICE_API_KEY=' "$ENVFILE" > "$ENVFILE.tmp" || true
echo "OMNIVOICE_API_KEY=$KEY" >> "$ENVFILE.tmp"
mv "$ENVFILE.tmp" "$ENVFILE"; chmod 600 "$ENVFILE"

# 2. Claude's connection settings (backup first)
cp "$CLAUDE_JSON" "$CLAUDE_JSON.bak-before-key-change"
KEY="$KEY" CLAUDE_JSON="$CLAUDE_JSON" python3 -I - <<'EOF'
import json, os
p = os.environ["CLAUDE_JSON"]
d = json.load(open(p))
d["mcpServers"]["voicestudio-docker"]["headers"]["Authorization"] = "Bearer " + os.environ["KEY"]
json.dump(d, open(p, "w"), indent=2)
EOF

# 3. restart the phone lock (it adds the key for the phone) and the container
systemctl --user restart voicestudio-gate
cd "$HERE" && docker compose up -d --force-recreate >/dev/null 2>&1
echo "New key saved and the container restarted. The key was not printed."
echo "To read it: grep OMNIVOICE_API_KEY $ENVFILE"
