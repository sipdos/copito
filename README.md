# 🦙 Copito — Chat multi-modelo sin límites, en un solo HTML

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sin backend](https://img.shields.io/badge/backend-ninguno-brightgreen)](#)
[![Un solo archivo](https://img.shields.io/badge/archivo-%C3%BAnico%20index.html-blue)](#)
[![Offline](https://img.shields.io/badge/offline-GGUF%20%2B%20sandbox%20%2B%20VM-orange)](#)
[![Ruteo](https://img.shields.io/badge/ruteo-OmniRoute%20style-purple)](#)

Copito es un cliente de chat **autocontenido** (un solo `index.html`) con **ruteo inteligente tipo OmniRoute** (rotación, circuit-breaker, traspaso de sesión y compactación), **modelos GGUF locales en el navegador** (incluidos **MoE**), **entornos de ejecución embebidos** para que el agente pruebe su propio código **desatendido**, y una cadena de **motores sin key** que se auto-diagnostica: los que mueren entran en cooldown y Copito salta al siguiente vivo.

> **Ábrelo por `http://` (no `file://`), escribe y chatea.** Lo demás es opcional.

---

## 🚀 Chatea al primer segundo: las 3 vías reales

| Vía | Cómo | Velocidad | Requiere |
|---|---|---|---|
| **1. GGUF local (recomendada)** | 📂 → elige tu `.gguf` (o déjalo en `modelos/` y pon la ruta en ⚙️ → Wllama) | **1-3 s**, offline total | nada (una sola carga) |
| **2. AI Horde (sin key)** | Ya activo por defecto en modo `🔀 Auto` | ~20-40 s (cola comunitaria) | internet |
| **3. Endpoint propio / OmniRoute** | ⚙️ → `+ Añadir endpoint OpenAI-compatible` (p.ej. tu OmniRoute en `http://localhost:20128/v1`) | 1-5 s | internet o LAN |

Con cualquiera de las tres, **el primer mensaje entra sin configurar keys ni wizard**. Copito además precarga y rota: si un motor falla, rota al siguiente y lo pone en *cooldown* para que el siguiente mensaje ya no pierda tiempo.

### ⚠️ Realidad de los endpoints "sin key" (septiembre 2026)

Los endpoints públicos anónimos **mueren rápido**. Estado verificado en vivo desde Copito:

| Motor | Estado | Motivo |
|---|---|---|
| **AI Horde** (anónimo ≤512 tok) | ✅ **VIVO** | Cola comunitaria; lento pero fiable |
| **Pollinations** | ❌ muerto | Ahora exige CAPTCHA Turnstile (`403 Missing Turnstile token`) |
| **DuckDuckGo AI (Duck.ai)** | ❌ muerto desde navegador | Token VQD + anti-bot; los proxies CORS no pasan el preflight |
| **Puter.js** | ❌ ya no anónimo | Pide cuenta/verificación de teléfono |
| **LLM7.io** | ❌ muerto | `400 Bad Request` a clientes anónimos |
| **HF Inference anónimo** | ❌ deprecado | `api-inference.huggingface.co` retirado (migró a `router.huggingface.co`, con token) |

Por eso Copito los trae **desactivados por defecto** y con *circuit-breaker*: si algún día reviven (o activas uno manualmente en ⚙️), entran a la rotación; si mueren, cooldown automático de 2-15 min y rotación al siguiente. **La magia no depende de que un servidor gratuito siga vivo: depende de tu GGUF local o de tu endpoint.**

> 💡 ¿Quieres un motor local **rápido y sin archivos grandes**? La siguiente integración prevista es **WebLLM** (WebGPU, descarga el peso una vez y luego va offline a decenas de tok/s). Pídela o revisa los issues.

---

## 📸 Capturas

| | |
|:---:|:---:|
| ![Chat](docs/img/01-chat-gguf.png) | ![Ruteo](docs/img/02-ruteo.png) |
| *Chat con GGUF local, métricas tok/s y código coloreado* | *Panel de ruteo con tarjetas por motor y auto-keys* |
| ![Terminal](docs/img/03-terminal.png) | ![Agéntico](docs/img/04-agentico.png) |
| *Terminal colapsable: el agente ejecuta y verifica solo* | *Ciclo agéntico con entorno de ejecución* |

> Genera las capturas con `F12` → `Ctrl+Shift+P` → *"Capture full size screenshot"* y guárdalas en `docs/img/`.

---

## 🐧 Entorno de desarrollo y pruebas en el navegador

Copito incluye **entornos de ejecución embebidos** que el **modo agéntico 🤖 usa solo**: escribe código, lo ejecuta, lee la salida, se auto-corrige (hasta 2 intentos) y entrega el resultado **verificado**. Tú no tocas nada.

| Entorno | Disponibilidad | Capacidades |
|---|---|---|
| **Sandbox JS** (Worker aislado) | Siempre, offline | Ejecuta JavaScript, lee `console.log`/errores |
| **Bash simulado** | Siempre, offline | `ls cd pwd cat echo mkdir rm cp mv find grep head tail wc date env…` sobre un mini-filesystem |
| **Pyodide (Python)** | Offline con `./pyodide/`; online vía CDN | Python completo + **pip** (`micropip.install`, `loadPackage`) |
| **VM Linux real (v86)** | Offline con `./v86/` | Shell real por puerto serial, desatendida; `apt/npm/git` si tu imagen los trae |

- **Offline:** sandbox JS + bash simulado (+ Pyodide si hiciste su setup).
- **Online:** se suma Pyodide vía CDN; y si pulsas 🐧, la VM Linux real.
- **Terminal colapsable 🐧:** cerrado por defecto; ábrelo con la flechita solo para *ver* al agente trabajar (incluida la pantalla del VM).

**Prueba:** activa 🤖 y pide *"verifica cuántos primos hay menores de 10000 y muéstrame los 5 últimos"* o *"crea un archivo y lista la carpeta"*.

---

## 🧠 Modelos soportados (incluye MoE)

Copito corre **cualquier GGUF** soportado por llama.cpp/wllama, incluidos **Mixture-of-Experts**:

- **MoE recomendados:** `OLMoE-1B-7B-Instruct` (7B totales / 1B activos: velocidad de modelo chico, calidad superior), `Qwen1.5-MoE-A2.7B`, `JetMoE-8B`.
- **Densos recomendados:** Llama-3.2-1B/3B, Qwen2.5-1.5B, SmolLM2-1.7B, Phi-4-mini.
- **Con visión:** Qwen2-VL-2B o Moondream2 + su archivo `mmproj` (el modelo "ve" tus imágenes).

Inferencia en **CPU**, **WebGPU** o **🧩 Split GPU+CPU** (capas repartidas, `n_gpu_layers` configurable), hilos ajustables, watchdog con auto-fallback a CPU, y validación de integridad del runtime wasm.

---

## 🔀 Ruteo tipo OmniRoute

- **🔀 Auto:** rota motores y modelos según estrategia (`priority`, `round-robin`, `least-used`, `random`).
- **Circuit-breaker:** 402/429/403/404 o timeout → *cooldown* (2-15 min) y rotación inmediata al siguiente.
- **Traspaso de sesión:** si un motor se corta a mitad, Copito **compacta el contexto (context-relay)** y continúa la misma conversación en el siguiente motor.
- **Métricas persistentes:** `⚡ tok/s · tokens · segundos` por respuesta, guardadas en el historial.

---

## 🧰 Guía de botones (sin complicaciones)

| Botón | Qué hace | Cuándo |
|---|---|---|
| `➤ / Enter` | Envía | siempre |
| `🔀 Auto` | Rota motores solo | por defecto |
| `📂` | Carga GGUF local | para offline/instantáneo |
| `🐧` | Arranca/oculta la VM Linux | solo si el agente necesita `apt/npm/git` reales |
| `🤖` | Modo agéntico (4 roles + entornos) | tareas de razonar-probar-verificar |
| `🔍/` | Búsqueda web (Google/Bing/DDG) inyectada al modelo | datos de actualidad |
| `🔒/` | Modo franco (tono directo) | cuando quieras crudeza; combina con GGUF *abliterated* |
| `🧠` | Ver/descargar memoria del chat | auditar o respaldar |
| `⬇ Exportar` | MD / JSON / CSV / PDF / Word / PowerPoint | llevarte la conversación |
| `🧑 Humanizar` | Reescribe con tono natural | respuestas robóticas |
| `📎 Adjuntar` | Imágenes, texto, Word, Excel, PPT, PDF | analizar documentos |
| `⏹` | Detiene al instante | respuestas largas |
| `⚙️ Ruteo` | Motores, keys, Split, hilos, contexto | afinar (opcional) |
| `🧙` | Wizard asistido | opcional y repetible |

**Atajos:** `Esc` cierra · `Ctrl+S` guarda · `Shift+Enter` salto de línea.

---

## 🔑 Auto-keys (opcional, para más potencia)

1. `⚙️ Ruteo` → `🔑 Key gratis` en el proveedor (Groq, Gemini, OpenRouter, Cerebras…).
2. Crea y copia tu key en la pestaña oficial.
3. Vuelve y pulsa `📥 Pegar`: se guarda local, activa el motor y lo prueba solo.

**Nada de esto es obligatorio.**

---

## 📦 Setup de componentes offline (una sola vez)

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_wllama.ps1    # runtime GGUF local (wllama 3.6.1)
powershell -ExecutionPolicy Bypass -File .\fix_wllama.ps1      # repara wasm corrupto
powershell -ExecutionPolicy Bypass -File .\setup_pyodide.ps1   # Python offline con pip
powershell -ExecutionPolicy Bypass -File .\setup_v86.ps1       # VM Linux embebida (v86)
```
(Mac/Linux: equivalentes `.sh`.) Tras cada setup, el componente vive en su carpeta y funciona **sin internet**.

### Servir Copito (importante)
```bash
copito_server.bat      # Windows → http://localhost:8080
./copito_server.sh     # Mac/Linux
```
**No abras `index.html` con `file://`:** varios motores, los proxies CORS y el VM requieren `http://`. El GGUF local y tu endpoint propio sí funcionan desde `file://`, pero Copito te avisa.

---

## 🛠 Solución de problemas

| Síntoma | Causa / arreglo |
|---|---|
| Primer mensaje lento (~1 min) | Rotación probando motores muertos → ya mitigado con cooldown; verifica que tu GGUF o custom estén activos |
| `Missing Turnstile token` | Pollinations murió (CAPTCHA): desactívalo en ⚙️ o ignóralo (ya viene off) |
| Popup de Puter pidiendo teléfono | Puter ya no es anónimo: déjalo desactivado |
| `ERR_NAME_NOT_RESOLVED` en algún motor | Endpoint retirado: Copito lo enfría solo; no hace nada |
| Wllama no carga en USB/Red | Copia el `.gguf` a disco interno y usa "URL directa" + ⬇ |
| VM 🐧 no arranca | Ejecuta `setup_v86.ps1` y sirve por `http://` |

---

## 🗂 Estructura del repo

```
copito/
├── index.html            ← la app completa (un solo archivo)
├── sw.js · README.md · LICENSE · .gitignore
├── docs/img/             ← capturas
├── copito_server.bat/.sh ← servidor local (COOP/COEP + Range)
├── setup_wllama.ps1/.sh · fix_wllama.ps1 · setup_pyodide.ps1 · setup_v86.ps1
├── wllama/ · pyodide/ · v86/   ← componentes offline (tras setup)
└── modelos/              ← tus .gguf (NO se sube a GitHub)
```

---

## 🔒 Privacidad

Keys y configuración **solo en tu navegador**. GGUF, sandbox y VM **nunca salen de tu máquina**. Sin telemetría ni backend propio.

## 📜 Licencia

**MIT** — uso, modificación y distribución libres, incluso comercial. Ver [LICENSE](LICENSE).