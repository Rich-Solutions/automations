# Rich-Solutions/automations

The operational hub for the **Rich-Solutions** organization. This repository manages fleet-wide maintenance, self-healing tasks, and organization-level quotas.

## 🛠 Components

### `targets.yml` — fleet registry
Single source of truth for cross-repo dispatch: enrolled repos, the campaigns
each opts into, and the per-campaign JSON context payload (focus / labels /
risk). Schema documented inline; see design §3.2.

### `scripts/quota-gate.sh` — spend guard
- **Purpose**: Counts Jules workflow runs across all org repos in a rolling
  24h window and blocks (exit 1) when usage is at/above the plan threshold.
- **Why**: Avoids 401s on the Jules REST API by using GitHub run history as the
  signal. Plan tier via `JULES_PLAN_TIER` (Free 9 / Pro 60 / Ultra 180).
- **Usage**: Invoked first in every campaign workflow; dispatch is gated on it.

### `scripts/dispatch.sh` — trigger layer
Reads `targets.yml`, builds the campaign context payload, and issues
`workflow_dispatch` to each enrolled repo's `jules.yml` entrypoint. Honors
`DRY_RUN=1` to log dispatches without triggering target repos.

### `.github/workflows/` — campaigns
| Workflow | Schedule | Focus |
|---|---|---|
| `latency-review.yml` | Weekly Mon 06:00 UTC | Hot paths |
| `redundancy-reduction.yml` | 1st/15th 06:00 UTC | Duplicate logic ≥15 lines |
| `refactor-sweep.yml` | Monthly 1st 08:00 UTC | Naming, dead code (low-risk) |

Each runs on its schedule plus `workflow_dispatch` (with a `dry_run` input that
**defaults to true** — manual runs never send live campaign traffic).

## 🔐 Authentication
Cross-repo dispatch authenticates as a **GitHub App**, not a PAT. Setup runbook:
[`docs/github-app-setup.md`](docs/github-app-setup.md). Requires org secrets
`AUTOMATIONS_APP_ID`, `AUTOMATIONS_APP_PRIVATE_KEY`, `JULES_PLAN_TIER`.

## 🚀 Future Roadmap

- [x] **Fleet Registry** (`targets.yml`)
- [x] **Campaign workflows** (latency / redundancy / refactor)
- [ ] **GitHub App secrets** — needs org admin (see runbook)
- [ ] **Organization Health Check**: Weekly audits of security, deps, CI health.
- [ ] **Self-Healing Workflows**: Automated unblocking / retry for stuck pipelines.
