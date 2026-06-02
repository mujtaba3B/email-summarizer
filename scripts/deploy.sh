#!/usr/bin/env bash
#
# deploy.sh - the email-summarizer deploy, as an executable runbook.
#
# One target: the Cloudflare Worker named "email-reader". This script IS the
# procedure; DEPLOY.md is the narrative around it (prereqs, rollback, why the
# checks exist). It is a thin, ordered wrapper over the documented command so
# the steps cannot drift from reality. It ends by running
# devops check (against deploy.json): the deploy is not "done" until it passes.
#
# Usage:
#   scripts/deploy.sh            # deploy the worker, then verify
#   scripts/deploy.sh check      # skip deploy, just run the post-deploy check
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TARGET="${1:-deploy}"

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

case "$TARGET" in
  deploy)
    step "Deploy Worker (Cloudflare edge)"
    npx wrangler deploy
    ;;
  check)
    : ;;  # skip deploy, fall through to the post-deploy check only
  *)
    echo "unknown target: ${TARGET} (use: deploy | check)" >&2
    exit 2
    ;;
esac

step "Post-deploy check (gates the deploy)"
# Checks are declared in deploy.json and run by the shared deploy kit (devops);
# the gating logic lives once in ~/dev/ops, not in this repo. See DEPLOY.md.
( cd "$REPO_ROOT" && devops check )

step "Deploy complete and verified"
