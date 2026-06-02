#!/usr/bin/env bash
#
# postdeploy-check.sh - post-deploy smoke test for the email-summarizer worker.
#
# A short, read-only set of assertions that GATE a deploy: deploy.sh calls this
# at the end, and a non-zero exit means "the deploy is not healthy, do not
# consider it done". Safe to run by hand any time to spot-check prod. None of
# the checks spends an OpenAI call or needs a secret.
#
# Why each check exists is documented inline and in DEPLOY.md.
#
# Usage:
#   scripts/postdeploy-check.sh
#   SUMMARIZER_BASE=https://email-reader.example.workers.dev scripts/postdeploy-check.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${SUMMARIZER_BASE:-https://email-reader.mujtaba-badat.workers.dev}"
CURL=(curl -sS -m 15 --connect-timeout 5)

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAILED=1; }
FAILED=0

echo "email-summarizer post-deploy check against ${BASE}"

# --- Check 1: worker is alive -------------------------------------------------
# GET / is public and dependency-free; a 200 means the worker is deployed and
# reachable at the edge.
get_body="$("${CURL[@]}" "${BASE}/" 2>/dev/null || true)"
code="$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${BASE}/" 2>/dev/null || echo 000)"
if [ "$code" = "200" ]; then
  pass "GET / returned 200"
else
  fail "GET / returned ${code} (expected 200; worker not deployed or route broken)"
fi

# --- Check 2: real worker, not a fallback -------------------------------------
# A 404 placeholder or a half-broken deploy would not both identify as
# email-reader on GET and enforce the auth boundary on POST. The unauthenticated
# POST must return 401 (the worker reached authorize() and rejected); a 200 or a
# 500 there means the auth gate is gone or the worker is erroring before it. No
# OpenAI call and no token are spent.
case "$get_body" in
  *'"service":"email-reader"'*) pass 'GET / identifies as service:"email-reader"' ;;
  *) fail "GET / did not identify as email-reader (got: ${get_body:0:120})" ;;
esac
post_code="$("${CURL[@]}" -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -d '{"links":[],"readingTime":5}' \
  "${BASE}/" 2>/dev/null || echo 000)"
if [ "$post_code" = "401" ]; then
  pass "unauthenticated POST / returned 401 (auth boundary is wired)"
else
  fail "unauthenticated POST / returned ${post_code} (expected 401; auth gate missing or worker erroring before it)"
fi

# --- Check 3: deployed version == repo version (freshness invariant) ----------
# GET / reports a version string sourced from src/worker.ts. If the live worker
# does not report the version in this working tree, the worker serving this
# route is NOT the code we just built: a failed/no-op deploy, a stale worker, or
# the wrong Cloudflare account. (Bump the version in src/worker.ts on behavioral
# deploys so this catches a regression rather than always matching.)
repo_version="$(grep -oE 'version[":[:space:]]+"[0-9][^"]*"' "${REPO_ROOT}/src/worker.ts" 2>/dev/null \
  | grep -oE '[0-9][^"]*' | head -1 || true)"
live_version="$(printf '%s' "$get_body" | grep -oE '"version":"[^"]*"' | head -1 | grep -oE '[0-9][^"]*' || true)"
if [ -z "$repo_version" ]; then
  fail "could not read a version string from src/worker.ts (check 3 cannot run)"
elif [ "$live_version" = "$repo_version" ]; then
  pass "deployed version ${live_version} matches repo (${repo_version})"
else
  fail "deployed version '${live_version}' != repo version '${repo_version}' (worker on this route is not the code you just built: failed/no-op deploy, stale worker, or wrong account)"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "post-deploy check: PASS"
  exit 0
else
  echo "post-deploy check: FAIL (see above)"
  exit 1
fi
