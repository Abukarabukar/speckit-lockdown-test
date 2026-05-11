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
$script:SystemAgentsPath  = 'C:\ProgramData\speckit\agents'
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

  # 1. Replace workspace .github/prompts/ and .github/agents/ with junctions to
  # the system paths. VS Code's Copilot Chat resolves prompts from
  # .github/prompts/ (slash command surface) and the prompt's `agent:` field
  # then resolves to .github/agents/<name>.agent.md (behavior). Both need to be
  # locked or a user can edit the agent definition and change what
  # /speckit.plan actually does.
  $githubDir = Join-Path $TargetDir '.github'
  New-Item -ItemType Directory -Force -Path $githubDir | Out-Null

  $junctions = @(
    @{ Workspace = Join-Path $githubDir 'prompts'; System = $script:SystemPromptsPath },
    @{ Workspace = Join-Path $githubDir 'agents';  System = $script:SystemAgentsPath  }
  )
  foreach ($j in $junctions) {
    if (Test-Path $j.Workspace) { Remove-Item -Recurse -Force $j.Workspace }
    New-Item -ItemType Junction -Path $j.Workspace -Target $j.System | Out-Null
    Write-Host "Internal.SpecKit: linked $($j.Workspace) -> $($j.System)"
  }

  # 2. Belt-and-suspenders: refuse to commit anything under .github/prompts/
  # or .github/agents/. The junctions themselves wouldn't normally be tracked,
  # but if a determined user replaces a junction with a real folder, git could
  # otherwise pick it up.
  $gitignore = Join-Path $TargetDir '.gitignore'
  $marker    = '# Spec Kit prompts/agents are managed by IT (junctions to C:\ProgramData\speckit)'
  $lines     = @('.github/prompts/', '.github/agents/')

  $current = if (Test-Path $gitignore) { Get-Content $gitignore -ErrorAction SilentlyContinue } else { @() }
  $toAdd   = $lines | Where-Object { $current -notcontains $_ }
  if ($toAdd) {
    $block = @($marker) + $toAdd -join "`n"
    Add-Content -Path $gitignore -Value "`n$block"
    Write-Host "Internal.SpecKit: appended $($toAdd -join ', ') to .gitignore"
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
