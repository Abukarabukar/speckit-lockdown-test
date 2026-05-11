# Intune Proactive Remediation - detection script.
# Runs as SYSTEM on every managed device. Exits 0 if every Spec Kit repo on the
# device has the locked ACL; exits 1 to trigger remediation.
#
# A repo is identified by the presence of .specify\extensions.yml.
# A repo is "locked" when .specify, .github\prompts, .vscode have:
#   - inheritance disabled
#   - SYSTEM:(F)
#   - BUILTIN\Users:(RX) only (no write/modify entry)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$signatureFile = '.specify\extensions.yml'
$lockedDirs    = @('.specify', '.github\prompts', '.vscode')
$searchRoots   = @(
  'C:\Users'
) | Where-Object { Test-Path $_ }

function Test-LockedAcl {
  param([string]$Path)
  if (-not (Test-Path $Path)) { return $true }   # nothing to lock — treat as compliant
  $acl = (icacls $Path 2>$null) -join "`n"
  # Must NOT contain an inherited ACE marker, must grant SYSTEM:(F) and Users:(RX), must NOT grant Users write.
  $inheritanceOff = $acl -notmatch '\(I\)'
  $systemFull     = $acl -match 'NT AUTHORITY\\SYSTEM:\([^)]*F[^)]*\)'
  $usersReadOnly  = ($acl -match 'BUILTIN\\Users:\([^)]*\b(R|RX)\b[^)]*\)') -and
                    ($acl -notmatch 'BUILTIN\\Users:\([^)]*\b(W|M|F)\b[^)]*\)')
  return ($inheritanceOff -and $systemFull -and $usersReadOnly)
}

$nonCompliant = New-Object System.Collections.Generic.List[string]
$reposScanned = 0

foreach ($root in $searchRoots) {
  Get-ChildItem -Path $root -Recurse -Depth 6 -Filter 'extensions.yml' -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName.EndsWith($signatureFile) -and $_.Directory.Parent } |
    ForEach-Object {
      $repo = $_.Directory.Parent.FullName
      $reposScanned++
      foreach ($d in $lockedDirs) {
        $p = Join-Path $repo $d
        if ((Test-Path $p) -and -not (Test-LockedAcl $p)) {
          $nonCompliant.Add($p) | Out-Null
        }
      }
    }
}

if ($nonCompliant.Count -eq 0) {
  Write-Output "Compliant: $reposScanned Spec Kit repo(s) scanned, all locked."
  exit 0
} else {
  Write-Output "Non-compliant: $($nonCompliant.Count) path(s) need re-lock:"
  $nonCompliant | ForEach-Object { Write-Output "  $_" }
  exit 1
}
