# Periodic updater for C:\ProgramData\speckit\prompts.
# Runs as SYSTEM via the SpecKitPromptsSync scheduled task (every 4 hours +
# at logon). SYSTEM has Full Control on the system path so it can pull while
# Users remain read-only.

$ErrorActionPreference = 'Continue'
$log = 'C:\ProgramData\speckit\sync.log'
function Log($m) { "{0:o} {1}" -f (Get-Date), $m | Tee-Object -FilePath $log -Append }

$root     = 'C:\ProgramData\speckit'
$checkout = Join-Path $root '.speckit-prompts-repo'
$prompts  = Join-Path $root 'prompts'
$agents   = Join-Path $root 'agents'

if (-not (Test-Path (Join-Path $checkout '.git'))) {
  Log "No checkout at $checkout; run programdata-setup.ps1 first."
  exit 0
}

function Get-Token {
  try { $v = (Get-ItemProperty 'HKLM:\Software\YourOrg\SpecKit' -ErrorAction Stop).PullToken; if ($v) { return $v } } catch {}
  $f = 'C:\ProgramData\speckit\token.txt'
  if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
  return $env:SPECKIT_GH_TOKEN
}

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = 'C:\Program Files\Git\cmd\git.exe' }
if (-not (Test-Path $git)) { Log 'git not found, aborting.'; exit 2 }

$token = Get-Token
$env:GIT_TERMINAL_PROMPT = '0'
if ($token) {
  $store = 'C:\ProgramData\speckit\git-credentials'
  "https://x-access-token:$token@github.com" | Set-Content $store -Encoding ASCII
  icacls $store /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(F)' /Q | Out-Null
  & $git config --system credential.helper "store --file=$store" | Out-Null
}

Log "Pulling $checkout ..."
$out  = & $git -C $checkout fetch --quiet --prune 2>&1
$out += & $git -C $checkout pull --ff-only --quiet 2>&1
if ($LASTEXITCODE -ne 0) { Log "  WARN: $out"; exit 1 }
Log '  OK'

# Sync canonical files from the checkout into the user-visible prompts/agents
# folders, preserving the read-only ACL on those folders (SYSTEM keeps F).
Log "Syncing prompts and agents into user-visible folders ..."
if (Test-Path (Join-Path $checkout 'prompts')) {
  Get-ChildItem -Path $prompts -Filter '*.prompt.md' -ErrorAction SilentlyContinue | Remove-Item -Force
  Copy-Item -Path (Join-Path $checkout 'prompts\*.prompt.md') -Destination $prompts -Force
}
if (Test-Path (Join-Path $checkout 'agents')) {
  Get-ChildItem -Path $agents -Filter '*.agent.md' -ErrorAction SilentlyContinue | Remove-Item -Force
  Copy-Item -Path (Join-Path $checkout 'agents\*.agent.md') -Destination $agents -Force
}
Log '  Sync complete.'
exit 0
