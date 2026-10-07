// صالون أبو يوسف - Service Worker (الشبكة أولًا عشان التحديثات تظهر فورًا)
const V = "salon-v12";
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

// ===== الإشعارات (Web Push): بتظهر وتصدّر صوت حتى لو التطبيق مقفول =====
self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "صالون أبو يوسف", body: e.data ? e.data.text() : "" }; }
  const ios = /iphone|ipad|ipod/i.test(self.navigator.userAgent);
  e.waitUntil((async () => {
    const cs = await clients.matchAll({ type: "window", includeUncontrolled: true });
    const live = cs.find(c => c.focused && c.visibilityState === "visible");
    if (live) live.postMessage({ type: "push", title: d.title, body: d.body, tab: d.tab, urgent: !!d.urgent }); // التطبيق مفتوح قدامه: الصوت والتنبيه جوه التطبيق
    if (live && !ios) return; // آيفون لازم يظهر إشعار مع كل push وإلا بيسحب الإذن
    await self.registration.showNotification(d.title || "صالون أبو يوسف", {
      body: d.body || "", icon: "/icon-192.png", badge: "/icon-192.png", tag: d.tag || undefined, renotify: !!d.tag,
      dir: "rtl", lang: "ar", silent: false, requireInteraction: !!d.urgent,
      vibrate: d.urgent ? [250, 120, 250, 120, 400] : [200, 100, 200],
      data: { url: d.url || "/", tab: d.tab || "" }
    });
    try { const n = await self.registration.getNotifications(); if (self.navigator.setAppBadge) await self.navigator.setAppBadge(n.length); } catch (_) {}
  })());
});
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const { url = "/", tab = "" } = e.notification.data || {};
  e.waitUntil((async () => {
    const target = new URL(url, self.location.origin);
    const root = p => p.startsWith("/admin") ? "/admin" : p.startsWith("/staff") ? "/staff" : "/";
    const cs = await clients.matchAll({ type: "window", includeUncontrolled: true });
    const same = cs.find(c => { const u = new URL(c.url); return !/^\/(book|qr)/.test(u.pathname) && root(u.pathname) === root(target.pathname); });
    try { const n = await self.registration.getNotifications(); if (self.navigator.setAppBadge) { n.length ? await self.navigator.setAppBadge(n.length) : await self.navigator.clearAppBadge(); } } catch (_) {}
    if (same) { await same.focus(); same.postMessage({ type: "goto", tab }); return; }
    await clients.openWindow(target.href);
  })());
});
