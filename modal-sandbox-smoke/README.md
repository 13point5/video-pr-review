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

## Required auth

Use one of:

- Modal CLI auth (`modal setup`), or
- env vars:

```bash
export MODAL_TOKEN_ID="ak-..."
export MODAL_TOKEN_SECRET="as-..."
```

Or put these in `modal-sandbox-smoke/.env`.
