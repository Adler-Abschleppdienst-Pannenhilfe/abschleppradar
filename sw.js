// AbschleppRadar – Service Worker (macht die Seite installierbar)
const CACHE = "abschleppradar-v1";
self.addEventListener("install", e => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET" || req.mode !== "navigate") return;
  e.respondWith(
    fetch(req).then(res => {
      const copy = res.clone();
      caches.open(CACHE).then(c => c.put("/", copy));
      return res;
    }).catch(() => caches.match("/"))
  );
});
