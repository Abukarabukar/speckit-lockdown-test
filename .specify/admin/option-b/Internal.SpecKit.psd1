@{
  RootModule        = 'Internal.SpecKit.psm1'
  ModuleVersion     = '1.0.0'
  GUID              = 'a2b6f0e0-1234-4abc-9def-000000000001'
  Author            = 'Spec Kit Admins'
  CompanyName       = 'Your Org'
  Copyright         = '(c) Your Org. All rights reserved.'
  Description       = 'Corporate wrapper around the upstream specify CLI. Removes workspace prompt files on `specify init` and points VS Code at the system-managed prompts path.'
  PowerShellVersion = '5.1'
  FunctionsToExport = @('Invoke-InternalSpecify', 'Set-WorkspacePromptPolicy', 'Resolve-InitTarget', 'Test-IsInitInvocation')
  AliasesToExport   = @('specify')
  CmdletsToExport   = @()
  VariablesToExport = @()
}
