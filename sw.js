/* MGEO PDF – service worker: app 100% offline + cache dos blocos do Google já vistos */
const VERSION = 'mgeo-pdf-v3';
const SHELL_CACHE = VERSION + '-app';
const TILE_CACHE = 'mgeo-tiles-v1';
const MAX_TILES = 4000;
const SHELL = [
  './', './index.html', './manifest.json',
  './lib/leaflet.js', './lib/leaflet.css',
  './lib/pdf.min.js', './lib/pdf.worker.min.js', './lib/pdf-lib.min.js',
  './icons/icon-192.png', './icons/icon-512.png', './icons/icon-maskable-512.png', './icons/apple-touch-icon.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(SHELL_CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== SHELL_CACHE && k !== TILE_CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

const isTile = u => /(^|\.)google\.com$/.test(u.hostname) && u.pathname.startsWith('/vt');

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (isTile(url)) { e.respondWith(tile(req)); return; }
  if (url.origin === self.location.origin) e.respondWith(app(req, e));
});

let puts = 0;
async function tile(req) {
  const c = await caches.open(TILE_CACHE);
  const hit = await c.match(req);
  if (hit) return hit;
  try {
    const res = await fetch(req);
    if (res.ok || res.type === 'opaque') {
      c.put(req, res.clone());
      if (++puts % 50 === 0) trim(c);
    }
    return res;
  } catch (err) {
    return new Response('', { status: 504 });
  }
}

async function trim(c) {
  const keys = await c.keys();
  for (let i = 0; i < keys.length - MAX_TILES; i++) await c.delete(keys[i]);
}

async function app(req, e) {
  const c = await caches.open(SHELL_CACHE);
  let hit = await c.match(req, { ignoreSearch: true });
  if (!hit && req.mode === 'navigate') hit = await c.match('./index.html');
  const net = fetch(req).then(r => { if (r.ok) c.put(req, r.clone()); return r; }).catch(() => null);
  if (hit) { e.waitUntil(net); return hit; }
  return (await net) || new Response('Offline', { status: 503 });
}
