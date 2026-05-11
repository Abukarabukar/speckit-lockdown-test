# Spec Kit lockdown — admin runbook

This repo's Spec Kit files are locked. End users **cannot** modify:

- `.github/prompts/speckit.*.prompt.md` — Copilot slash-command prompts
- `.specify/**` — templates, scripts, workflows, integrations, memory
- `.vscode/**` — editor configuration shipped by Spec Kit
- `.github/CODEOWNERS` — the lock itself
- `.github/workflows/lock-speckit.yml` — the CI guard

Enforcement uses three layers:

1. **GitHub push ruleset** with `file_path_restriction` (server-side, hard block on `git push`).
2. **CODEOWNERS** + "Require review from Code Owners" branch protection (PR merge gate).
3. **CI guard workflow** that verifies an admin approved any PR touching locked paths.

Copilot still reads the prompt files normally — none of these layers restrict reads.

---

## Personal-account test setup (public repo)

Push rulesets with `file_path_restriction` are available on public repos across all plans, so you can verify the lock works against a personal GitHub.com account before rolling out at the company.

```pwsh
# 1. Authenticate
gh auth login

# 2. Create a public repo from this directory
gh repo create <YOUR_USERNAME>/speckit-lockdown-test --public --source . --push

# 3. Apply the repo-level ruleset
#    (file path: .specify/admin/ruleset-repo.json)
gh api `
  -X POST `
  -H "Accept: application/vnd.github+json" `
  /repos/<YOUR_USERNAME>/speckit-lockdown-test/rulesets `
  --input .specify/admin/ruleset-repo.json
```

The included `ruleset-repo.json` uses bypass actor `RepositoryRole 5` (admin role) so you, as the repo owner, can still push when you need to update prompts. To **prove** the lock works, temporarily remove the bypass list, attempt to edit `.specify/init-options.json`, push, and observe the push being rejected by the server with `GH013: Repository rule violations found`.

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
