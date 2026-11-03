// Keeps the last good copy of the page so that, if the panel is down or the phone can't reach it,
// the home-screen app shows "Can't reach the panel" instead of a blank white page.
const CACHE = "dock-shell-v2";

self.addEventListener("install", (e) => {
  self.skipWaiting();
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(["/", "/lock.js", "/icon.png"])));
});
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.startsWith("/api/")) return;
  const cached = () => caches.match(e.request);
  const timeout = new Promise((_, no) => setTimeout(no, 6000));
  e.respondWith(
    Promise.race([fetch(e.request), timeout])
      .then(async (r) => {
        if (r.ok) { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; }
        return (await cached()) || r;  // a 502 from Tailscale means the panel is down
      })
      .catch(async () => (await cached()) || Response.error())
  );
});
