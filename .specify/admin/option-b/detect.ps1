# Intune Proactive Remediation - detection for Option B installation.
# Returns 0 (compliant) when all five checks pass:
#   1. C:\ProgramData\speckit\prompts exists
#   2. Its ACL is locked (SYSTEM:F, Users:RX, inheritance off)
#   3. The Internal.SpecKit module is installed under $PSHOME\Modules
#   4. The AllUsers profile imports it
#   5. The SpecKitPromptsSync scheduled task exists

$ErrorActionPreference = 'SilentlyContinue'
$problems = New-Object System.Collections.Generic.List[string]

$root = 'C:\ProgramData\speckit'
if (-not (Test-Path $root)) {
  $problems.Add("Missing path: $root")
} else {
  $acl = (icacls $root 2>$null) -join "`n"
  if ($acl -match '\(I\)')                                                              { $problems.Add("$root has inherited ACEs (should be /inheritance:r).") }
  if ($acl -notmatch 'NT AUTHORITY\\SYSTEM:\([^)]*F[^)]*\)')                            { $problems.Add("SYSTEM is not granted Full Control on $root.") }
  if (-not ($acl -match 'BUILTIN\\Users:\([^)]*\b(R|RX)\b[^)]*\)') -or
       ($acl -match 'BUILTIN\\Users:\([^)]*\b(W|M|F)\b[^)]*\)'))                        { $problems.Add('Users entry is missing or has write access.') }

  foreach ($sub in @('prompts','agents')) {
    $p = Join-Path $root $sub
    if (-not (Test-Path $p)) { $problems.Add("Missing path: $p") }
  }
}

$module = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules\Internal.SpecKit\Internal.SpecKit.psm1'
if (-not (Test-Path $module)) { $problems.Add("Wrapper not installed: $module") }

$profilePath = "$PSHOME\Profile.ps1"
if (-not (Test-Path $profilePath) -or -not ((Get-Content $profilePath -ErrorAction SilentlyContinue) -match '# speckit:wrapper')) {
  $problems.Add('AllUsers profile does not import Internal.SpecKit.')
}

$task = Get-ScheduledTask -TaskName 'SpecKitPromptsSync' -ErrorAction SilentlyContinue
if (-not $task -or $task.State -eq 'Disabled') { $problems.Add('SpecKitPromptsSync scheduled task missing or disabled.') }

if ($problems.Count -eq 0) {
  Write-Output 'Compliant: Option B fully installed.'
  exit 0
} else {
  Write-Output 'Non-compliant:'
  $problems | ForEach-Object { Write-Output "  $_" }
  exit 1
}
