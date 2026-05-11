# Internal.SpecKit — corporate wrapper around the upstream Spec Kit CLI.
#
# Behavior:
#   - Forwards every invocation to the upstream `specify` binary.
#   - On `specify init ...`, post-processes the target directory:
#       1. Deletes .github/prompts/  (workspace prompts are forbidden)
#       2. Writes .vscode/settings.json so VS Code loads prompts from the
#          IT-managed system path (read-only via NTFS ACL).
#       3. Appends .github/prompts/ to .gitignore so accidental recreation
#          can never be committed.
#   - On every other subcommand (check, version, extension, etc.) it does nothing
#     after the forward call.
#
# Distribute by:
#   - Installing this .psm1 + .psd1 to $PSHOME\Modules\Internal.SpecKit\ (system)
#   - Adding `Import-Module Internal.SpecKit` to $PSHOME\Profile.ps1 (AllUsers)
#   - Renaming the upstream binary to `specify-upstream` so this wrapper
#     can call it without re-entry.

$script:SystemPromptsPath = 'C:\ProgramData\speckit\prompts'
$script:UpstreamCommand   = 'specify-upstream'

function Test-IsInitInvocation {
  param([string[]] $InvocationArgs)
  if ($InvocationArgs.Count -eq 0) { return $false }
  $firstPositional = $InvocationArgs | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1
  return $firstPositional -eq 'init'
}

function Resolve-InitTarget {
  param([string[]] $InvocationArgs)
  if ($InvocationArgs -contains '--here') { return (Get-Location).Path }

  $afterInit = $false
  foreach ($a in $InvocationArgs) {
    if ($a -eq 'init') { $afterInit = $true; continue }
    if (-not $afterInit) { continue }
    if ($a.StartsWith('-')) { continue }
    if ($a -eq '.') { return (Get-Location).Path }
    return (Join-Path (Get-Location) $a)
  }
  return (Get-Location).Path
}

function Set-WorkspacePromptPolicy {
  param([Parameter(Mandatory)] [string] $TargetDir)

  if (-not (Test-Path (Join-Path $TargetDir '.specify'))) {
    Write-Warning "Internal.SpecKit: '$TargetDir' has no .specify folder; nothing to post-process."
    return
  }

  $workspacePrompts = Join-Path $TargetDir '.github\prompts'
  if (Test-Path $workspacePrompts) {
    Remove-Item -Recurse -Force $workspacePrompts
    Write-Host "Internal.SpecKit: removed workspace prompts at $workspacePrompts"
  }

  $vscodeDir    = Join-Path $TargetDir '.vscode'
  $settingsPath = Join-Path $vscodeDir 'settings.json'
  New-Item -ItemType Directory -Force -Path $vscodeDir | Out-Null

  $settings = if (Test-Path $settingsPath) {
    try { Get-Content -Raw -Path $settingsPath | ConvertFrom-Json -AsHashtable } catch { @{} }
  } else { @{} }

  $settings['chat.promptFilesLocations'] = @($script:SystemPromptsPath)
  $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
  Write-Host "Internal.SpecKit: wrote chat.promptFilesLocations to $settingsPath"

  $gitignore = Join-Path $TargetDir '.gitignore'
  $marker    = '# Spec Kit prompts are managed by IT (see .vscode/settings.json)'
  $line      = '.github/prompts/'
  $hasLine = (Test-Path $gitignore) -and ((Get-Content $gitignore -ErrorAction SilentlyContinue) -contains $line)
  if (-not $hasLine) {
    Add-Content -Path $gitignore -Value "`n$marker`n$line"
    Write-Host "Internal.SpecKit: appended $line to .gitignore"
  }
}

function Invoke-InternalSpecify {
  [CmdletBinding()]
  param([Parameter(ValueFromRemainingArguments)] [string[]] $InvocationArgs)

  $upstream = Get-Command $script:UpstreamCommand -ErrorAction SilentlyContinue
  if (-not $upstream) {
    Write-Error "Internal.SpecKit: upstream command '$($script:UpstreamCommand)' not found on PATH. Install the corporate Spec Kit package."
    return 127
  }

  & $upstream.Source @InvocationArgs
  $code = $LASTEXITCODE
  if ($code -ne 0) { return $code }

  if (Test-IsInitInvocation -InvocationArgs $InvocationArgs) {
    $target = Resolve-InitTarget -InvocationArgs $InvocationArgs
    Set-WorkspacePromptPolicy -TargetDir $target
  }
  return 0
}

Set-Alias -Name specify -Value Invoke-InternalSpecify -Scope Global -Force

Export-ModuleMember -Function Invoke-InternalSpecify, Set-WorkspacePromptPolicy, Resolve-InitTarget, Test-IsInitInvocation -Alias specify
