# Spec Kit lockdown — Option B (system-managed prompts + wrapper)

This package replaces per-repo prompt-file ACLs with a single system-managed prompt path plus a corporate wrapper around `specify`. End-state on every device:

- `C:\ProgramData\speckit\prompts\` holds the canonical Spec Kit prompts. **Users have Read+Execute only**; SYSTEM/Admins have Full Control.
- Every new repo created with `specify init` has `.github/prompts/` as a **directory junction** pointing at the system path. VS Code's Copilot Chat sees prompts in the expected workspace location; the OS transparently routes all reads/writes to the locked system path.
- Updates flow through one channel: a SYSTEM scheduled task pulls a central `speckit-prompts` repo every 4 hours into the system path. All workspaces see new prompts immediately — no `git pull` in user repos.
- The corporate org's GitHub push ruleset (Layer 1, see `..\ruleset-org.json`) blocks any attempt to commit `.github/prompts/speckit.*.prompt.md` from a user who reinstalls upstream Spec Kit.

## Files

| File | Purpose |
|---|---|
| `Internal.SpecKit.psm1` / `.psd1` | The PowerShell wrapper around `specify`. Removes workspace prompts on `init`, writes `chat.promptFilesLocations` into `.vscode/settings.json`. |
| `install-wrapper.ps1` | Copies the module to `$PSHOME\Modules\Internal.SpecKit\`, ACLs it, and adds the import to the AllUsers profile (PowerShell 5.1 and 7). |
| `programdata-setup.ps1` | Creates `C:\ProgramData\speckit\prompts`, clones the central prompts repo into it, applies the read-only ACL. |
| `programdata-sync.ps1` | SYSTEM-context git puller for the system path. Runs every 4 hours. |
| `register-sync-task.ps1` | Win32-app installer that drops `programdata-sync.ps1` and registers the scheduled task. |
| `detect.ps1` | Intune proactive-remediation detection (returns 0 when fully installed). |
| `remediate.ps1` | Intune remediation; runs the three install scripts in order. |
| `uninstall.ps1` | Full removal for retirement / debugging. |

## Prerequisites

1. **Upstream `specify` installed system-wide and renamed to `specify-upstream`**:

   ```pwsh
   # On the device base image (one time):
   uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
   $real = (Get-Command specify).Source
   Rename-Item -Path $real -NewName 'specify-upstream.exe'
   ```

2. **A central GitHub repo** holding the canonical prompts, e.g. `<ORG>/speckit-prompts`, owned by `@<ORG>/speckit-admins`.

3. **Registry value or env var** pointing at it:
   - `HKLM\Software\YourOrg\SpecKit\PromptsRepo = https://github.com/<ORG>/speckit-prompts.git`
   - or `SPECKIT_PROMPTS_REPO=...`

4. **(Recommended) AppLocker / WDAC policy** that denies execution of `specify.exe` and the upstream `specify-upstream.exe` outside `$PSHOME\Modules\Internal.SpecKit\` and the corp-managed install path. Closes the "user runs upstream directly" gap.

## Deployment via Intune

1. **Win32 app: Internal.SpecKit wrapper**
   - Install: `powershell -NoProfile -ExecutionPolicy Bypass -File install-wrapper.ps1`
   - Uninstall: `powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1`
   - Detection: file exists `C:\Program Files\WindowsPowerShell\Modules\Internal.SpecKit\Internal.SpecKit.psm1`
   - Run as System.

2. **Win32 app: System prompts setup**
   - Install: `powershell -NoProfile -ExecutionPolicy Bypass -File programdata-setup.ps1`
   - Detection: file exists `C:\ProgramData\speckit\prompts\.git\HEAD`

3. **Win32 app: Sync scheduled task**
   - Install: `powershell -NoProfile -ExecutionPolicy Bypass -File register-sync-task.ps1`
   - Uninstall: `schtasks /Delete /TN SpecKitPromptsSync /F`
   - Detection: `schtasks /Query /TN SpecKitPromptsSync` returns 0.

4. **Proactive remediation: drift check**
   - Detection: `detect.ps1`
   - Remediation: `remediate.ps1`
   - Schedule: every 4 hours.

## What "works" looks like on a corp device

```pwsh
PS> cd C:\Users\dev\source\my-feature
PS> specify init . --integration copilot
# upstream specify runs (creates .specify, .github/prompts, .vscode)
# Internal.SpecKit post-processes:
#   linked .github\prompts -> C:\ProgramData\speckit\prompts
#   appended .github/prompts/ to .gitignore

PS> ls .github
# prompts (junction → C:\ProgramData\speckit\prompts)

PS> code .
# In Copilot Chat:
PS> /speckit.plan
# Copilot loads C:\ProgramData\speckit\prompts\speckit.plan.prompt.md (read-only)
# Slash command works. User cannot edit.

# Tamper attempt:
PS> Set-Content C:\ProgramData\speckit\prompts\speckit.plan.prompt.md '# vandalize'
# → Access to the path is denied.
```

## Recovery / legitimate prompt edits

A dev who needs to change a prompt:

1. Clones `<ORG>/speckit-prompts` to a working area.
2. Edits there, opens a PR.
3. PR reviewed by `speckit-admins` and merged.
4. Next sync cycle (≤ 4h) ships the new prompt to every device.
