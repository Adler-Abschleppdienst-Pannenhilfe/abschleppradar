// AbschleppRadar – Service Worker (installierbar + Handy-Benachrichtigungen)
// Seiten immer zuerst aus dem Internet laden (neueste Version), ohne Netz die gespeicherte Startseite.
const CACHE = "abschleppradar-v2";
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
// Benachrichtigung anzeigen
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "AbschleppRadar", {
    body: d.body || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: d.tag || undefined,
    renotify: !!d.tag,
    vibrate: [200, 100, 200, 100, 300],
    data: { url: d.url || "/" }
  }));
});
// Antippen: App öffnen (vorhandenes Fenster bevorzugen)
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = (e.notification.data && e.notification.data.url) || "/";
  e.waitUntil((async () => {
    const all = await clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const c of all) {
      if (new URL(c.url).origin === self.location.origin) {
        await c.focus();
        try { await c.navigate(url); } catch (err) {}
        return;
      }
    }
    await clients.openWindow(url);
  })());
});
