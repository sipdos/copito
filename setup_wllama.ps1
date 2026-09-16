# setup_wllama.ps1 — descarga wllama 3.6.1 (runtime GGUF local) y valida integridad
$ErrorActionPreference = 'Stop'
$V = '3.6.1'
$base = "https://cdn.jsdelivr.net/npm/@wllama/wllama@$V/esm"

Write-Host "⬇ Descargando wllama $V…" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path 'wllama/wasm' | Out-Null

Invoke-WebRequest -Uri "$base/index.js" -OutFile 'wllama/index.js'

$tmp = 'wllama/wasm/wllama.wasm.tmp'
Invoke-WebRequest -Uri "$base/wasm/wllama.wasm" -OutFile $tmp
$bytes = [IO.File]::ReadAllBytes($tmp)

# Validar magic bytes \0asm = 0,97,115,109
if (-not ($bytes[0] -eq 0 -and $bytes[1] -eq 0x61 -and $bytes[2] -eq 0x73 -and $bytes[3] -eq 0x6D)) {
  Remove-Item $tmp -Force
  throw 'wasm descargado SIN magic bytes \0asm: descarga corrupta, reintenta.'
}
if ($bytes.Length -lt 8000000) {
  Remove-Item $tmp -Force
  throw ("wasm demasiado pequeño ({0} bytes): truncado, reintenta." -f $bytes.Length)
}
Move-Item -Force $tmp 'wllama/wasm/wllama.wasm'

Write-Host ("✅ wllama $V listo: index.js + wasm/wllama.wasm ({0} bytes, magic OK)" -f $bytes.Length) -ForegroundColor Green
Get-ChildItem -Recurse wllama | Select-Object FullName, Length