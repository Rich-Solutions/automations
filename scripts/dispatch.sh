#!/usr/bin/env bash
# scripts/dispatch.sh
# Reads targets.yml and dispatches a campaign to every enrolled target repo's
# on-demand entrypoint (workflow_dispatch). The target repo owns its Jules
# session; this script is only the trigger layer (design §3.4).
#
# Usage:
#   CAMPAIGN=latency-review scripts/dispatch.sh
#   CAMPAIGN=refactor-sweep DRY_RUN=1 scripts/dispatch.sh
#
# Env:
#   CAMPAIGN   (required)  campaign name; must exist in targets.yml `campaigns:`
#   DRY_RUN    (optional)  "1"/"true" => print the gh command, do not dispatch
#   TARGETS    (optional)  path to registry (default: targets.yml)
#   GH_TOKEN   (optional)  token gh uses; in CI this is the GitHub App token
#
# Exit codes: 0 ok (incl. dry-run), 2 usage/config error, 1 a dispatch failed.

set -euo pipefail

CAMPAIGN="${CAMPAIGN:-}"
TARGETS="${TARGETS:-targets.yml}"
DRY_RUN="${DRY_RUN:-0}"

case "$DRY_RUN" in
  1 | true | TRUE | yes) DRY_RUN=1 ;;
  *) DRY_RUN=0 ;;
esac

if [[ -z "$CAMPAIGN" ]]; then
  echo "ERROR: CAMPAIGN env var is required" >&2
  exit 2
fi
if [[ ! -f "$TARGETS" ]]; then
  echo "ERROR: registry not found: $TARGETS" >&2
  exit 2
fi
for bin in yq jq gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: missing dependency: $bin" >&2; exit 2; }
done

# --- Resolve campaign-level config from the registry --------------------------
if [[ "$(yq -r ".campaigns | has(\"$CAMPAIGN\")" "$TARGETS")" != "true" ]]; then
  echo "ERROR: campaign '$CAMPAIGN' is not defined in $TARGETS" >&2
  exit 2
fi

ENTRYPOINT="$(yq -r '.defaults.entrypoint_workflow' "$TARGETS")"
DEFAULT_BRANCH="$(yq -r '.defaults.branch // "main"' "$TARGETS")"

# Build the JSON context payload (design §4): focus areas, PR labels, risk.
# Emitted compact so it round-trips cleanly as a single workflow_dispatch input.
CONTEXT="$(yq -o=json -I=0 "
  .campaigns.\"$CAMPAIGN\" | {
    \"campaign\": \"$CAMPAIGN\",
    \"risk\": .risk,
    \"labels\": .labels,
    \"focus\": .focus,
    \"params\": (.params // {})
  }
" "$TARGETS")"

echo "Campaign     : $CAMPAIGN"
echo "Entrypoint   : $ENTRYPOINT"
echo "Context      : $CONTEXT"
echo "Dry run      : $DRY_RUN"
echo "----------------------------------------"

# --- Iterate enrolled repos ---------------------------------------------------
FAILED=0
DISPATCHED=0

# Repos that list this campaign and are not explicitly disabled.
# Portable read loop (avoids `mapfile`, a bash 4+ builtin absent on macOS bash 3.2).
REPOS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && REPOS+=("$line")
done < <(yq -r "
  .repos[]
  | select(.campaigns[] == \"$CAMPAIGN\")
  | select(.enrolled != false)
  | .name
" "$TARGETS")

if [[ "${#REPOS[@]}" -eq 0 ]]; then
  echo "No enrolled repos for campaign '$CAMPAIGN'. Nothing to dispatch."
  exit 0
fi

for REPO in "${REPOS[@]}"; do
  BRANCH="$(yq -r ".repos[] | select(.name == \"$REPO\") | .branch // \"$DEFAULT_BRANCH\"" "$TARGETS")"
  echo "-> $REPO (ref: $BRANCH)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "   DRY_RUN: gh workflow run $ENTRYPOINT --repo $REPO --ref $BRANCH \\"
    echo "            -f campaign=$CAMPAIGN -f context=<json>"
    DISPATCHED=$((DISPATCHED + 1))
    continue
  fi

  if gh workflow run "$ENTRYPOINT" \
       --repo "$REPO" \
       --ref "$BRANCH" \
       -f "campaign=$CAMPAIGN" \
       -f "context=$CONTEXT"; then
    echo "   dispatched"
    DISPATCHED=$((DISPATCHED + 1))
  else
    echo "   DISPATCH FAILED" >&2
    FAILED=$((FAILED + 1))
  fi
done

echo "----------------------------------------"
echo "Dispatched: $DISPATCHED  Failed: $FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
