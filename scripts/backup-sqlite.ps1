$ErrorActionPreference = 'Stop'
$source = Join-Path $env:USERPROFILE 'Documents\sayler.sqlite'
if (-not (Test-Path $source)) {
  throw "SQLite file not found: $source"
}
$folder = Join-Path $env:USERPROFILE 'Documents\SaylerBackups'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$zip = Join-Path $folder "sayler-$stamp.zip"
$temp = Join-Path $env:TEMP "sayler-backup-$stamp.sqlite"
Copy-Item -Path $source -Destination $temp -Force
Compress-Archive -Path $temp -DestinationPath $zip -Force
Remove-Item $temp -Force
Get-ChildItem $folder -Filter 'sayler-*.zip' |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force
Write-Host "Backup: $zip"

if ($args -contains '-Register') {
  $script = $PSCommandPath
  schtasks /Create /F /SC DAILY /ST 23:30 /TN 'SaylerSqliteBackup' /TR "powershell -NoProfile -ExecutionPolicy Bypass -File `"$script`""
  Write-Host 'Scheduled daily at 23:30.'
}
