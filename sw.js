let ggufFile = null;
let mmprojFile = null;

self.addEventListener('install', e => {
  self.skipWaiting();
  e.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', e => {
  e.waitUntil(self.clients.claim());
});

self.addEventListener('message', e => {
  if(!e.data) return;
  if(e.data === 'SKIP_WAITING'){ self.skipWaiting(); return; }
  if(e.data.type === 'SET_GGUF') ggufFile = e.data.file;
  if(e.data.type === 'SET_MMPROJ') mmprojFile = e.data.file;
});

self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);
  if(url.pathname.startsWith('/__copito_gguf__') && ggufFile){
    e.respondWith(servirRange(e.request, ggufFile));
  }else if(url.pathname.startsWith('/__copito_mmproj__') && mmprojFile){
    e.respondWith(servirRange(e.request, mmprojFile));
  }
});

async function servirRange(req, file){
  const range = req.headers.get('Range');
  if(!range){
    return new Response(file, {headers:{'Accept-Ranges':'bytes','Content-Length':String(file.size)}});
  }
  const m = /bytes=(\d*)-(\d*)/.exec(range);
  const start = (m && m[1]) ? parseInt(m[1],10) : 0;
  const end = (m && m[2]) ? parseInt(m[2],10) : file.size - 1;
  const slice = file.slice(start, end + 1);
  return new Response(slice, {status:206, headers:{
    'Content-Range':'bytes ' + start + '-' + end + '/' + file.size,
    'Accept-Ranges':'bytes',
    'Content-Length':String(slice.size)
  }});
}