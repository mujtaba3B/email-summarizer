#!/usr/bin/env bash
#
# version.sh - deploy-kit hook: the deployed worker reports the version in this
# tree (a freshness invariant). The HTTP assertions in deploy.json cannot express
# "live == repo", so it lives here as an escape-hatch hook (exit 0 = pass).
#
set -uo pipefail
BASE="${SUMMARIZER_BASE:-https://email-reader.mujtaba-badat.workers.dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Anchor on an object-key position so a bare-word `version` substring can't match.
repo_version="$(grep -oE '[{,][[:space:]]*version:[[:space:]]*"[0-9][^"]*"' "${ROOT}/src/worker.ts" 2>/dev/null \
  | grep -oE '"[0-9][^"]*"' | tr -d '"' | head -1 || true)"
live_version="$(curl -sS -m 12 --connect-timeout 5 "${BASE}/" 2>/dev/null \
  | grep -oE '"version":"[^"]*"' | head -1 | grep -oE '[0-9][^"]*' || true)"

if [ -z "$repo_version" ]; then
  echo "could not read a version from src/worker.ts"; exit 1
fi
if [ "$live_version" = "$repo_version" ]; then
  echo "deployed version ${live_version} matches repo"; exit 0
fi
echo "deployed version '${live_version}' != repo version '${repo_version}' (failed/no-op deploy, stale worker, or wrong account)"
exit 1
