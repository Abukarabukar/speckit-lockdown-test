# Intune Proactive Remediation - remediation script.
# Runs as SYSTEM. Applies the read-only ACL to every Spec Kit repo it finds.
# After this runs:
#   - SYSTEM has Full Control (so the scheduled updater can git-pull)
#   - BUILTIN\Users has Read+Execute only
#   - Inheritance is disabled (so user-profile inheritance can't re-grant write)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$signatureFile = '.specify\extensions.yml'
$lockedDirs    = @('.specify', '.github\prompts', '.vscode')
$searchRoots   = @('C:\Users') | Where-Object { Test-Path $_ }

function Lock-Path {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return }
  icacls $Path /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(OI)(CI)F' /T /Q | Out-Null
  icacls $Path /grant:r 'BUILTIN\Administrators:(OI)(CI)F'             /T /Q | Out-Null
  icacls $Path /grant:r 'BUILTIN\Users:(OI)(CI)RX'                     /T /Q | Out-Null
}

$locked = 0
foreach ($root in $searchRoots) {
  Get-ChildItem -Path $root -Recurse -Depth 6 -Filter 'extensions.yml' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName.EndsWith($signatureFile) -and $_.Directory.Parent } |
    ForEach-Object {
      $repo = $_.Directory.Parent.FullName
      foreach ($d in $lockedDirs) {
        $p = Join-Path $repo $d
        if (Test-Path $p) { Lock-Path -Path $p; $locked++ }
      }
    }
}

Write-Output "Locked $locked Spec Kit director(y/ies) across discovered repos."
exit 0
