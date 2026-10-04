# 🦙 Copito — Chat multi-modelo sin límites, en un solo HTML

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sin backend obligatorio](https://img.shields.io/badge/backend-opcional-brightgreen)](#)
[![Un solo archivo](https://img.shields.io/badge/app-index.html%20%C3%BAnico-blue)](#)
[![Offline](https://img.shields.io/badge/offline-GGUF%20%2B%20sandbox%20%2B%20VM-orange)](#)
[![Endpoint](https://img.shields.io/badge/endpoint-OpenAI%20%2B%20Anthropic%20%3A20666-purple)](#)

Copito es un cliente de chat **autocontenido** (un solo `index.html`) con **ruteo inteligente tipo OmniRoute**, **generación de imágenes FLUX**, **entornos de ejecución desatendidos** (sandbox JS, Pyodide, VM Linux embebido), **modo agéntico 🤖** con auto-verificación, y un **endpoint local OpenAI/Anthropic en :20666** que expone tu GGUF del navegador a clientes externos (incluido **Claude Code**).

> Un archivo. Cero servidores obligatorios. Chatea al instante con tu GGUF local. Y si quieres API para Claude Code, `copito.bat`/`copito.sh` ya te la dan.

---

## ⚡ Qué funciona al abrir Copito (honesto, sep-2026)

| Quiero… | Cómo |
|---|---|
| Chatear **al instante y offline** | Carga un GGUF con **📂** → wllama responde en 10–25 tok/s (CPU, KV f16) |
| Chatear **online sin keys** | **AI Horde** anónimo responde en ~20–40 s (único endpoint remoto sin key que sigue vivo) |
| Chatear **rápido y con calidad** | Añade **Groq / Cerebras / Gemini / OpenRouter** con 🔑 Key gratis → 📥 Pegar |
| **API para Claude Code** | 🌐 Endpoint → Iniciar → `ANTHROPIC_BASE_URL=http://127.0.0.1:20666` |
| Que el agente **ejecute y verifique código solo** | Activa **🤖** → genera → corre en sandbox/VM → resultado verificado |
| **Imágenes** | 🎨 FLUX vía `image.pollinations.ai` (puede requerir token hoy; si falla, usa tu custom) |

### Estado real de los motores zero-config remotos

| Motor | Estado | Motivo |
|---|---|---|
| **AI Horde** | ✅ Vivo | Anónimo, ~20–40 s |
| Pollinations (texto) | ❌ Muerto | Exige Cloudflare Turnstile (403) |
| DuckDuckGo AI | ❌ Muerto | Preflight CORS del token VQD bloqueado |
| Puter.js | ❌ Muerto | Ahora pide cuenta con teléfono |
| LLM7.io | ❌ Muerto | Rechaza anónimos (400) |
| UncloseAI / KiloAI | ❌ Muerto | Dominios sin resolver DNS |
| HuggingFace Inference (legacy) | ❌ Muerto | Migró a `router.huggingface.co` (requiere token) |

Copito trae estos muertos **desactivados por defecto** (con su cliente intacto por si reviven) y **circuit breakers**: un motor que falla (403/404/DNS/timeout) entra en **cooldown 2 min** y se salta; un cupo agotado (402/429), **cooldown 15 min** + traspaso de sesión. Por eso la rotación no quema tiempo reintentando lo muerto.

---

## 🧠 GGUF local en el navegador (Wllama) — tu mejor zero-config

Carga `.gguf` desde tu disco (**📂**) o desde `modelos/` / HuggingFace / URL. Inferencia **100% offline** en **CPU**, **WebGPU** o **🧩 Split**.

- **Runtime wllama 3.6.1** (el de la carpeta `./wllama/3.6.1/`). Es el unico con **WebGPU**: el 2.x forcea `n_gpu_layers: 0` en el worker y **anula la GPU**, ademas de no tener `flash_attn`. Por eso la carpeta versionada tiene prioridad sobre la plana, y si una base no trae WebGPU se descarta.
- **KV cache segun el modo**: `f16/f16` en CPU (con `flash_attn:false`), y `q8_0/q8_0` + `flash_attn:true` en GPU/split (llama.cpp exige flash para cache cuantizado en V).
- **Hilos = nucleos fisicos, no logicos.** Medido en un i9-12900HK (14C/20T): 1 -> 3.96 tok/s, 8 -> 12.17, **14 -> 14.70**, 20 -> **13.48**. El hyperthreading se pelea, asi que por defecto usa `round(hardwareConcurrency x 0.7)`. Se puede fijar a mano con *Hilos CPU* (`0` = automatico).
- **`n_ubatch` segun tamano y modo**: 256 en CPU, 512 en GPU, y **256 para 7B+** (un 7B en GPU revienta el compute buffer con 512).
- **`cont_batching: false`** por defecto: medido mas rapido generando de un mensaje cada vez (15.1 vs 9.75 tok/s).
- **Vision con `mmproj`**, verificada de extremo a extremo con **SmolVLM-256M-Instruct**: `modelos/SmolVLM-256M-Instruct-Q8_0.gguf` + `modelos/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf` (167 + 99 MB). El `mmproj` se pone por **ruta** en el campo *mmproj*, no con el selector 📎 (ese mete el fichero entero en la RAM del navegador). Soporte **MoE** (OLMoE, Qwen1.5-MoE, JetMoE).
- **Vision: tres cosas que hay que saber, todas medidas**
  1. **El GGUF necesita `tokenizer.chat_template`.** Sin el, wllama arma mal el prompt, ignora el marcador de imagen y el modelo devuelve **0 tokens** al instante. Todos los Q4 de Moondream2 que existen en HuggingFace **no lo traen**; solo el F16 de 2.64 GB (`moondream2-text-model-f16_ct-vicuna.gguf`, el prefijo `_ct-` significa "chat template"). Para revisarlo antes de descargar: los primeros 12 MB del GGUF bastan, `chat_template` esta en el metadata inicial.
  2. **Con `mmproj` el dispositivo se fuerza a GPU.** En CPU pura el encoder de imagen **se cuelga**: se para en `clip_encode: copying image 1/1 to input buffer` y no sale nunca (>4 min, reproducible), aunque el texto-only del mismo modelo vaya a 14 tok/s. No es lentitud, es que el grafo del encoder no termina. En cuanto `n_gpu_layers > 0` responde en ~3.5 s.
  3. **wllama 3.x no entiende `image_url`.** Su `prepareMultimodalInput` hace `files.push(c.data)`: espera los **bytes** de la imagen en `content[].data`. Copito convierte la imagen a `Uint8Array` antes de llamar (`wllamaImgBytes` / `resolverImagenesWllama`); con el formato viejo falla siempre con *"Failed to load image or audio file"*.
- **Chrome corta cualquier fichero OPFS en 2000 MiB.** MEDIDO en origen limpio y con la cuota recién concedida (2025 MB libres): se escribieron 2.491.872.272 bytes y el fichero quedó en **2.097.152.000 = 2000 MiB exactos, sin lanzar ningún error**. Repetido con dos ficheros distintos: no es falta de RAM ni de cuota. Por tanto **un GGUF de más de 1953 MiB no se puede cargar por URL en ningún caso**: la copia queda truncada en silencio y llama.cpp protesta con `tensor ... data is not within the file bounds`, un error que no menciona el tamaño. Por eso los modelos de más de 2 GB (Phi-4-mini 2376, OLMoE 2444, los 7B, el 9B) **solo cargan con el botón 📂 Archivo local**, que entrega un `File` respaldado por disco y no pasa por OPFS.
- **Los GGUF locales se cargan por dos caminos, según el tamaño:**
  - **Ruta Blob** (`fetch` → `Blob` → `loadModel`): **no toca OPFS, 0 MB de cuota** (verificado). Pero mete el GGUF entero en la memoria del navegador. MEDIDO con 6.3 GB de RAM libres: 1117 MB ✅, 1500 MB ❌, 2376 MB ❌, siempre con `Failed to fetch` — que `fetch` no distingue de un error de red.
  - **Ruta OPFS** (`loadModelFromUrl`): escribe a **disco por streaming, sin gastar RAM**, pero **ocupa la cuota del navegador de forma permanente**: no la devuelven `unloadWllama()`, ni borrar la entrada de OPFS, ni recargar. Solo *Clear site data*.
  - Copito mide el tamaño por `HEAD` y elige: hasta **~1.1 GB** va por Blob (los pequeños no queman cuota), por encima va por OPFS, y por encima de **1953 MiB** avisa de que hace falta el botón 📂. El umbral se ajusta con el heap real (`jsHeapSizeLimit × 0.35`, medido 4192 MB aquí).
- **Comprobación previa de espacio**: antes de una descarga por URL se mira la cuota libre y el tamaño real (HEAD). El pico de espacio es **~2x** el del modelo, porque `createWritable()` pasa antes por un fichero temporal (medido: un modelo de 2376 MB necesita 4753 MB libres). Si no cabe, avisa en **0 s** con el motivo y los pasos, en vez de esperar varios minutos y petar con un error inútil.
- **Carga tolerante a rutas**: prueba `./wllama/3.6.1/`, luego `./wllama/`, y por ultimo CDN; valida magic bytes `\0asm` + tamano del wasm, y **pregunta al `index.js` si trae WebGPU** antes de elegirlo.
- **Lock anti-doble-carga** (`wllamaLock`, con tope de espera) y **probe** que valida que el modelo genera antes de darlo por bueno.
- **`split` con modelos grandes se avisa, no se cuelga en silencio**: timeout de 4 min explicando el motivo real (los cruces CPU/GPU serializan el calculo) y recomendacion de usar `gpu` o `auto`.
- **`exit()` con tiempo maximo**: si el worker de wasm aborta (`GGML_ASSERT`), `exit()` se queda colgado y dejaba el lock bloqueado para siempre. Ahora hay timeout y reseteo forzado, y el boton *Soltar modelo* siempre responde.
- **Un fallo de GPU ya no degrada el dispositivo**: antes un solo timeout ponia `wllamaDevice=cpu` **y lo guardaba** en la config. Ahora solo afecta a esa carga.

**Recomendación:** copia `Llama-3.2-1B-Instruct-Q4_K_M.gguf` (~760 MB) a `modelos/` y deja `wurl = modelos/Llama-3.2-1B-Instruct-Q4_K_M.gguf` en la tarjeta wllama. Copito lo auto-carga al arrancar (bajo http) y chateas sin internet.

### Limite duro: 4 GiB en WebAssembly32

El espacio de direcciones de wasm32 es 4 GiB, y eso limita **solo a los pesos que quedan en la RAM de la CPU**:

| Modo | Donde caen los pesos | Cabe un 7B Q4 (4.36 GiB)? |
|---|---|---|
| `cpu` | RAM de wasm32 | **No**: no entra en 4 GiB |
| `split` | Reparto GPU/CPU | **No en la practica** (ver abajo) |
| `gpu` | VRAM | **Si** |

**Sobre `split`:** el reparto en sí es válido, pero en la práctica **no termina la carga** con modelos grandes. En split el grafo se parte en trozos CPU/GPU y cada cruce serializa el cálculo; subir capa a capa los pesos de 4.36 GiB por WebGPU desde el navegador tarda tanto que parece un cuelgue (medido: seguía colgado a los 200 s). Por eso Copito pone un aviso al elegirlo y un timeout de 4 min explicando que use `gpu` o `auto`. Con iGPU, `gpu` puro es mejor que `split` en cualquier caso.

### Como leer las metricas

El panel muestra **tok/s de generacion** y el **prefill aparte**:

```
14.2 tok/s . 84 tokens . 11.4s . prefill 0.66s
     ^ generado          ^ total ^ espera antes del primer token
```

El prefill (leer el prompt) va mucho mas rapido en GPU: medido **3.6x** (170 tok: 6.6 s -> 1.8 s). Si ves el total muy por debajo del de generacion, el problema es el historial, no el modelo: bajala con **Ruteo -> Presupuesto de prefill**.

**Techo de respuesta:** Ruteo -> *Techo GGUF local* (por defecto 1024). Antes `max_tokens` se derivaba de `n_ctx` y daba 3840 tokens, que a ~14 tok/s son **274 s** por respuesta. El campo *Longitud max de respuesta* ahora si manda.

### Rendimiento real esperado

En un i9-12900HK con el 1B Q4 y WebGPU: **~13-15 tok/s** de generacion, prefill de ~0.5 s con prompt corto. Si necesitas 40-60 tok/s, el limite no es Copito sino **WebAssembly**: ejecuta el mismo GGUF con `llama-server` u Ollama y conectalo por el endpoint OpenAI de `:20666`.

---

## 🐧 Entornos de ejecución desatendidos

| Entorno | Disponible | Hace |
|---|---|---|
| **Sandbox JS** (Worker) | Siempre, offline | Ejecuta JavaScript, lee stdout/errores |
| **Bash simulado** | Siempre, offline | `ls cd pwd cat echo mkdir rm cp mv find grep head tail wc date env…` sobre mini-filesystem |
| **Pyodide (Python)** | Offline con `./pyodide/`; online vía CDN | Python + **pip** (`micropip.install`) |
| **VM Linux real (v86)** | Offline con `./v86/` | Shell por puerto serial; `apt/npm/git` si la imagen los trae |

Terminal colapsable **🐧** (cerrado por defecto). En modo **🤖**, si la tarea requiere pruebas, el agente genera código → lo ejecuta → lee la salida → se auto-corrige (hasta 2 intentos) → entrega resultado **verificado**.

---

## 🌐 Endpoint local OpenAI/Anthropic (:20666)

`copito.bat` (Windows, C# embebido) y `copito.sh` (macOS/Linux, Perl core) son el **mismo relé**: escuchan en `:8080` (web + admin) y `:20666` (API). El navegador (Copito) **genera** con su wllama/proveedores y el server **re-empaqueta** los deltas como SSE OpenAI o Anthropic. Así Claude Code habla con tu GGUF del navegador.

Ciclo real (contrato que cumple el `index.html`):
```
Claude Code ─/v1/messages─▶ server:20666 ─/__copito/poll─▶ navegador (Copito)
                                  ▲                              │
                                  └─/__copito/chunk|done|error───┘
```
- El navegador publica su modelo cargado con `POST /__copito/config {enabled,api_key,model}`.
- `GET /__copito/poll` (long-poll 25 s) entrega el job ya convertido Anthropic→OpenAI.
- El navegador envía `POST /__copito/chunk` por delta y `/__copito/done` o `/__copito/error` al cerrar.
- `/v1/chat/completions` (stream y no-stream) y `/v1/messages` (stream y no-stream) los traduce el server.
- Headers **COOP `same-origin` + COEP `credentialless`** → habilitan `SharedArrayBuffer` → wllama multi-hilo.

**Conectar Claude Code** (con `copito.bat`/`copito.sh` corriendo y 🌐 Endpoint → Iniciar):
```bat
set ANTHROPIC_BASE_URL=http://127.0.0.1:20666
set ANTHROPIC_API_KEY=lo-que-pusiste   (o cualquier string si la dejaste vacía)
set ANTHROPIC_MODEL=copito-local
claude
```
`ANTHROPIC_MODEL` admite prefijo de proveedor para fijarlo: `groq:llama-3.1-8b-instant`, `openrouter:deepseek/deepseek-chat-v3-0324:free`. Sin prefijo, el navegador rota solo (priority: wllama → keyless vivos → custom con key).

⚠️ El server escucha en `0.0.0.0` (toda tu LAN). Pon **API key** en el modal 🌐 o abre firewall solo si hace falta (botón 🔥 en 🛠 Server).

**Limitación honesta:** la pestaña de Copito debe estar **abierta y viva** (por eso hay "Pestaña mantenida viva", un Worker que hace ping a `/health`). Si cierras Copito, el bridge no tiene quién genere. Eso es inherente a "el navegador genera".

---

## 🔀 Ruteo tipo OmniRoute (replicado en el navegador)

- **🔀 Auto** con estrategias `priority` (local/keyless primero) / `round-robin` / `least-used` / `random`.
- **Circuit breaker** por motor (2 min muertos / 15 min cupos) + **context-relay**: compacta la conversación y continúa en otro modelo sin perder el hilo.
- **Proxies CORS encadenados** (directo → corsproxy.io → allorigins) para los pocos endpoints que aún los aceptan.
- **Warmup silencioso** al arrancar (precalienta DNS/TLS de AI Horde).

---

## 🔑 Auto-keys (opcional, para más potencia)

Con 🔑 Key gratis → 📥 Pegar (lee portapapeles, guarda local, prueba solo): **Groq, Cerebras, Gemini (AI Studio), OpenRouter (`:free`), Mistral, GitHub Models, NVIDIA NIM, Together, Cloudflare Workers AI, HuggingFace Router, Cohere, Fireworks, DeepInfra**, y **tu propio gateway OpenAI-compatible / OmniRoute remoto** como endpoint `custom`. Nada obligatorio: sin keys ya chateas con wllama + AI Horde.

---

## 🧰 Botones

| Botón | Hace |
|---|---|
| `➤ / Enter` | Enviar · `⏹` detener · `Shift+Enter` salto |
| `🔀 Auto` (selector) | Rota proveedores/modelos |
| `📂` | Carga GGUF local (offline) |
| `🌐` | Endpoint :20666 (OpenAI/Anthropic, Claude Code) |
| `🛠` | Administración del server (firewall, instalar, reparar, empaquetar, inicio-auto) |
| `🐧` | VM Linux embebido |
| `🤖` | Modo agéntico (4 roles + entorno + auto-corrección) |
| `🎨` | FLUX (imágenes) |
| `🔍/` | Búsqueda web (Google/Bing/DDG) inyectada al modelo |
| `🔒/🔓` | Modo franco (tono directo) |
| `🧠` | Memoria del chat (MD/JSON, descargar) |
| `⬇` | Exportar (MD/JSON/CSV/PDF/Word/PPT) |
| `🧑 Humanizar` | Reescribe con tono natural |
| `📎` | Adjuntar imagen/texto/Word/Excel/PPT/PDF |

**Atajos:** `Esc` cierra · `Ctrl+S` guarda config.

---

## 📦 Setup offline (una sola vez, desde 🛠 Server)

Los botones del panel **🛠 Server** le mandan órdenes al propio `copito.bat`/`copito.sh` (puerto 8080, solo tu máquina). No hay comandos de consola:

- 📦 **Instalar todo offline** → descarga `wllama/`, `v86/`, `pyodide/` a carpetas locales.
- 🧩 / 🐧 / 🐍 → solo wllama / v86 / pyodide.
- 🔧 **Reparar wllama.wasm** → re-descarga y valida el wasm (magic bytes + tamaño).
- 🔥 **Abrir firewall** → reglas `netsh` para 8080/20666 (Windows, pide UAC).
- 🗜 **Empaquetar portable** → `copito-portable.zip` con todo **excepto `modelos/`**.
- 🔁 **Inicio automático** → registro/launchd/autostart.

En Windows los jobs de admin son **asíncronos** (`{jobId}` → el panel sondea `/admin/job?id=`); en Unix son **síncronos** (`{done,log,result}`). El panel maneja ambos. Tras el setup, los componentes viven en `wllama/`, `v86/`, `pyodide/` y funcionan **sin internet**.

---

## 🚀 Uso

### Opción A — Local (recomendado, desbloquea todo)
```bash
copito.bat        # Windows (doble clic)
./copito.sh       # macOS/Linux
```
Abre `http://localhost:8080`. Servido por HTTP se desbloquean CORS, el VM, el bridge :20666 y el auto-load de `modelos/`.

### Opción B — Doble clic en `index.html` (`file://`)
Funcionan **wllama local**, **AI Horde** y tu **custom**. El bridge :20666, los proxies CORS y el VM quedan limitados (Copito te lo avisa en la barra de estado).

### Opción C — GitHub Pages
```bash
git init && git add . && git commit -m "Copito"
git branch -M main && git remote add origin https://github.com/TU_USUARIO/copito.git && git push -u origin main
# Settings → Pages → Source: main → / (root)
```

---

## 🗂 Estructura

```
copito/
├── index.html            ← la app completa (un solo archivo, 7 bloques coherentes)
├── sw.js                 ← PWA offline (NO toca el bridge ni los .gguf)
├── copito.bat            ← server Windows (C# embebido) :8080 + :20666   [YA ENCAJA con index.html]
├── copito.sh             ← server macOS/Linux (Perl core) :8080 + :20666  [YA ENCAJA con index.html]
├── README.md · LICENSE · .gitignore
├── docs/img/             ← capturas
├── wllama/ · v86/ · pyodide/   ← componentes offline (tras  Instalar)
└── modelos/              ← tus .gguf (NO se sube a GitHub)
```

> **Nota importante sobre `copito.bat`/`copito.sh`:** ya implementan el contrato exacto que consume este `index.html` (`/__copito/poll|chunk|done|error|config`, `/__copito/admin/*`, `/v1/chat/completions`, `/v1/messages`, `/health`, COOP+COEP). **No requieren cambio** para funcionar con la app nueva. Si algún día ves un volcado/copia de estos archivos con espacios raros dentro de palabras o cadenas (`pub lic`, `"127.0.0.1 "` con espacio, `\r\n` convertido a saltos en el `.sh`), son **artefactos de la copia**, no del original: el original funciona. Verifica esas cadenas antes de "arreglar" nada.

---

## 🔒 Privacidad

Keys y configuración **solo en tu navegador** (localStorage/cookie). GGUF, entornos y VM **nunca salen de tu máquina**. Sin telemetría, sin trackers. El bridge :20666 es local/LAN y opcional.

---

## 📜 Licencia

**MIT** — uso, modificación y distribución libres, incluso comercial. Ver [LICENSE](LICENSE).
