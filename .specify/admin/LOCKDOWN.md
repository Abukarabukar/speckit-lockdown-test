# Spec Kit lockdown — admin runbook

End users **cannot** modify Spec Kit prompts, templates, or related configuration anywhere — not on GitHub, not on their own machines. Copilot reads everything normally; nothing about the slash commands changes.

## Recommended architecture (Option B + GitHub ruleset)

> **Use Option B as the primary local-enforcement model.** See [`option-b/README.md`](option-b/README.md) for the full deliverable.

```
┌──────────────────────────────────────────────────────────────────┐
│  Layer 1 — GitHub server                                          │
│  Org push ruleset (ruleset-org.json) on every Spec Kit repo       │
│  + CODEOWNERS + lock-speckit.yml CI guard                         │
│  Blocks: any commit to .github/prompts/, .specify/, .vscode/      │
└──────────────────────────────────────────────────────────────────┘
                                ↑
                                │ (server rejects push with GH013)
                                │
┌──────────────────────────────────────────────────────────────────┐
│  Layer 2 — Every corp device (Intune)                             │
│  C:\ProgramData\speckit\prompts\  ← SYSTEM:F  Admins:F  Users:RX  │
│  Internal.SpecKit PowerShell wrapper shadows `specify init`:      │
│    - removes workspace .github/prompts/                           │
│    - sets chat.promptFilesLocations to the system path            │
│    - adds .github/prompts/ to .gitignore                          │
│  SpecKitPromptsSync scheduled task (SYSTEM, every 4h):            │
│    - git pulls central <ORG>/speckit-prompts repo                 │
│    - users keep RX, SYSTEM keeps F — no credential dance          │
└──────────────────────────────────────────────────────────────────┘
```

### What this prevents end-to-end

| Vector | Layer that catches it |
|---|---|
| User edits `C:\ProgramData\speckit\prompts\*.prompt.md` | Layer 2 NTFS ACL → `Access denied` |
| User edits workspace `.github/prompts/*` | The folder doesn't exist after `specify init` (wrapper deletes it) |
| User runs upstream `specify init` to recreate workspace prompts | Wrapper shadows `specify`; AppLocker can hard-block upstream binary |
| User commits a hand-crafted workspace prompts dir | Layer 1 org push ruleset rejects the push |
| User edits `.specify/templates/*` | Layer 1 covers it; per-repo `.specify/` ACL can be layered if needed |

### Why Option B is preferred over the per-repo ACL approach

| | Per-repo ACL (`intune/`) | Option B (`option-b/`) |
|---|---|---|
| State to lock | Every clone, every machine | One folder, every machine |
| Discovery cycle | Intune scans for `.specify\extensions.yml` every 4h | None — wrapper acts at `specify init` time |
| Prompt updates | Per-repo `git pull` as SYSTEM | One central repo, one SYSTEM puller |
| User confusion | Sees `.github/prompts/` but can't edit them | No `.github/prompts/` at all |
| Failure mode if Intune is slow | New repo unlocked until next remediation | New repo wrapper-processed immediately |

The per-repo package (`.specify/admin/intune/`) is retained for backwards compatibility / hybrid rollouts, but new deployments should use Option B.

## GitHub server-side enforcement (Layer 1 — required regardless of model)

Identical for both models. Apply once at the org level.

---

## Personal-account test setup (public repo)

**Important constraint:** GitHub rejects `push` rulesets on personal-account repos ("only org-owned repos can have push rules"). On a personal account, use a **branch** ruleset for `main` that requires PRs + code-owner review, combined with the `lock-speckit` workflow as a required status check. The org-level **push** ruleset (`ruleset-org.json`) is what you'll apply at the company.

Applied configuration on `Abukarabukar/speckit-lockdown-test` (ruleset id `16246633`):

