# 🦙 Copito — Chat multi-modelo sin límites, en un solo HTML

Copito es un cliente de chat **autocontenido** (un solo `index.html`) con **ruteo inteligente tipo OmniRoute**: rota y combina proveedores de IA (sin key, con key gratuita, endpoints OpenAI-compatible propios y **modelos GGUF locales en el navegador**) preservando tu sesión y traspasándola de un modelo a otro sin que notes el cambio.

> **Un archivo. Cero servidores. Cero cuentas obligatorias.** Ábrelo y chatea.

---

## ✨ Características principales

### 🔀 Ruteo tipo OmniRoute
- **Auto-selección de modelo**: el modo `🔀 Auto` rota solo entre todos los proveedores y modelos activos según la estrategia elegida.
- **Estrategias configurables**: `priority` (keyless primero), `round-robin`, `least-used`, `random`.
- **Detección de cupo agotado**: reconoce 402/429/"budget exceeded" y aplica *cooldown* de 15 min por modelo.
- **Preservación y traspaso de sesión**: si un modelo se agota o falla a mitad de conversación, Copito **compacta el contexto (context-relay)** y **continúa la misma sesión en el siguiente modelo disponible**, sin perder el hilo ni pedírtelo de nuevo.
- **Compactación automática**: al crecer el contexto o agotarse un cupo, resume la conversación y conserva los últimos mensajes para seguir con memoria.

### 🔑 Auto-keys y configuración asistida
- **Wizard inicial 🧙**: configuración guiada, opcional y repetible ("Usar modo Auto", "Ya terminé", "Omitir").
- **Auto-keys**: botón `🔑 Key gratis` abre la página oficial del proveedor y `📥 Pegar` lee tu key del portapapeles, la guarda localmente, activa el proveedor y prueba el endpoint en un clic.
- **Zero-config real**: sin tocar nada ya funciona con **Pollinations + AI Horde** (sin key ni registro).

### 🧠 GGUF local en el navegador (Wllama)
- Carga modelos `.gguf` desde tu disco (**📂 Archivo local**, método Blob: sin servidor ni Service Worker) o desde `modelos/` / HuggingFace.
- Inferencia **100% offline** en **CPU** o **WebGPU** (selector Auto/CPU/GPU + botón 🔄 para recargar y comparar velocidad).
- **Visión local con `mmproj`**: carga el proyector de visión y el modelo "ve" tus imágenes (Qwen2-VL, Moondream…).
- Detección automática de iGPU débil (Intel integrada) para elegir el dispositivo óptimo.

### 🛠 Totalmente configurable
- Tarjeta por proveedor: modelo, key, base URL, URL de modelos, activar/desactivar, probar, eliminar.
- Preferencias globales: estrategia de ruteo, **contexto total (n_ctx)**, **longitud máx de respuesta**, modelo por defecto, auto-compactación, tema.
- Añadir endpoints OpenAI-compatible ilimitados (gateways propios, OmniRoute desplegado, etc.).
- Atajos: `Esc` cierra, `Ctrl+S` guarda.

### 🧾 Memoria y transparencia
- **Ver memoria 🧠**: inspecciona la conversación guardada en Markdown o JSON crudo, y descárgala.
- **Métricas en vivo** por respuesta: `⚡ tok/s · tokens · tiempo`, persistidas en el historial.
- **Historial** de chats con títulos automáticos, editar/reenviar y copiar.

### 📎 Entrada y salida ricas
- **Adjuntos**: imágenes, texto, **Word, Excel, PowerPoint y PDF** (extracción de texto integrada).
- **Búsqueda web 🌐** (DuckDuckGo + Wikipedia) inyectada al modelo con citas.
- **Modo agéntico 🤖**: orquestador → ingeniero de prompts → resolvedor → evaluador de calidad.
- **Humanizar 🧑**: reescribe cualquier respuesta con tono natural, como una respuesta nueva con sus propias métricas.
- **Exportar**: Markdown, JSON, CSV, PDF (imprimir), Word y PowerPoint.

### 🎨 UI
- Tema claro/oscuro, responsive (móvil con sidebar ☰), numeración y coloreado de código, indicador "pensando" con verbos rotativos, botón ⏹ y ↓ inteligentes.

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
Abre `http://localhost:8080` y carga tu GGUF con **📂** o desde `modelos/`. Con el WiFi apagado sigue chateando.

---

## 🧠 Modelos locales recomendados (CPU + WebGPU)

| Modelo | Peso Q4 | Uso |
|---|---|---|
| Llama-3.2-1B-Instruct | ~0.8 GB | texto rápido |
| Qwen2.5-1.5B-Instruct | ~1.0 GB | texto equilibrado |
| SmolLM2-1.7B-Instruct | ~1.2 GB | texto |
| Qwen2-VL-2B-Instruct + `mmproj` | ~1.0 GB + 1.3 GB | **visión** |

---

## 🔒 Privacidad

- Las keys y la configuración se guardan **solo en tu navegador** (localStorage/cookie). Nada se envía a servidores propios.
- Los GGUF locales nunca salen de tu máquina.
- Sin telemetría, sin trackers, sin backend.

---

## 📜 Licencia

**MIT** — uso, modificación y distribución libres, incluso comercial. Ver [LICENSE](LICENSE).