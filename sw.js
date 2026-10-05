// صالون أبو يوسف - Service Worker (الشبكة أولًا عشان التحديثات تظهر فورًا)
const V = "salon-v10";
const SHELL = ["/", "/staff", "/admin", "/app.js", "/config.js", "/style.css", "/icon-192.png", "/manifest.webmanifest", "/manifest-staff.webmanifest", "/manifest-admin.webmanifest", "/icon-staff-192.png", "/icon-admin-192.png"];
self.addEventListener("install", e => {
  e.waitUntil(caches.open(V).then(c => Promise.all(SHELL.map(u => c.add(u).catch(() => {})))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(k => Promise.all(k.filter(x => x !== V).map(x => caches.delete(x)))).then(() => clients.claim()));
});
self.addEventListener("fetch", e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== "GET") return;
  const cdn = u.hostname === "cdn.jsdelivr.net" || u.hostname === "fonts.googleapis.com" || u.hostname === "fonts.gstatic.com";
  if (u.origin !== location.origin && !cdn) return; // طلبات سوبابيز تروح للشبكة مباشرة ومبتتخزنش
  if (cdn) { // مكتبات وخطوط: الكاش أولًا
    e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); return res; })));
    return;
  }
  e.respondWith(fetch(r).then(res => {
    if (res.ok && !res.redirected) { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); }
    return res;
  }).catch(() => caches.match(r).then(m => m || caches.match(r.mode === "navigate" ? (u.pathname.startsWith("/admin") ? "/admin" : u.pathname.startsWith("/staff") ? "/staff" : "/") : r))));
});
