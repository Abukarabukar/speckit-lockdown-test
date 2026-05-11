# Installs Internal.SpecKit to the system-wide PowerShell module path and
# wires up the AllUsers profile so every PowerShell session auto-imports it.
# Run as SYSTEM via Intune Win32 app install.

$ErrorActionPreference = 'Stop'

$moduleName = 'Internal.SpecKit'
$systemModuleRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
$target = Join-Path $systemModuleRoot $moduleName

New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'Internal.SpecKit.psm1') -Destination $target -Force
Copy-Item -Path (Join-Path $PSScriptRoot 'Internal.SpecKit.psd1') -Destination $target -Force

icacls $target /inheritance:r `
  /grant:r 'NT AUTHORITY\SYSTEM:(OI)(CI)F' `
  /grant:r 'BUILTIN\Administrators:(OI)(CI)F' `
  /grant:r 'BUILTIN\Users:(OI)(CI)RX' /T /Q | Out-Null

$profilePath = "$PSHOME\Profile.ps1"
$importLine  = "Import-Module $moduleName -ErrorAction SilentlyContinue # speckit:wrapper"

$existing = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
if ($existing -notmatch '# speckit:wrapper') {
  Add-Content -Path $profilePath -Value "`n$importLine"
}

$pwsh7Profile = 'C:\Program Files\PowerShell\7\profile.ps1'
if (Test-Path (Split-Path $pwsh7Profile)) {
  $existing7 = if (Test-Path $pwsh7Profile) { Get-Content $pwsh7Profile -Raw } else { '' }
  if ($existing7 -notmatch '# speckit:wrapper') {
    Add-Content -Path $pwsh7Profile -Value "`n$importLine"
  }
  $pwsh7Modules = 'C:\Program Files\PowerShell\7\Modules'
  $pwsh7Target  = Join-Path $pwsh7Modules $moduleName
  New-Item -ItemType Directory -Force -Path $pwsh7Target | Out-Null
  Copy-Item -Path (Join-Path $PSScriptRoot 'Internal.SpecKit.psm1') -Destination $pwsh7Target -Force
  Copy-Item -Path (Join-Path $PSScriptRoot 'Internal.SpecKit.psd1') -Destination $pwsh7Target -Force
}

Write-Output "Installed $moduleName to $target and registered in AllUsers profile."
