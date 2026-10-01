$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'Archive'
$links = Join-Path $app 'windows\flutter\ephemeral\.plugin_symlinks'
if (Test-Path $links) {
  Remove-Item -Recurse -Force $links
}
Push-Location $app
try {
  flutter build windows --release
} finally {
  Pop-Location
}
$exe = Join-Path $app 'build\windows\x64\runner\Release\sales_system.exe'
Write-Host "Release: $exe"
