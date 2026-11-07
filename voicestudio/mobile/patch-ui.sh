#!/bin/sh
# Container entrypoint: add the phone layout to the stock web UI, then start the app as the image normally does.
# This folder is mounted at assets/vs-mobile/, inside the folder the API-key gate leaves open for the app's own files,
# so everything in it is readable without the key. Keep it to the layout files and this script.
# index.html is edited in place rather than replaced by a mounted copy, so the hashed asset names in it stay right
# after an image update. Everything added stays on ONE line containing assets/vs-mobile/, so the delete below removes
# it all before each re-add (a second line would pile up at every restart). It also adds the home-screen app tags (icon, name); gate.py serves those files, since the
# container has no /vs-app/. The layout tags are rewritten at every start with ?v=<file time>, so a restart makes phones fetch
# edited layout files instead of reusing cached ones (the icon files are cached an hour by gate.py).
INDEX=/app/frontend/dist/index.html
HERE=/app/frontend/dist/assets/vs-mobile
if [ -f "$INDEX" ]; then
  v=$(cat "$HERE/vs-mobile.css" "$HERE/vs-mobile.js" | cksum | cut -d' ' -f1)
  sed -i -e '/assets\/vs-mobile\//d' \
    -e "s|</head>|  <link rel=\"icon\" href=\"/vs-app/icon-round-192.png\" /><meta name=\"mobile-web-app-capable\" content=\"yes\" /><link rel=\"apple-touch-icon\" href=\"/vs-app/icon-180.png\" /><link rel=\"manifest\" href=\"/manifest.webmanifest\" /><meta name=\"apple-mobile-web-app-capable\" content=\"yes\" /><meta name=\"apple-mobile-web-app-title\" content=\"VoiceStudio\" /><meta name=\"theme-color\" content=\"#1b1520\" /><link rel=\"stylesheet\" href=\"/assets/vs-mobile/vs-mobile.css?v=$v\" /><script src=\"/assets/vs-mobile/vs-mobile.js?v=$v\" defer></script>\n  </head>|" \
    "$INDEX" || echo "patch-ui: could not add the phone layout; starting without it" >&2
else
  echo "patch-ui: $INDEX not found; starting without the phone layout" >&2
fi
cd /app
# The image's own start command (its ENTRYPOINT, with no CMD). Check it here after an image update.
# Start as root only to edit index.html above, then drop to the host user so files in the shared ~/.omnivoice folder
# stay owned by you (the desktop app uses the same folder).
exec setpriv --reuid=1000 --regid=1000 --clear-groups python3 backend/docker_entrypoint.py "$@"
