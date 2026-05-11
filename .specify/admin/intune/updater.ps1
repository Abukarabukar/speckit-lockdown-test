# Spec Kit privileged updater.
# Runs as SYSTEM via the scheduled task created by register-updater.ps1.
# Pulls the latest Spec Kit prompts/templates into every locked repo on the
# device without dropping the user's ACL — SYSTEM has Full Control while the
# user only has Read, so git operations succeed and the lock stays intact.
#
# Authentication for private repos:
#   This script reads a GitHub token from one of (first found wins):
#     1. The HKLM:\Software\YourOrg\SpecKit registry value 'PullToken'
#     2. The file C:\ProgramData\speckit\token.txt (NTFS ACL: SYSTEM only)
#     3. The environment variable SPECKIT_GH_TOKEN
#   The token must have `repo` (read) scope on the target repos. Provision via
#   a GitHub App installation token if possible (no rotation), or a fine-grained
#   PAT scoped to your speckit org and the relevant repos.
#
#   For PUBLIC repos no token is required.

$ErrorActionPreference = 'Continue'
$logDir = 'C:\ProgramData\speckit'
$null = New-Item -ItemType Directory -Force -Path $logDir
$log   = Join-Path $logDir 'updater.log'
function Log($m) { "{0:o} {1}" -f (Get-Date), $m | Tee-Object -FilePath $log -Append }

function Get-Token {
  try {
    $v = (Get-ItemProperty 'HKLM:\Software\YourOrg\SpecKit' -ErrorAction Stop).PullToken
    if ($v) { return $v }
  } catch {}
  $f = 'C:\ProgramData\speckit\token.txt'
  if (Test-Path $f) { return (Get-Content $f -Raw).Trim() }
  if ($env:SPECKIT_GH_TOKEN) { return $env:SPECKIT_GH_TOKEN }
  return $null
}

$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitExe) {
  $gitExe = 'C:\Program Files\Git\cmd\git.exe'
}
if (-not (Test-Path $gitExe)) { Log "git.exe not found, aborting."; exit 2 }

$token = Get-Token
$env:GIT_TERMINAL_PROMPT = '0'
if ($token) {
  $env:GIT_ASKPASS = ''
  # Configure a credential helper that returns the token for github.com.
  $store = Join-Path $logDir 'git-credentials'
  "https://x-access-token:$token@github.com" | Set-Content $store -Encoding ASCII
  icacls $store /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(F)' /Q | Out-Null
  & $gitExe config --system credential.helper "store --file=$store" | Out-Null
}

$signatureFile = '.specify\extensions.yml'
$repos = Get-ChildItem 'C:\Users' -Recurse -Depth 6 -Filter 'extensions.yml' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName.EndsWith($signatureFile) -and $_.Directory.Parent } |
  ForEach-Object { $_.Directory.Parent.FullName } |
  Sort-Object -Unique

foreach ($repo in $repos) {
  if (-not (Test-Path (Join-Path $repo '.git'))) { Log "Skip (no .git): $repo"; continue }
  Log "Pull: $repo"
  $out = & $gitExe -C $repo fetch --quiet --prune 2>&1
  $out += & $gitExe -C $repo pull --ff-only --quiet 2>&1
  if ($LASTEXITCODE -ne 0) { Log "  WARN: $out" } else { Log "  OK" }
}

Log "Updater run complete."
exit 0
