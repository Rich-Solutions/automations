# GitHub App wiring — runbook

The campaign workflows authenticate cross-repo `workflow_dispatch` calls as a
**GitHub App** (not a PAT), per design §3.1. This is the one piece that needs
org-admin access to complete — it could not be automated from the build session
(the build token lacked the org `actions secrets` permission; `gh secret list
--org Rich-Solutions` returned HTTP 403).

What the workflows already expect (so this runbook just has to satisfy it):

| Workflow reference | Type | Value the App must provide |
|---|---|---|
| `secrets.AUTOMATIONS_APP_ID` | org secret | the App's numeric App ID |
| `secrets.AUTOMATIONS_APP_PRIVATE_KEY` | org secret | the App's PEM private key |
| `secrets.JULES_PLAN_TIER` | org secret | `Free` \| `Pro` \| `Ultra` (quota-gate plan) |

The token is minted with [`actions/create-github-app-token@v1`] scoped to
`owner: Rich-Solutions`. (The design named `tibdex/github-app-token`; that
action is archived, so the GitHub-maintained replacement is used instead.)

## 1. Create the App (org admin)

Settings → Developer settings → GitHub Apps → **New GitHub App**, on the
`Rich-Solutions` org.

- **Name:** `rich-solutions-automations`
- **Homepage URL:** the repo URL (any valid URL is fine)
- **Webhook:** uncheck **Active** (no webhook needed — this is dispatch-only)
- **Repository permissions:**
  - **Actions:** Read and write  ← required to `workflow_dispatch` target repos
  - **Contents:** Read-only      ← checkout / read `jules.yml`
  - **Pull requests:** Read and write (optional — only if a future campaign
    wants to label/comment on PRs directly; not used by current workflows)
- **Where can this App be installed?** Only on this account.

Click **Create GitHub App**, then note the **App ID**.

## 2. Generate a private key

On the App page → **Private keys** → **Generate a private key**. A `.pem`
downloads. Keep it secret; it is the App's credential.

## 3. Install the App on the org

App page → **Install App** → install on `Rich-Solutions`. Grant it the target
repos: at minimum every repo enrolled in `targets.yml` —
`Azimuth`, `Aethel`, `Synapse`, `OptX_Trading` — plus `automations` itself.
(Selecting **All repositories** is simplest and future-proofs new enrollments.)

## 4. Set the org secrets

Org → Settings → Secrets and variables → Actions → **New organization secret**.
Scope each to the `automations` repo (or all repos):

```text
AUTOMATIONS_APP_ID          = <the numeric App ID from step 1>
AUTOMATIONS_APP_PRIVATE_KEY = <full contents of the .pem from step 2>
JULES_PLAN_TIER             = Free        # or Pro / Ultra
```

CLI equivalent (run as an org admin whose token has the
`admin:org` / fine-grained *actions secrets* permission):

```bash
gh secret set AUTOMATIONS_APP_ID          --org Rich-Solutions --app actions --body "<APP_ID>"
gh secret set AUTOMATIONS_APP_PRIVATE_KEY --org Rich-Solutions --app actions < path/to/app.pem
gh secret set JULES_PLAN_TIER             --org Rich-Solutions --app actions --body "Free"
```

## 5. Verify (dry-run only — never live)

`workflow_dispatch` only registers from the **default branch**, so this can run
only after the feature branch merges to `main`.

```bash
# dry_run defaults to true on manual runs — this triggers NO live campaign traffic.
gh workflow run latency-review.yml --repo Rich-Solutions/automations --ref main
gh run watch --repo Rich-Solutions/automations
```

Expected: the `quota-gate` job mints an App token and runs
`scripts/quota-gate.sh`; if quota is OK, the `dispatch` job runs
`scripts/dispatch.sh` with `DRY_RUN=1` and logs the dispatches it *would* make
without triggering target repos.

To confirm the App token (not a PAT) authenticated, check the `dispatch` job log
for the App-token step succeeding, and that dispatch lines reference the App
installation rather than a user.

## Per-repo prerequisite (design §6)

Each target repo needs the on-demand entrypoint job in its own `jules.yml`: a
`workflow_dispatch` trigger accepting `campaign` and `context` string inputs
that forwards them to its Jules session. The dispatch fails for any repo missing
this entrypoint — Azimuth already has `jules.yml`; the others need the job
added before their first live (non-dry-run) campaign.

[`actions/create-github-app-token@v1`]: https://github.com/actions/create-github-app-token
