# Deploying email-summarizer

The deploy procedure lives in `scripts/deploy.sh` (executable runbook); this file is the narrative around it: prereqs, rollback, and *why* each post-deploy check exists. If the steps and this doc ever disagree, the script wins. It follows the `~/dev` deploy convention (`DEPLOY.md` + `scripts/deploy.sh` + `deploy.json`, run by the shared `devops` kit); `sms-hero` is the reference implementation.

## What deploys where

One target: a single Cloudflare Worker.

| Target | What | Command of record |
|---|---|---|
| `worker` | The summarizer backend (Cloudflare Worker named `email-reader`) | `npx wrangler deploy` |

The worker name (`email-reader`) and the project name (`email-summarizer`) differ for historical reasons; see `~/dev/where-things-run.json`. The Tampermonkey userscript in `src/client/` reads the open Gmail message and POSTs `{links, readingTime}` to the worker, which fetches each article, calls the summarizer adapter (OpenAI by default), and returns structured bullets.

Public URL: `https://email-reader.mujtaba-badat.workers.dev`.

## Quick start

```bash
scripts/deploy.sh            # deploy the worker, then verify
scripts/deploy.sh check      # skip deploy, just run the post-deploy check
```

The script ends by running `devops check` (against `deploy.json`). The deploy is **not done** until that passes.

## Prereqs

- `npx wrangler` authenticated for the Cloudflare account (`50980fd4...`). The deploy is a no-op surprise if you are logged into the wrong account, so the post-deploy check re-confirms the live worker's identity.
- Worker secrets (the OpenAI key and the shared `AUTH_TOKEN`) are set with `wrangler secret put ...`, sourced from the 1Password `AI CLI` vault. They are NOT in this repo.

## Post-deploy checks (and why each exists)

The checks are declared in **`deploy.json`** (the standard descriptor) and run by the shared deploy kit: `devops check`. The gating logic lives once in `~/dev/ops`, not in this repo. None of the checks spends an OpenAI call or needs a secret.

1. **`alive`: `GET /` returns 200.** The worker is deployed and reachable at the edge. A dependency-free liveness check.
2. **`identity`: `GET /` is 200 and contains `"service":"email-reader"`.** Proves the right worker is serving this route, not a blank/placeholder.
3. **`auth-boundary`: an unauthenticated `POST /` returns 401.** The "real worker, not a fallback" check: the worker reached `authorize()` and rejected, so the request-handling logic actually shipped. A `200` or `500` would mean the auth gate is gone or the worker erroring before it.
4. **`version-fresh` (hook, `scripts/checks/version.sh`): the deployed `version` equals `src/worker.ts`.** A freshness invariant the HTTP assertions cannot express, so it lives as an escape-hatch hook. A mismatch means the worker serving this route is NOT the code you just built (failed/no-op deploy, stale worker, wrong Cloudflare account). Bump the `version` string in `src/worker.ts` on a behavioral deploy so this catches a regression.

## Rollback

- `npx wrangler rollback` reverts to the previous worker version, or redeploy the previous commit. Re-run `devops check` to confirm. The worker is stateless, so a rollback is safe and immediate.

## Gotchas

- Wrangler deploys to whatever Cloudflare account you are logged into. If `wrangler whoami` shows the wrong account, the deploy "succeeds" against a different worker and the version check (3) is what catches it.
- `wrangler.toml` and `wrangler.jsonc` both exist in this repo for historical reasons; `wrangler deploy` reads `wrangler.toml` (`name = "email-reader"`).
