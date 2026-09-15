# 🦙 Copito — Chat multi-modelo sin límites, en un solo HTML

Copito es un cliente de chat **autocontenido** (un solo `index.html`) con **ruteo inteligente tipo OmniRoute**: rota y combina proveedores de IA (sin key, con key gratuita, endpoints OpenAI-compatible propios y **modelos GGUF locales en el navegador**) preservando tu sesión y traspasándola de un modelo a otro sin que notes el cambio. Además integra **entornos de ejecución** para que el agente pruebe su propio código de forma **desatendida**.

> **Un archivo. Cero servidores obligatorios. Cero cuentas obligatorias.** Ábrelo y chatea.

---

## ✨ Características principales

### 🔀 Ruteo tipo OmniRoute
- **Auto-selección de modelo**: el modo `🔀 Auto` rota solo entre todos los proveedores y modelos activos según la estrategia elegida.
- **Estrategias configurables**: `priority` (keyless primero), `round-robin`, `least-used`, `random`.
- **Detección de cupo agotado**: reconoce 402/429/"budget exceeded" y aplica *cooldown* de 15 min por modelo.
- **Preservación y traspaso de sesión**: si un modelo se agota o falla a mitad de conversación, Copito **compacta el contexto (context-relay)** y **continúa la misma sesión en el siguiente modelo disponible**, sin perder el hilo.
- **Compactación automática**: al crecer el contexto o agotarse un cupo, resume la conversación y conserva los últimos mensajes.

### 🔑 Auto-keys y configuración asistida
- **Wizard inicial 🧙**: configuración guiada, opcional y repetible.
- **Auto-keys**: `🔑 Key gratis` abre la página oficial del proveedor y `📥 Pegar` lee tu key del portapapeles, la guarda localmente, activa el proveedor y prueba el endpoint en un clic.
- **Zero-config real**: sin tocar nada ya funciona con **Pollinations + AI Horde** (sin key ni registro).

### 🧠 GGUF local en el navegador (Wllama)
- Carga modelos `.gguf` desde tu disco (**📂 Archivo local**, método Blob sin Service Worker) o desde `modelos/` / HuggingFace / URL directa.
- Inferencia **100% offline** en **CPU**, **WebGPU** o **🧩 Split GPU+CPU** (capas repartidas, `n_gpu_layers` configurable).
- **Hilos CPU configurables** (`wthr`) y batches adaptativos al tamaño del modelo y a tu RAM.
- **Visión local con `mmproj`**: el modelo "ve" tus imágenes (Qwen2-VL, Moondream…).
- Detección automática de iGPU débil (Intel integrada) y *watchdog* con auto-fallback a CPU si la GPU se cuelga.
- Validación de integridad del runtime wasm (detecta archivos corruptos).

### 🐧 Entornos de ejecución para el agente (desatendidos)
| Entorno | Disponibilidad | Capacidades |
|---|---|---|
| **Sandbox JS** (Worker) | Siempre, offline | Ejecuta JavaScript y lee stdout/errores |
| **Bash simulado** | Siempre, offline | `ls cd pwd cat echo mkdir rm cp mv find grep head tail wc date env…` |
| **Pyodide (Python)** | Offline con `./pyodide/`, o online vía CDN | Python completo + `micropip`/`loadPackage` (pip) |
| **Linux real embebido (v86)** | Offline con `./v86/` | Shell real por puerto serial; el agente escribe, ejecuta y lee **solo**. Soporta `apt/npm/git` si tu imagen los trae |
| **WebVM (CheerpX/Debian)** | Online, en pestaña | Referencia visual con Debian completo (no controlable por el agente) |

- **Terminal colapsable 🐧**: por defecto cerrado; ábrelo con la flechita solo si quieres ver al agente trabajar.
- **Loop autónomo**: en modo 🤖, si la tarea requiere pruebas, el agente genera código → lo ejecuta en el mejor entorno disponible → lee la salida → se auto-corrige (hasta 2 iteraciones) → entrega el resultado **verificado**.

### 🌐 Búsqueda web multi-motor
- **Google → Bing → Bing(html) → DuckDuckGo → DDG-Lite**, vía proxies CORS sin key (`r.jina.ai`, `allorigins`).
- Wikipedia solo como último recurso.
- Resultados **inyectados al modelo** con citas obligatorias.

### 🛠 Totalmente configurable
- Tarjeta por proveedor: modelo, key, base URL, URL de modelos, activar/desactivar, probar, eliminar.
- Preferencias globales: estrategia, **contexto total (n_ctx)**, **longitud máx de respuesta**, modelo por defecto, auto-compactación, tema.
- Endpoints OpenAI-compatible ilimitados (gateways propios, OmniRoute desplegado, etc.).
- Atajos: `Esc` cierra · `Ctrl+S` guarda.

