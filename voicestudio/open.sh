#!/usr/bin/env bash
# Menu launcher "VoiceStudio (Docker)": turns the Docker copy on if it's off, waits until it answers, then opens it in
# its own window (Chrome app mode, no tabs or address bar). The desktop app can't share the 8 GB card with it, so if the
# desktop app is open this says so instead of starting a copy that would run out of memory.
DOCK="$HOME/claude_workspace/linux-remote/dock"
URL=http://127.0.0.1:3901/
note() { command -v notify-send >/dev/null && notify-send -i voicestudio-docker "VoiceStudio" "$1"; echo "$1"; }

if [ -z "$(docker ps -q --filter name='^omnivoice$' --filter status=running 2>/dev/null)" ]; then
  if pgrep -f /opt/VoiceStudio/voicestudio-electron >/dev/null; then
    note "The desktop VoiceStudio is open and has the graphics card. Close it first, then open this again."
    exit 1
  fi
  note "Starting VoiceStudio..."
  "$DOCK" on voicestudio >/dev/null 2>&1
fi

ready=0
for _ in $(seq 1 90); do
  [ "$(curl -s -m3 -o /dev/null -w '%{http_code}' "${URL}engines")" = 200 ] && { ready=1; break; }
  sleep 2
done
[ "$ready" = 1 ] || { note "VoiceStudio didn't start. Check the Docker panel."; exit 1; }
exec google-chrome --app="$URL" "$@"
