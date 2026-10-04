/* Copito service worker - PWA offline SIN tocar el bridge ni la carga por rangos.
   index.html: NETWORK-FIRST (para que editar el archivo surta efecto al recargar).
   wllama/v86/pyodide: NETWORK-FIRST con respaldo en cache (era cache-first y servia
   para siempre un wllama 2.x viejo aunque ya se hubiera reparado en disco).
   NUNCA interceptar /__copito/*, /v1/*, /health, POST, Range ni .gguf. */
'use strict';

var VERSION = 'copito-v14';
var SHELL_CACHE   = VERSION + '-shell';
var RUNTIME_CACHE = VERSION + '-runtime';

var SHELL_ASSETS = ['./', './index.html', './sw.js'];
var RUNTIME_PREFIXES = ['wllama/', 'v86/', 'pyodide/'];
var RUNTIME_EXT = ['.js', '.mjs', '.wasm', '.json', '.bin', '.iso', '.css'];

function isRuntimeLocal(pathname){
  for(var i=0;i<RUNTIME_PREFIXES.length;i++){
    if(pathname.indexOf('/' + RUNTIME_PREFIXES[i]) === 0 || pathname.indexOf(RUNTIME_PREFIXES[i]) === 0) return true;
  }
  var dot = pathname.lastIndexOf('.');
  if(dot === -1) return false;
  var ext = pathname.slice(dot).toLowerCase();
  for(var j=0;j<RUNTIME_EXT.length;j++){ if(ext === RUNTIME_EXT[j]) return true; }
  return false;
}

function mustPassthrough(req, url){
  if(req.method !== 'GET') return true;
  if(req.headers.has('range')) return true;
  var p = url.pathname;
  if(p.indexOf('/__copito') === 0) return true;
  if(p.indexOf('/v1') === 0) return true;
  if(p === '/health') return true;
  if(p.indexOf('/modelos') === 0) return true;
  if(/\.gguf$/i.test(p)) return true;
  if(url.origin !== location.origin) return true;
  return false;
}

self.addEventListener('install', function(e){
  e.waitUntil(
    caches.open(SHELL_CACHE).then(function(c){ return c.addAll(SHELL_ASSETS); })
      .then(function(){ return self.skipWaiting(); })
      .catch(function(err){ console.warn('[sw] install parcial:', err && err.message); })
  );
});

self.addEventListener('activate', function(e){
  e.waitUntil(
    caches.keys().then(function(keys){
      return Promise.all(keys.map(function(k){
        if(k !== SHELL_CACHE && k !== RUNTIME_CACHE) return caches.delete(k);
        return null;
      }));
    }).then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener('message', function(e){
  if(e.data && e.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', function(e){
  var req = e.request;
  var url;
  try{ url = new URL(req.url); }catch(_){ return; }
  if(mustPassthrough(req, url)) return;

  /* index.html / navegacion: NETWORK-FIRST. Si la red falla, cae a cache.
     Esto es lo que evita el bug del SW sirviendo un index.html viejo. */
  if(req.mode === 'navigate' || /index\.html$|^\/$/.test(url.pathname)){
    e.respondWith(
      fetch(req).then(function(res){
        if(res && res.ok){
          var copy = res.clone();
          caches.open(SHELL_CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
        }
        return res;
      }).catch(function(){
        return caches.match(req, {ignoreSearch:true});
      })
    );
    return;
  }

  /* runtime local (wllama/v86/pyodide): NETWORK-FIRST con respaldo en cache.
     BUG ARREGLADO: antes era cache-first ("return cached || network"), asi que un
     wllama.wasm / index.js viejo cacheado se servia para siempre y ni "Reparar
     wllama.wasm" ni editar el disco cambiaban nada. La red manda; la cache solo
     entra si no hay servidor. */
  if(isRuntimeLocal(url.pathname)){
    e.respondWith(
      fetch(req).then(function(res){
        if(res && res.ok){
          var copy = res.clone();
          caches.open(RUNTIME_CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
        }
        return res;
      }).catch(function(){
        return caches.match(req, {ignoreSearch:true});
      })
    );
    return;
  }

  /* resto de GET locales: red con cache de respaldo */
  e.respondWith(
    fetch(req).then(function(res){
      if(res && res.ok){
        var copy = res.clone();
        caches.open(RUNTIME_CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
      }
      return res;
    }).catch(function(){
      return caches.match(req);
    })
  );
});