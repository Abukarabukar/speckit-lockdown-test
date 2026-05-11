# One-shot installer that drops updater.ps1 to a stable system path and registers
# a scheduled task running it as SYSTEM every 4 hours and at logon.
# Deliver this as a Win32 app via Intune (intunewin), running once at install.

$ErrorActionPreference = 'Stop'

$target = 'C:\ProgramData\speckit'
$null   = New-Item -ItemType Directory -Force -Path $target
$src    = Join-Path $PSScriptRoot 'updater.ps1'
$dst    = Join-Path $target       'updater.ps1'
Copy-Item -Path $src -Destination $dst -Force

# Lock the updater so users can't tamper with it.
icacls $dst /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(F)' /grant:r 'BUILTIN\Administrators:(F)' /grant:r 'BUILTIN\Users:(RX)' /Q | Out-Null

$taskName = 'SpecKitUpdater'
$action   = New-ScheduledTaskAction -Execute 'powershell.exe' `
  -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$dst`""

$triggers = @(
  New-ScheduledTaskTrigger -AtLogOn
  (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Hours 4))
)

$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd `
              -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 5)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers `
  -Principal $principal -Settings $settings -Force | Out-Null

Write-Output "Registered scheduled task '$taskName' to run updater every 4 hours."
