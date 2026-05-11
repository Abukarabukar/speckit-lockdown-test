# Removes Option B from a device: ACL reset, module removed, scheduled task
# deleted, profile entry stripped. Use only when intentionally retiring Option B.

$ErrorActionPreference = 'Continue'

$root = 'C:\ProgramData\speckit'
if (Test-Path $root) { icacls $root /reset /T /Q | Out-Null }

Unregister-ScheduledTask -TaskName 'SpecKitPromptsSync' -Confirm:$false -ErrorAction SilentlyContinue

foreach ($p in @(
    "$env:ProgramFiles\WindowsPowerShell\Modules\Internal.SpecKit",
    'C:\Program Files\PowerShell\7\Modules\Internal.SpecKit'
  )) {
  if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}

foreach ($p in @("$PSHOME\Profile.ps1", 'C:\Program Files\PowerShell\7\profile.ps1')) {
  if (Test-Path $p) {
    $lines = Get-Content $p | Where-Object { $_ -notmatch '# speckit:wrapper' }
    Set-Content -Path $p -Value $lines
  }
}

Write-Output 'Option B uninstalled.'
