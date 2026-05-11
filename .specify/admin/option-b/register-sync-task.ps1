# Drops programdata-sync.ps1 to a stable system path and registers the
# SpecKitPromptsSync scheduled task (SYSTEM, every 4 hours, at logon).
# Deliver as a Win32 app via Intune (intunewin).

$ErrorActionPreference = 'Stop'

$target = 'C:\ProgramData\speckit'
$null = New-Item -ItemType Directory -Force -Path $target
$dst = Join-Path $target 'programdata-sync.ps1'
Copy-Item -Path (Join-Path $PSScriptRoot 'programdata-sync.ps1') -Destination $dst -Force
icacls $dst /inheritance:r `
  /grant:r 'NT AUTHORITY\SYSTEM:(F)' `
  /grant:r 'BUILTIN\Administrators:(F)' `
  /grant:r 'BUILTIN\Users:(RX)' /Q | Out-Null

$taskName = 'SpecKitPromptsSync'
$action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dst`""

$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn
  (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 4))
)

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
              -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
              -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers `
  -Principal $principal -Settings $settings -Force | Out-Null

Write-Output "Registered scheduled task '$taskName'."
