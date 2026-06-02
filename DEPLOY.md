# Deploying email-summarizer

The deploy procedure lives in `scripts/deploy.sh` (executable runbook); this file is the narrative around it: prereqs, rollback, and *why* each post-deploy check exists. If the steps and this doc ever disagree, the script wins. It follows the `~/dev` deploy convention (`DEPLOY.md` + `scripts/deploy.sh` + `scripts/postdeploy-check.sh`); `sms-hero` is the reference implementation.

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

The script ends by running `scripts/postdeploy-check.sh`. The deploy is **not done** until that passes.

## Prereqs

- `npx wrangler` authenticated for the Cloudflare account (`50980fd4...`). The deploy is a no-op surprise if you are logged into the wrong account, so the post-deploy check re-confirms the live worker's identity.
- Worker secrets (the OpenAI key and the shared `AUTH_TOKEN`) are set with `wrangler secret put ...`, sourced from the 1Password `AI CLI` vault. They are NOT in this repo.

## Post-deploy checks (and why each exists)

`scripts/postdeploy-check.sh` runs three read-only assertions and exits non-zero if any fail. None of them spends an OpenAI call or needs a secret.

1. **`GET /` returns 200.** The worker is deployed and reachable at the edge. A dependency-free liveness check.
2. **`GET /` identifies as `email-reader`, and an unauthenticated `POST /` returns 401.** This is the "real worker, not a fallback" check. A blank route, a 404 placeholder, or a half-broken deploy would not both report `service:"email-reader"` on GET and enforce the auth boundary on POST. The 401 proves the request-handling logic actually shipped (the worker reached `authorize()` and rejected), without spending an OpenAI call or the shared token. A `200` or a `500` on the unauthenticated POST would mean the auth gate is gone or the worker is erroring before it.
3. **The deployed version equals the version in this repo (freshness invariant).** `GET /` reports a `version` string sourced from `src/worker.ts`. The check reads that same string from the working tree and asserts the live worker reports it. A mismatch means the worker serving this route is NOT the code you just built: a failed/no-op `wrangler deploy`, a stale worker on the route, or the wrong Cloudflare account. This is the email-summarizer analog of sms-hero's single-backend invariant: assert that the thing serving traffic is the thing you just shipped. (For the check to catch a regression, bump the `version` string in `src/worker.ts` when a deploy changes behavior.)

## Rollback

- `npx wrangler rollback` reverts to the previous worker version, or redeploy the previous commit. Re-run `scripts/postdeploy-check.sh` to confirm. The worker is stateless, so a rollback is safe and immediate.

## Gotchas

- Wrangler deploys to whatever Cloudflare account you are logged into. If `wrangler whoami` shows the wrong account, the deploy "succeeds" against a different worker and the version check (3) is what catches it.
- `wrangler.toml` and `wrangler.jsonc` both exist in this repo for historical reasons; `wrangler deploy` reads `wrangler.toml` (`name = "email-reader"`).
