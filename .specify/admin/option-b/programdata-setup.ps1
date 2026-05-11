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
$root    = 'C:\ProgramData\speckit'
$prompts = Join-Path $root 'prompts'
$agents  = Join-Path $root 'agents'

# Reset any prior lock so we have write access during setup (idempotent).
if (Test-Path $root) { icacls $root /reset /T /Q | Out-Null }
New-Item -ItemType Directory -Force -Path $root, $prompts, $agents | Out-Null

$repoUrl = $env:SPECKIT_PROMPTS_REPO
if (-not $repoUrl) {
  try { $repoUrl = (Get-ItemProperty 'HKLM:\Software\YourOrg\SpecKit' -ErrorAction Stop).PromptsRepo } catch {}
}
if (-not $repoUrl) {
  Write-Warning 'SPECKIT_PROMPTS_REPO not set; system paths will be created empty.'
}

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }

# The central repo is expected to have this layout:
#   <repo>/prompts/*.prompt.md
#   <repo>/agents/*.agent.md
# A bare clone into $root\.speckit-prompts-repo, then file sync into prompts/agents.
if ($repoUrl -and (Test-Path $git)) {
  $checkout = Join-Path $root '.speckit-prompts-repo'
  if (Test-Path (Join-Path $checkout '.git')) {
    & $git -C $checkout fetch --quiet --prune
    & $git -C $checkout pull --ff-only --quiet
  } else {
    if (Test-Path $checkout) { Remove-Item -Recurse -Force $checkout }
    & $git clone --quiet $repoUrl $checkout
  }

  if (Test-Path (Join-Path $checkout 'prompts')) {
    Get-ChildItem -Path $prompts -Filter '*.prompt.md' -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -Path (Join-Path $checkout 'prompts\*.prompt.md') -Destination $prompts -Force
  }
  if (Test-Path (Join-Path $checkout 'agents')) {
    Get-ChildItem -Path $agents -Filter '*.agent.md' -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item -Path (Join-Path $checkout 'agents\*.agent.md') -Destination $agents -Force
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

$pCount = (Get-ChildItem -Path $prompts -Filter '*.prompt.md' -ErrorAction SilentlyContinue).Count
$aCount = (Get-ChildItem -Path $agents  -Filter '*.agent.md'  -ErrorAction SilentlyContinue).Count
Write-Output "System content ready under $root — prompts: $pCount, agents: $aCount. ACL: SYSTEM/Admins:F, Users:RX."
