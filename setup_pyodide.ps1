# setup_pyodide.ps1 — descarga Pyodide offline a ./pyodide (Python + pip en el navegador)
$ErrorActionPreference = 'Stop'
$V = '0.26.4'
# Cambia a "pyodide-$V.tar.bz2" si quieres la versión FULL (numpy/pandas/scipy offline, ~180MB)
$url = "https://github.com/pyodide/pyodide/releases/download/$V/pyodide-core-$V.tar.bz2"
$out = 'pyodide-core.tar.bz2'

Write-Host "⬇ Descargando Pyodide $V (core)…" -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $out

Write-Host '📦 Extrayendo (tar)…' -ForegroundColor Cyan
tar -xjf $out
if (Test-Path "pyodide-core-$V") { Move-Item -Force "pyodide-core-$V" pyodide }
elseif (Test-Path "pyodide-$V")  { Move-Item -Force "pyodide-$V" pyodide }
Remove-Item -Force $out

# Verificación mínima
if (-not (Test-Path 'pyodide/pyodide.js')) { throw 'No se encontró pyodide/pyodide.js: extracción fallida.' }
Write-Host '✅ Pyodide offline listo en ./pyodide' -ForegroundColor Green
Get-ChildItem pyodide | Select-Object Name, Length | Format-Table -AutoSize
Write-Host 'Con esto, Python y micropip (pip) funcionan SIN internet en Copito.' -ForegroundColor Cyan