### 🎭 Modo franco 🔓
- System prompt de tono **directo, sin rodeos ni moralina**, activable con un botón.
- Para crudeza *real* en local, combínalo con GGUFs **abliterated/uncensored**.

### 🧾 Memoria y transparencia
- **Ver memoria 🧠**: inspecciona la conversación en Markdown o JSON crudo, y descárgala.
- **Métricas en vivo** por respuesta: `⚡ tok/s · tokens · tiempo`, persistidas en el historial.
- **Historial** con títulos automáticos, editar/reenviar y copiar.

### 📎 Entrada y salida ricas
- **Adjuntos**: imágenes, texto, **Word, Excel, PowerPoint y PDF** (extracción integrada).
- **Exportar**: Markdown, JSON, CSV, PDF (imprimir), Word y PowerPoint.
- **Humanizar 🧑**: reescribe cualquier respuesta con tono natural, como respuesta nueva con sus propias métricas.

### 🎨 UI
- Tema claro/oscuro, responsive (móvil con sidebar ☰), numeración y coloreado de código, indicador "pensando" con verbos rotativos, stop ⏹ inmediato y scroll inteligente ↓.

---

## 🚀 Uso rápido

### Opción A — GitHub Pages (recomendado)
1. Entra a la URL publicada del repo (ver *Deploy* abajo).
2. Escribe y listo: `🔀 Auto` rota proveedores sin key automáticamente.
3. Para GGUF local: pulsa **📂** y elige tu `.gguf` (método Blob, sin servidor).

### Opción B — Local (offline total)
```bash
# Windows
copito_server.bat
# Mac / Linux
./copito_server.sh
```
Abre `http://localhost:8080` y carga tu GGUF con **📂** o desde `modelos/`. Con el WiFi apagado sigue chateando y ejecutando código en los entornos locales.

---

## 📦 Setup de componentes opcionales (una sola vez, luego offline)

```bash
# Runtime wllama 3.6.1 (GGUF local)
powershell -ExecutionPolicy Bypass -File setup_wllama.ps1   # o ./setup_wllama.sh
# Repara un wasm corrupto si fuera necesario
powershell -ExecutionPolicy Bypass -File fix_wllama.ps1

# Python offline con pip (Pyodide)
powershell -ExecutionPolicy Bypass -File setup_pyodide.ps1

# Linux real embebido para el agente (v86)
powershell -ExecutionPolicy Bypass -File setup_v86.ps1
```

Tras cada setup, el componente queda en su carpeta (`wllama/`, `pyodide/`, `v86/`) y funciona **sin internet**.

---

## 🧠 Modelos locales recomendados (CPU + WebGPU)

| Modelo | Peso Q4 | Uso |
|---|---|---|
| Llama-3.2-1B-Instruct | ~0.8 GB | texto rápido |
| Qwen2.5-1.5B-Instruct | ~1.0 GB | texto equilibrado |
| SmolLM2-1.7B-Instruct | ~1.2 GB | texto |
| Qwen2-VL-2B-Instruct + `mmproj` | ~1.0 GB + 1.3 GB | **visión** |
| OLMoE-1B-7B-Instruct (MoE) | ~4.0 GB | calidad MoE, velocidad de 1B |

---

## 🔒 Privacidad

- Las keys y la configuración se guardan **solo en tu navegador** (localStorage/cookie). Nada se envía a servidores propios.
- Los GGUF locales y los entornos de ejecución nunca salen de tu máquina.
- Sin telemetría, sin trackers, sin backend.

---

## 🗂 Estructura del repo

```
copito/
├── index.html            ← la app completa (un solo archivo)
├── sw.js                 ← Service Worker (opcional)
├── README.md / LICENSE / .gitignore
├── copito_server.bat     ← servidor local Windows (COOP/COEP + Range)
├── copito_server.sh      ← servidor local Mac/Linux
├── setup_wllama.ps1/.sh  ← runtime wllama 3.6.1
├── fix_wllama.ps1        ← repara wasm corrupto
├── setup_pyodide.ps1     ← Python offline (Pyodide)
├── setup_v86.ps1         ← Linux embebido (v86)
├── wllama/  pyodide/  v86/   ← componentes offline (tras setup)
└── modelos/              ← tus .gguf (NO se sube a GitHub)
```

---

## 📜 Licencia

**MIT** — uso, modificación y distribución libres, incluso comercial. Ver [LICENSE](LICENSE).