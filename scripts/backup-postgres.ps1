$ErrorActionPreference = 'Stop'
$url = $env:SAYLER_DATABASE_PUBLIC_URL
if ([string]::IsNullOrWhiteSpace($url)) {
  throw 'Set SAYLER_DATABASE_PUBLIC_URL before running. The URL is not printed.'
}
$folder = Join-Path $env:USERPROFILE 'Documents\SaylerBackups'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$out = Join-Path $folder "railway-$stamp.dump"
& pg_dump --dbname=$url --format=custom --file=$out
if ($LASTEXITCODE -ne 0) {
  throw 'pg_dump failed. Install the PostgreSQL client and use the public database URL.'
}
Get-ChildItem $folder -Filter 'railway-*.dump' |
  Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-14) } |
  Remove-Item -Force
Write-Host "Dump: $out"

if ($args -contains '-Register') {
  $script = $PSCommandPath
  schtasks /Create /F /SC DAILY /ST 23:45 /TN 'SaylerPostgresBackup' /TR "powershell -NoProfile -ExecutionPolicy Bypass -File `"$script`""
  Write-Host 'Scheduled daily at 23:45. The database URL variable must exist for that Windows account.'
}
