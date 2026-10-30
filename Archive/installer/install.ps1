$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'Sayler'

function Find-SaylerExe {
  param([string]$Start)
  $candidates = @(
    (Join-Path $Start 'sales_system.exe'),
    (Join-Path $Start 'app\sales_system.exe'),
    (Join-Path $Start '..\sales_system.exe'),
    (Join-Path $Start '..\app\sales_system.exe')
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  $found = Get-ChildItem -LiteralPath $Start -Filter 'sales_system.exe' -Recurse -File -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($found) {
    return $found.FullName
  }
  $parent = Split-Path -Parent $Start
  if ($parent -and (Test-Path -LiteralPath $parent)) {
    $found = Get-ChildItem -LiteralPath $parent -Filter 'sales_system.exe' -Recurse -File -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($found) {
      return $found.FullName
    }
  }
  return $null
}

$exeSource = Find-SaylerExe $root
if (-not $exeSource) {
  $seen = Get-ChildItem -LiteralPath $root -Force | ForEach-Object { $_.Name }
  throw ("sales_system.exe was not found next to the installer. Folder: $root. Contents: " + ($seen -join ', '))
}
$source = Split-Path -Parent $exeSource

New-Item -ItemType Directory -Force -Path $dest | Out-Null
$copy = Start-Process -FilePath "$env:SystemRoot\System32\robocopy.exe" -ArgumentList @(
  $source,
  $dest,
  '/E',
  '/XF',
  'install.ps1',
  'Install-Sayler.cmd',
  '/NFL',
  '/NDL',
  '/NJH',
  '/NJS',
  '/nc',
  '/ns',
  '/np'
) -Wait -PassThru -WindowStyle Hidden
if ($copy.ExitCode -ge 8) {
  throw "Could not copy Sayler files. Code $($copy.ExitCode)"
}

$serverScript = Join-Path $dest 'server\start-server.ps1'
if (Test-Path -LiteralPath $serverScript) {
  Start-Process -FilePath powershell.exe -ArgumentList @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $serverScript
  ) -WindowStyle Hidden
  $ready = $false
  for ($i = 0; $i -lt 45; $i++) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
      $client.Connect('127.0.0.1', 3000)
      $ready = $true
      break
    } catch {
      Start-Sleep -Seconds 1
    } finally {
      $client.Dispose()
    }
  }
  if (-not $ready) {
    throw 'The local Sayler server did not start. See server\server.log next to the program.'
  }
}

$exe = Join-Path $dest 'sales_system.exe'
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutName = -join @(
  [char]0x0633,
  [char]0x0627,
  [char]0x064A,
  [char]0x0644,
  [char]0x0631
)
$latinShortcut = Join-Path $desktop 'Sayler.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($latinShortcut)
$link.TargetPath = $exe
$link.WorkingDirectory = $dest
$link.IconLocation = "$exe,0"
$link.Description = 'Sayler'
$link.Save()

$arabicShortcut = Join-Path $desktop ($shortcutName + '.lnk')
if (Test-Path -LiteralPath $arabicShortcut) {
  Remove-Item -LiteralPath $arabicShortcut -Force
}
Rename-Item -LiteralPath $latinShortcut -NewName ($shortcutName + '.lnk')

Start-Process -FilePath $exe
