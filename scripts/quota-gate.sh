#!/bin/bash
# scripts/quota-gate.sh
# Gathers Jules session usage via GitHub API instead of Jules REST API.
# Use this to avoid 401 errors on the Jules /sessions endpoint.

set -e

# Configuration
REPO_ORG="Rich-Solutions"
WORKFLOW_FILE="jules.yml"
# JULES_PLAN_TIER: Free (15), Pro (100), Ultra (300)
PLAN=${JULES_PLAN_TIER:-Free}

# Thresholds from automations design
case $PLAN in
  Free)  LIMIT=15;  THRESHOLD=9  ;;
  Pro)   LIMIT=100; THRESHOLD=60 ;;
  Ultra) LIMIT=300; THRESHOLD=180 ;;
  *)     echo "Unknown plan: $PLAN"; exit 1 ;;
esac

# 24 hour cutoff for rolling window.
# GNU date (CI runners) uses `-d`; BSD date (macOS) uses `-v`. Suppress stderr
# INSIDE the substitution so the failing variant doesn't leak a usage error.
CUTOFF=$(date -u -d '24 hours ago' +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || \
         date -u -v-24H +'%Y-%m-%dT%H:%M:%SZ')

echo "Checking Jules quota for $REPO_ORG (Plan: $PLAN, Cap: $LIMIT, Threshold: $THRESHOLD)..."
echo "Window: $CUTOFF to $(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Get all repositories in the organization
REPOS=$(gh repo list "$REPO_ORG" --json name -q '.[].name')

TOTAL_RUNS=0
echo "Scanning workflow runs..."

for REPO in $REPOS; do
  # Count runs of the Jules workflow created after the cutoff
  # Note: Filtering by actor 'google-labs-jules[bot]' might exclude manual triggers,
  # but the design wants to count all 'sessions', so we count all runs of the workflow.
  COUNT=$(gh run list --repo "$REPO_ORG/$REPO" \
    --workflow "$WORKFLOW_FILE" \
    --created ">$CUTOFF" \
    --json databaseId --jq 'length' 2>/dev/null || echo "0")
  
  if [ "$COUNT" -gt 0 ]; then
    echo "  - $REPO: $COUNT"
    TOTAL_RUNS=$((TOTAL_RUNS + COUNT))
  fi
done

echo "----------------------------------------"
echo "Total Jules runs in last 24h: $TOTAL_RUNS"

if [ "$TOTAL_RUNS" -ge "$THRESHOLD" ]; then
  echo "STATUS: QUOTA EXCEEDED"
  echo "Current usage ($TOTAL_RUNS) is at or above the run threshold ($THRESHOLD)."
  exit 1
fi

echo "STATUS: QUOTA OK"
exit 0
