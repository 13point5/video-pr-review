# Modal CDP Smoke Test (Bun + TypeScript)

This project runs a Modal sandbox CDP smoke test that:

1. builds/reuses a cached image with Chromium + `agent-browser`,
2. launches Chromium with CDP inside a sandbox,
3. records a short `.webm` via `agent-browser`,
4. downloads the video artifact locally, and
5. terminates the sandbox.

## Run

```bash
cd modal-sandbox-smoke
bun install
bun run cdp-smoke
```

The script loads `.env` automatically via `dotenv`.

If successful, the video is written to `modal-sandbox-smoke/artifacts/`.
By default, this script builds (or reuses) a cached Modal image layer with `chromium`, `ffmpeg`, and `agent-browser` preinstalled so future runs start faster.

## RLX codeflix + CDP run

This run clones `13point5/rlx` inside the sandbox, writes API/web sandbox env files from your local RLX checkout, executes setup/run commands from `codeflix.json`, and records a short video via CDP.

```bash
cd modal-sandbox-smoke
bun run rlx-cdp
```

Defaults expect your local RLX checkout at `../rlx` (sibling to this repo) and load env files in this order:

1. `apps/api/.env.sandbox`
2. `apps/web/.env.sandbox`

In RLX, create sandbox env files once:

```bash
cp apps/api/.env apps/api/.env.sandbox
cp apps/web/.env.local apps/web/.env.sandbox
```

Create `codeflix.json` in the RLX repo root. Keep it simple: `setup` and `run` are strings.

```json
{
  "setup": "bash scripts/codeflix-setup.sh",
  "run": "bash scripts/codeflix-run.sh",
  "open_url": "http://127.0.0.1:3000/sign-in"
}
```

Override only if needed:

```bash
export RLX_LOCAL_DIR="/absolute/path/to/rlx"
export RLX_API_ENV_PATH="/absolute/path/to/rlx/apps/api/.env.sandbox"
export RLX_WEB_ENV_PATH="/absolute/path/to/rlx/apps/web/.env.sandbox"
export CODEFLIX_CONFIG_PATH="/absolute/path/to/rlx/codeflix.json"
export RLX_REPO_URL="https://github.com/13point5/rlx.git"
```

## RLX sign-in + home screenshot (in sandbox)

This run keeps everything inside the Modal sandbox, signs in with Clerk test email-code auth using `agent-browser`, opens `http://127.0.0.1:3000/home`, and captures a PNG screenshot.

```bash
cd modal-sandbox-smoke
export CLERK_TEST_EMAIL="your-test-user@example.com"
export CLERK_TEST_CODE="424242"
bun run rlx-home-screenshot
```

If successful, the screenshot is written to `modal-sandbox-smoke/artifacts/`.

## Required auth

Use one of:

- Modal CLI auth (`modal setup`), or
- env vars:

```bash
export MODAL_TOKEN_ID="ak-..."
export MODAL_TOKEN_SECRET="as-..."
```

Or put these in `modal-sandbox-smoke/.env`.
