# fix_wllama.ps1 — repara un wllama.wasm corrupto/truncado (error "length overflow")
$ErrorActionPreference = 'Stop'
$V = '3.6.1'
$base = "https://cdn.jsdelivr.net/npm/@wllama/wllama@$V/esm"

Write-Host "🔧 Reparando wllama…" -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path 'wllama/wasm' | Out-Null

# Backup del wasm actual por si acaso
if (Test-Path 'wllama/wasm/wllama.wasm') {
  Move-Item -Force 'wllama/wasm/wllama.wasm' 'wllama/wasm/wllama.wasm.bak' -ErrorAction SilentlyContinue
}

Invoke-WebRequest -Uri "$base/index.js" -OutFile 'wllama/index.js'

$tmp = 'wllama/wasm/wllama.wasm.tmp'
Invoke-WebRequest -Uri "$base/wasm/wllama.wasm" -OutFile $tmp
$bytes = [IO.File]::ReadAllBytes($tmp)

if (-not ($bytes[0] -eq 0 -and $bytes[1] -eq 0x61 -and $bytes[2] -eq 0x73 -and $bytes[3] -eq 0x6D)) {
  Remove-Item $tmp -Force
  throw 'wasm nuevo SIN magic bytes \0asm: la descarga falló, reintenta.'
}
if ($bytes.Length -lt 8000000) {
  Remove-Item $tmp -Force
  throw ("wasm nuevo demasiado pequeño ({0} bytes): reintenta." -f $bytes.Length)
}
Move-Item -Force $tmp 'wllama/wasm/wllama.wasm'
Remove-Item 'wllama/wasm/wllama.wasm.bak' -ErrorAction SilentlyContinue

Write-Host ("✅ wasm reparado: {0} bytes, magic \0asm correcto" -f $bytes.Length) -ForegroundColor Green
Write-Host 'Recarga Copito con Ctrl+Shift+R y vuelve a cargar tu GGUF.' -ForegroundColor Cyan