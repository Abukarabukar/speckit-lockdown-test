# Provisions C:\ProgramData\speckit\prompts on a managed device.
# - Creates the folder
# - Applies the read-only ACL (Users:RX, SYSTEM/Admins:F)
# - Seeds the folder with prompt files cloned from a central GitHub repo
#
# Run as SYSTEM via Intune Win32 app install. Idempotent.
#
# Required env or registry value:
#   HKLM\Software\YourOrg\SpecKit\PromptsRepo = https://github.com/<ORG>/speckit-prompts.git

$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\speckit'
$prompts = Join-Path $root 'prompts'
New-Item -ItemType Directory -Force -Path $root, $prompts | Out-Null

$repoUrl = $env:SPECKIT_PROMPTS_REPO
if (-not $repoUrl) {
  try { $repoUrl = (Get-ItemProperty 'HKLM:\Software\YourOrg\SpecKit' -ErrorAction Stop).PromptsRepo } catch {}
}
if (-not $repoUrl) {
  Write-Warning 'SPECKIT_PROMPTS_REPO not set; system path will be created empty.'
}

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }

if ($repoUrl -and (Test-Path $git)) {
  if (Test-Path (Join-Path $prompts '.git')) {
    & $git -C $prompts fetch --quiet --prune
    & $git -C $prompts pull --ff-only --quiet
  } else {
    $tmp = Join-Path $env:TEMP ("speckit-prompts-{0}" -f ([Guid]::NewGuid()))
    & $git clone --quiet $repoUrl $tmp
    Get-ChildItem -Path $tmp -Force | Move-Item -Destination $prompts -Force
    Remove-Item -Recurse -Force $tmp
  }
}

# Apply inheritable ACEs to the root. (OI)(CI) propagates to NEW children but
# not necessarily to existing ones — so we then reset child ACLs to re-inherit.
icacls $root /inheritance:r `
  /grant:r 'NT AUTHORITY\SYSTEM:(OI)(CI)F' `
  /grant:r 'BUILTIN\Administrators:(OI)(CI)F' `
  /grant:r 'BUILTIN\Users:(OI)(CI)RX' /Q | Out-Null

# Reset all descendants so they discard old/empty ACEs and inherit the new ones.
if (Get-ChildItem $root -Recurse -Force -ErrorAction SilentlyContinue) {
  icacls "$root\*" /reset /T /Q | Out-Null
}

$count = (Get-ChildItem -Path $prompts -Filter '*.prompt.md' -Recurse -ErrorAction SilentlyContinue).Count
Write-Output "System prompts ready at $prompts (files: $count). ACL: SYSTEM/Admins:F, Users:RX."