```pwsh
# 1. Authenticate
gh auth login --web --git-protocol https --hostname github.com --scopes "repo,workflow,read:org"

# 2. Create the public repo and push
gh repo create Abukarabukar/speckit-lockdown-test --public --source . --remote origin --push

# 3. Apply the branch ruleset (PRs + code-owner review + required `guard` check)
gh api -X POST -H "Accept: application/vnd.github+json" `
  /repos/Abukarabukar/speckit-lockdown-test/rulesets `
  --input .specify/admin/ruleset-repo-branch.json
```

Verification result: opening a PR that edits `.specify/init-options.json` blocks the merge with `mergeStateStatus=BLOCKED`, the `guard` workflow fails with the message *"This PR touches locked Spec Kit files and has no APPROVED review yet. A member of @Abukarabukar/speckit-admins must approve."*, and `reviewDecision=REVIEW_REQUIRED` (CODEOWNERS).

Admin bypass works: pushing directly to `main` as the repo admin succeeds (bypass actor = `RepositoryRole 5`).

To list / disable / update the ruleset:

```pwsh
gh api /repos/<YOUR_USERNAME>/<REPO>/rulesets
gh api -X PUT /repos/<YOUR_USERNAME>/<REPO>/rulesets/<ID> --input .specify/admin/ruleset-repo.json
gh api -X DELETE /repos/<YOUR_USERNAME>/<REPO>/rulesets/<ID>
```

---

## Production rollout (GitHub Enterprise Cloud, org-wide)

The org-level ruleset (`.specify/admin/ruleset-org.json`) targets every repo in the org that has the **custom property** `uses_speckit=true`. One ruleset, applied centrally, blocks edits across all participating repos.

```pwsh
# 1. Create the admin team (org admins should add members)
gh api -X POST /orgs/<ORG>/teams -f name=speckit-admins -f privacy=closed

# 2. Resolve the team id and patch it into ruleset-org.json
$TEAM_ID = gh api /orgs/<ORG>/teams/speckit-admins --jq .id

# 3. Declare a custom property for opt-in
gh api -X PUT /orgs/<ORG>/properties/schema/uses_speckit `
  -f value_type=string -f default_value=false -F allowed_values='["true","false"]'

# 4. Tag each Spec Kit repo with uses_speckit=true (or set on all repos)
gh api -X PATCH /repos/<ORG>/<REPO>/properties/values `
  -F 'properties=[{"property_name":"uses_speckit","value":"true"}]'

# 5. Edit ruleset-org.json to set actor_id = $TEAM_ID, then create the ruleset
gh api -X POST /orgs/<ORG>/rulesets --input .specify/admin/ruleset-org.json
```

After this:
- All Spec Kit repos in the org reject pushes to locked paths from anyone outside `@<ORG>/speckit-admins`.
- New repos that need the lock are opted in by setting `uses_speckit=true` — no per-repo ruleset config.
- Updating prompts is an admin-only operation, ideally via a PR from a fork or branch with the bypass actor approving.

---

## Updating locked prompts as an admin

1. As a `speckit-admins` member, create a branch on a locked repo.
2. Edit the prompt file, commit, push (your team is in the bypass list, so the push succeeds).
3. Open a PR. The `lock-speckit` workflow will pass because an admin approved.
4. Merge.

For org-wide prompt updates, prefer a central template/automation repo that pushes a vetted version into every Spec Kit repo on a schedule, rather than hand-editing each repo.

---

## Verifying the lock

| Test | Expected result |
|---|---|
| Non-admin pushes a change to `.specify/init-options.json` | Push rejected by GitHub with `GH013: Repository rule violations` |
| Non-admin opens a PR touching `.github/prompts/speckit.plan.prompt.md` | `lock-speckit / guard` check fails; merge blocked by CODEOWNERS |
| Admin (bypass actor) pushes the same change | Push accepted; PR check passes |
| User tries to delete `.github/workflows/lock-speckit.yml` | Push rejected (path is in the ruleset) |
| User tries to disable the ruleset via API | Rejected unless org/repo admin |
