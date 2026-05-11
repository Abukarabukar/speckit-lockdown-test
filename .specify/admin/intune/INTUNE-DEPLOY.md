# Spec Kit lockdown — Intune deployment

End-to-end deployment of the local OS lock that prevents Spec Kit files from being modified on managed Windows devices, plus a privileged updater that pulls upstream prompt updates without breaking the lock.

## What gets enforced on every device

| Path on each device | ACL after deployment |
|---|---|
| `<repo>\.specify\**` | SYSTEM = Full Control, Admins = Full Control, Users = Read+Execute |
| `<repo>\.github\prompts\**` | SYSTEM = Full Control, Admins = Full Control, Users = Read+Execute |
| `<repo>\.vscode\**` | SYSTEM = Full Control, Admins = Full Control, Users = Read+Execute |

`<repo>` is any directory under `C:\Users\` (depth ≤ 6) that contains `.specify\extensions.yml` — the Spec Kit signature file.

Effective result: a developer cannot edit, delete, or replace any locked file. Copilot reads them normally. `git pull` runs by the scheduled SYSTEM task, which has Full Control, so upstream updates flow in seamlessly.

---

## Step 1 — Proactive remediation (the lock itself)

This is the recurring guardrail that re-applies the lock if anything drifts.

**Intune Admin Center → Devices → Scripts and remediations → Create script package**

| Field | Value |
|---|---|
| Name | Spec Kit lock |
| Description | Read-only ACL on .specify, .github/prompts, .vscode for all dev repos |
| Detection script | upload `detect.ps1` |
| Remediation script | upload `remediate.ps1` |
| Run script in 64-bit PowerShell | **Yes** |
| Run script using logged-on credentials | **No** (runs as SYSTEM) |
| Enforce script signature check | optional (sign for prod) |
| Schedule | Every 4 hours |
| Assignments | All corporate Windows devices (or a pilot group first) |

Intune fires the detection script every 4 hours. If any repo on the device is missing the lock, remediation runs and locks it.

---

## Step 2 — Privileged updater (so `git pull` keeps working)

Without this step, locked files cannot be updated by upstream changes — `git pull` would fail because the interactive user has no write access. The updater runs as SYSTEM, which the remediation grants Full Control, so it can pull cleanly.

### 2a. Package as a Win32 app

```pwsh
# On a build machine with the IntuneWinAppUtil tool:
IntuneWinAppUtil.exe -c .\intune -s register-updater.ps1 -o .\build
# Produces register-updater.intunewin
```

### 2b. Upload to Intune

**Apps → Windows → Add → Windows app (Win32) → upload `register-updater.intunewin`**

| Field | Value |
|---|---|
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File register-updater.ps1` |
| Uninstall command | `schtasks /Delete /TN SpecKitUpdater /F` |
| Install behavior | System |
| Device restart behavior | No restart |
| Detection rule | File path `C:\ProgramData\speckit\updater.ps1` exists |

Assign to the same device groups as Step 1.

### 2c. Provision the pull token

For private GitHub repos, the SYSTEM updater needs a token. Use **one** of:

```pwsh
# Option A — registry (recommended; rotate via Intune Configuration Profile → Settings catalog)
reg add 'HKLM\Software\YourOrg\SpecKit' /v PullToken /d <TOKEN> /f

# Option B — file (push as a separate Intune script)
mkdir C:\ProgramData\speckit
'<TOKEN>' | Set-Content C:\ProgramData\speckit\token.txt
icacls C:\ProgramData\speckit\token.txt /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(F)'
```

Token scope: `repo` read on the Spec Kit repos. Prefer a **GitHub App installation token** rotated by a small Azure Function over a long-lived PAT.

For public repos no token is needed — skip 2c.

---

## Step 3 — Verify on a pilot device

```pwsh
# 1. Force Intune to sync
Get-ScheduledTask -TaskName *IntuneManagementExtension* | Start-ScheduledTask

# 2. Confirm detect sees compliance after remediation has run
powershell.exe -ExecutionPolicy Bypass -File detect.ps1
# Expected: "Compliant: N Spec Kit repo(s) scanned, all locked." exit 0

# 3. Verify ACL on a locked path
icacls "C:\Users\<user>\<repo>\.specify"
# Expected ACEs:
#   NT AUTHORITY\SYSTEM:(OI)(CI)(F)
#   BUILTIN\Administrators:(OI)(CI)(F)
#   BUILTIN\Users:(OI)(CI)(RX)

# 4. Confirm the scheduled task is registered and runs
schtasks /Query /TN SpecKitUpdater /V /FO LIST
schtasks /Run /TN SpecKitUpdater
Get-Content C:\ProgramData\speckit\updater.log -Tail 20

# 5. Attempt a tamper as the regular user
"# vandalize" | Out-File "C:\Users\<user>\<repo>\.specify\init-options.json" -Append
# Expected: "Access to the path ... is denied."
```

---

## Step 4 — Rollout sequence

1. **Pilot ring** (5–10 dev volunteers) — Step 1 only, monitor for false positives in detection.
2. **Pilot ring + updater** (Step 2) — add private-repo support, validate pulls finish.
3. **Broader ring** (20–50 devices).
4. **Full org rollout**.
5. **Combine with the GitHub org push ruleset** (`ruleset-org.json`). At this point you have:
   - Server-side: changes to locked paths rejected at push time (Layer 1).
   - Client-side: changes to locked paths rejected at write time (Layer 2).
   - Reconciliation: SYSTEM scheduled task keeps every device in sync with the canonical version.

---

## Recovery / emergency unlock

If a dev needs write access (legitimate Spec Kit maintainer, debugging the lock itself):

```pwsh
# As a local admin or by remote PSExec as SYSTEM:
.\uninstall.ps1
# Or scoped to one repo:
icacls "<repo>\.specify"        /reset /T /Q
icacls "<repo>\.github\prompts" /reset /T /Q
icacls "<repo>\.vscode"         /reset /T /Q
```

To prevent the next remediation cycle from re-locking, exclude that device from the script-package assignment temporarily.

---

## Threat model: what's still possible

- **A user with local admin** can `icacls /reset` and edit. Corporate Windows devices typically deny local admin to developers — that's the prerequisite for this control to be effective.
- **A user can copy the repo elsewhere and edit there.** Their copy still can't push (Layer 1 still blocks). The copy is a personal sandbox; it cannot poison teammates.
- **A user with admin on their own personal device** (not corporate-managed) is outside Intune's scope. The server-side ruleset is what protects you in that case — they can edit but not propagate.
- **Tampering with the scheduled task** is prevented by the file ACL on `C:\ProgramData\speckit\updater.ps1` (SYSTEM/Admins only) plus the task itself being SYSTEM-owned.
