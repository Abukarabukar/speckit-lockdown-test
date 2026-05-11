# Intune Proactive Remediation - brings Option B back to compliance.
# Calls the three idempotent install scripts in dependency order. Runs as SYSTEM.

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'install-wrapper.ps1')
& (Join-Path $PSScriptRoot 'programdata-setup.ps1')
& (Join-Path $PSScriptRoot 'register-sync-task.ps1')

Write-Output 'Option B remediation complete.'
exit 0
