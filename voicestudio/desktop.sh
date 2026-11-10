#!/usr/bin/env bash
# Menu launcher for the VoiceStudio desktop app (~/.local/share/applications/VoiceStudio.desktop points here).
# The desktop app and the Docker copy can't both fit on the 8 GB card: with the container holding ~2 GB, desktop
# renders fail with "CUDA out of memory". So: turn the container off, run the desktop app, and once it has fully
# closed, turn the container back on if it was on before (the phone and Claude's voice tools use it).
DOCK="$HOME/claude_workspace/linux-remote/dock"
APP=/opt/VoiceStudio/voicestudio-electron

was_on=0
if [ -n "$(docker ps -q --filter name='^omnivoice$' --filter status=running 2>/dev/null)" ]; then
  was_on=1
  "$DOCK" off voicestudio >/dev/null 2>&1
fi

"$APP" "$@"

[ "$was_on" = 1 ] || exit 0
# The launcher can return while the app keeps running (a second click hands off to the open window), and the app's
# engine (under ~/.config/VoiceStudio/runtime) lets go of the card a few seconds after the window closes.
while pgrep -f "$APP" >/dev/null || pgrep -f "$HOME/.config/VoiceStudio/runtime" >/dev/null; do
  sleep 3
done
"$DOCK" on voicestudio >/dev/null 2>&1
