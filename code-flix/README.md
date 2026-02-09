# code-flix

Python + uv runner for starting RLX in a Modal sandbox and printing preview URLs.

This project keeps the existing Bun/TS scripts intact and provides a Python implementation of the RLX `codeflix.json` workflow.

## Prereqs

- `uv`
- Modal auth (`modal setup`) or `MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET`
- Local RLX checkout with:
  - `apps/api/.env.sandbox`
  - `apps/web/.env.sandbox`
  - `codeflix.json`

## Install

```bash
cd code-flix
uv sync
```

## Run

```bash
cd code-flix
uv run python main.py
```

This does the following:

- clones the RLX repo in a sandbox,
- copies `apps/api/.env.sandbox` and `apps/web/.env.sandbox`,
- derives preview URLs early and injects strict auth/origin env overrides,
- runs `bash scripts/codeflix-setup.sh` then `bash scripts/codeflix-run.sh`,
- opens tunnel ports and prints preview URLs,
- leaves the sandbox running.

To stop the last started sandbox:

```bash
uv run python main.py --stop
```

To stop a specific sandbox id:

```bash
uv run python main.py --stop --sandbox-id sb-xxxxxxxxxxxxxxxxxxxxxx
```

Optional: copy `.env.example` to `.env` and customize values.

The script defaults to reading RLX from `../../rlx` relative to this project.

Optional overrides:

```bash
export RLX_REPO_URL="https://github.com/13point5/rlx.git"
export RLX_API_ENV_PATH="/absolute/path/to/rlx/apps/api/.env.sandbox"
export RLX_WEB_ENV_PATH="/absolute/path/to/rlx/apps/web/.env.sandbox"
export MODAL_APP_NAME="rlx-video-smoke"
export MODAL_BASE_IMAGE="node:22-slim"
export CODEFLIX_TUNNEL_PORTS="3000,8000"
```
