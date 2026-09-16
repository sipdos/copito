# 🦙 Copito — Chat multi-modelo sin límites, en un solo HTML

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Sin backend](https://img.shields.io/badge/backend-ninguno-brightgreen)](#)
[![Un solo archivo](https://img.shields.io/badge/archivo-%C3%BAnico%20index.html-blue)](#)
[![Offline](https://img.shields.io/badge/offline-GGUF%20%2B%20sandbox%20%2B%20VM-orange)](#)
[![Zero-config](https://img.shields.io/badge/zero--config-chatea%20al%20abrir-success)](#)

Copito es un cliente de chat **autocontenido** (un solo `index.html`) que **chatea desde el primer segundo, sin keys ni registro**, y que además puede **ejecutar y verificar código él solo** en entornos de desarrollo embebidos en el navegador.

> **Ábrelo y escribe.** Eso es todo. Lo demás es opcional y se activa cuando tú quieras.

---

## 🚀 Arranca y chatea (0 configuración)

Al abrir Copito **ya puedes chatear**: usa **Pollinations sin key** con un triple mecanismo de respaldo (POST stream → POST simple → GET simple) que garantiza respuesta inmediata la primera vez. Si Pollinations fallara, rota solo a **AI Horde** (también sin key). **No hay wizard obligatorio, no hay keys que poner, no hay nada que configurar.**

- **Con internet:** chatea al instante con modelos remotos gratuitos.
- **Sin internet:** carga un GGUF local (📂) y chatea 100% offline; los entornos de ejecución (sandbox/VM) también funcionan offline.

---

## 📸 Capturas

| | |
|:---:|:---:|
| ![Chat](docs/img/01-chat-gguf.png) | ![Ruteo](docs/img/02-ruteo.png) |
| *Chat con GGUF local, métricas tok/s y código coloreado* | *Panel de ruteo OmniRoute con auto-keys y Wllama* |
| ![Terminal](docs/img/03-terminal.png) | ![Agéntico](docs/img/04-agentico.png) |
| *Terminal colapsable: el agente ejecuta y verifica solo* | *Ciclo agéntico con entorno de ejecución* |

> Genera las capturas con `F12` → `Ctrl+Shift+P` → *"Capture full size screenshot"* y guárdalas en `docs/img/`.

---

##  Entorno de desarrollo y pruebas en el navegador (sandbox + Linux real)

Copito incluye **entornos de ejecución embebidos** que el **modo agéntico 🤖 usa solo, sin que tú toques nada**: escribe código, lo ejecuta, lee la salida, se corrige y te entrega el resultado **verificado**.

| Entorno | ¿Cuándo está? | Qué puede hacer |
|---|---|---|
| **Sandbox JS** (Worker aislado) | **Siempre, offline** | Ejecutar JavaScript y leer `console.log`/errores |
| **Bash simulado** | **Siempre, offline** | `ls cd pwd cat echo mkdir rm cp mv find grep head tail wc date env…` sobre un mini-filesystem |
| **Pyodide (Python)** | Offline con `./pyodide/`; online vía CDN | Python completo + **pip** (`micropip.install`, `loadPackage`) |
| **VM Linux real (v86)** | Offline con `./v86/` | Shell real por puerto serial; `apt/npm/git` si tu imagen los trae |

- **Offline:** sandbox JS + bash simulado (+ Pyodide si descargaste `pyodide/`).
- **Online:** se suman Pyodide vía CDN y, si arrancas 🐧, la VM Linux con paquetes reales.
- **Terminal colapsable 🐧:** cerrado por defecto; ábrelo con la flechita solo si quieres **ver** al agente trabajar (incluida la pantalla del VM). Si no lo abres, el agente trabaja igual, a ciegas para ti.

**Cómo se usa:** activa 🤖 y pide algo ejecutable, p.ej. *"verifica cuántos primos hay menores de 10000"* o *"crea un archivo y lista la carpeta"*. El agente elige el mejor entorno disponible, ejecuta, y si falla se auto-corrige (hasta 2 intentos) antes de responderte.

---

## 🧠 Modelos soportados (incluye MoE)

Copito corre **cualquier GGUF** que soporte llama.cpp/wllama, incluidos los **Mixture-of-Experts (MoE)**:

- **MoE recomendados:** `OLMoE-1B-7B-Instruct` (7B totales / 1B activos → velocidad de modelo pequeño con calidad superior), `Qwen1.5-MoE-A2.7B`, `JetMoE-8B`.
- **Densos recomendados:** Llama-3.2-1B/3B, Qwen2.5-1.5B, SmolLM2-1.7B, Phi-4-mini.
- **Con visión:** Qwen2-VL-2B o Moondream2 + su archivo `mmproj` (el modelo "ve" tus imágenes).

Los MoE se cargan igual que cualquier GGUF (📂 o URL directa); wllama rutea los expertos internamente. En máquinas con poca RAM, usa `🖥️ CPU` y `n_ctx 2048`.

---

## 🔀 Ruteo tipo OmniRoute

- **🔀 Auto:** rota solo entre proveedores y modelos según la estrategia (`priority`, `round-robin`, `least-used`, `random`).
- **Cupo agotado:** detecta 402/429, aplica cooldown de 15 min y **traspasa tu sesión** al siguiente modelo.
- **Context-relay:** si el contexto crece o un motor se corta, **compacta la conversación** y continúa en otro modelo sin perder el hilo.

---

## 🧰 Guía rápida de cada botón (sin complicaciones)

| Botón | Qué hace | Cuándo usarlo |
|---|---|---|
| `➤ / Enter` | Envía el mensaje | Siempre |
| `🔀 Auto` (selector) | Rota proveedores/modelos solo | Por defecto; déjalo así |
| `📂` | Carga un GGUF local (offline) | Cuando quieras privacidad total o sin internet |
| `🐧` | Arranca/oculta la VM Linux embebida | Solo si el agente necesita `apt/npm/git` reales |
| `🤖` | Modo agéntico (4 roles + entorno de ejecución) | Tareas que requieran razonar, probar y verificar |
| `🔍/🌐` | Búsqueda web (Google/Bing/DDG) inyectada al modelo | Preguntas de actualidad o datos verificables |
| `🔒/🔓` | Modo franco (tono directo, sin moralina) | Cuando quieras crudeza; combina con GGUF *abliterated* |
| `🧠` | Ver/descargar la memoria del chat | Para auditar o respaldar conversaciones |
| `⬇ Exportar` | MD / JSON / CSV / PDF / Word / PowerPoint | Para llevar-te la conversación |
| `🧑 Humanizar` | Reescribe una respuesta con tono natural | Cuando una respuesta suene robótica |
| `📎 Adjuntar` | Imágenes, texto, Word, Excel, PPT, PDF | Para analizar documentos o fotos |
| `⏹` | Detiene la generación al instante | Si una respuesta se alarga |
| `⚙️ Ruteo` | Proveedores, keys, Split GPU+CPU, hilos, contexto | Solo si quieres afinar (opcional) |
| `🧙` | Wizard de configuración asistida | Opcional y repetible |

**Atajos:** `Esc` cierra modales · `Ctrl+S` guarda configuración · `Shift+Enter` salto de línea.

---

## 🔑 Auto-keys (solo si quieres más potencia, opcional)

Copito funciona sin keys, pero si quieres modelos más rápidos o grandes:
1. `⚙️ Ruteo` → pulsa `🔑 Key gratis` en el proveedor (Groq, Gemini, OpenRouter…).
2. Crea y copia tu key en la pestaña que se abre.
3. Vuelve y pulsa `📥 Pegar`: Copito la guarda localmente, activa el proveedor y lo prueba solo.

Nada de esto es obligatorio: **sin keys ya chateas al abrir.**

---

## 📦 Setup de componentes offline (una sola vez)

```bash
powershell -ExecutionPolicy Bypass -File setup_wllama.ps1   # runtime GGUF local
powershell -ExecutionPolicy Bypass -File fix_wllama.ps1     # repara wasm corrupto
powershell -ExecutionPolicy Bypass -File setup_pyodide.ps1  # Python offline con pip
powershell -ExecutionPolicy Bypass -File setup_v86.ps1      # VM Linux embebida
# Mac/Linux: usa los .sh equivalentes
```

Tras cada setup, el componente vive en su carpeta (`wllama/`, `pyodide/`, `v86/`) y funciona **sin internet**.

---

## 🗂 Estructura del repo

```
copito/
├── index.html            ← la app completa (un solo archivo)
├── sw.js · README.md · LICENSE · .gitignore
├── docs/img/             ← capturas
├── copito_server.bat/.sh ← servidor local (COOP/COEP + Range)
├── setup_wllama.* · fix_wllama.ps1 · setup_pyodide.ps1 · setup_v86.ps1
├── wllama/ · pyodide/ · v86/   ← componentes offline (tras setup)
└── modelos/              ← tus .gguf (NO se sube a GitHub)
```

---

## 🔒 Privacidad

Keys y configuración **solo en tu navegador**. GGUF y entornos de ejecución **nunca salen de tu máquina**. Sin telemetría ni backend.

## 📜 Licencia

**MIT** — uso, modificación y distribución libres, incluso comercial. Ver [LICENSE](LICENSE).