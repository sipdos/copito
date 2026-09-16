# setup_v86.ps1 — descarga v86 + BIOS + imagen Linux para el VM embebido del agente
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path 'v86/bios', 'v86/images' | Out-Null

$build = 'https://copy.sh/v86/build/'
$bios  = 'https://copy.sh/v86/bios/'
$img   = 'https://copy.sh/v86/images/'

function Get-File($url, $dest) {
  Write-Host ("⬇ {0}" -f $dest) -ForegroundColor Cyan
  try {
    Invoke-WebRequest -Uri $url -OutFile $dest
    if ((Get-Item $dest).Length -eq 0) { throw 'archivo vacío' }
  } catch {
    Write-Host ("⚠️ Falló {0}: {1}" -f $url, $_.Exception.Message) -ForegroundColor Yellow
    Write-Host '   Si la URL cambió, abre https://copy.sh/v86/ , pulsa F12→Network, recarga' -ForegroundColor Yellow
    Write-Host '   y copia la ruta real del archivo correspondiente en este script.' -ForegroundColor Yellow
    return $false
  }
  return $true
}

$ok = $true
$ok = (Get-File ($build + 'libv86.js')   'v86/libv86.js')   -and $ok
$ok = (Get-File ($build + 'v86.wasm')    'v86/v86.wasm')    -and $ok
$ok = (Get-File ($bios + 'seabios.bin')  'v86/bios/seabios.bin')  -and $ok
$ok = (Get-File ($bios + 'vgabios.bin')  'v86/bios/vgabios.bin')  -and $ok
# Imagen Linux minimal (busybox). Si da 404, prueba 'linux4.iso' o 'buildroot.img' en la misma carpeta.
$ok = (Get-File ($img + 'buildroot.iso') 'v86/images/buildroot.iso') -and $ok

if (-not $ok) {
  Write-Host '⚠️ Algunos archivos no se descargaron. Copito usará el bash SIMULADO hasta que completes v86/.' -ForegroundColor Yellow
} else {
  Write-Host '✅ v86 listo en ./v86 — el agente tendrá Linux real desatendido (🐧).' -ForegroundColor Green
}
Get-ChildItem -Recurse v86 | Select-Object FullName, Length | Format-Table -AutoSize