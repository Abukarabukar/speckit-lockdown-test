# Removes the Spec Kit lock ACL. Intended for IT use only — running this on a
# managed device restores user write access to .specify, prompts, .vscode.

$ErrorActionPreference = 'Continue'
$signatureFile = '.specify\extensions.yml'
$lockedDirs    = @('.specify', '.github\prompts', '.vscode')

Get-ChildItem 'C:\Users' -Recurse -Depth 6 -Filter 'extensions.yml' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName.EndsWith($signatureFile) -and $_.Directory.Parent } |
  ForEach-Object {
    $repo = $_.Directory.Parent.FullName
    foreach ($d in $lockedDirs) {
      $p = Join-Path $repo $d
      if (Test-Path $p) {
        icacls $p /reset /T /Q | Out-Null
        Write-Output "Unlocked: $p"
      }
    }
  }
