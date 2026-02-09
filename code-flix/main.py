import argparse
import os
import shlex
import time
from pathlib import Path
from urllib.parse import urlsplit

import modal
from dotenv import load_dotenv

load_dotenv()


APP_NAME = os.getenv("MODAL_APP_NAME", "rlx-video-smoke")
BASE_IMAGE = os.getenv("MODAL_BASE_IMAGE", "node:22-slim")
RLX_REPO_URL = os.getenv("RLX_REPO_URL", "https://github.com/13point5/rlx.git")
RLX_REPO_DIR = "/workspace/rlx"
SANDBOX_ID_FILE = Path(__file__).resolve().parent / ".codeflix_sandbox_id"

CLONE_TIMEOUT_SECONDS = int(os.getenv("CODEFLIX_CLONE_TIMEOUT_SECONDS", "300"))
SETUP_TIMEOUT_SECONDS = int(os.getenv("CODEFLIX_SETUP_TIMEOUT_SECONDS", "1800"))
RUN_START_TIMEOUT_SECONDS = int(os.getenv("CODEFLIX_RUN_START_TIMEOUT_SECONDS", "120"))
TUNNEL_TIMEOUT_SECONDS = int(os.getenv("CODEFLIX_TUNNEL_TIMEOUT_SECONDS", "120"))

TUNNEL_PORTS = [
    int(p.strip())
    for p in os.getenv("CODEFLIX_TUNNEL_PORTS", "3000,8000").split(",")
    if p.strip()
]


def _quote(value: str) -> str:
    return shlex.quote(value)


def _origin(url: str) -> str:
    parsed = urlsplit(url)
    if not parsed.scheme or not parsed.netloc:
        return url.rstrip("/")
    return f"{parsed.scheme}://{parsed.netloc}"


def _upsert_env_value(env_text: str, key: str, value: str) -> str:
    lines = env_text.splitlines()
    updated = False
    prefix = f"{key}="
    for i, line in enumerate(lines):
        if line.startswith(prefix):
            lines[i] = f"{key}={value}"
            updated = True
            break

    if not updated:
        lines.append(f"{key}={value}")

    return "\n".join(lines).rstrip("\n") + "\n"


def run_shell(
    sandbox: modal.Sandbox,
    command: str,
    timeout_seconds: int,
    phase: str,
    stream_output: bool = False,
) -> None:
    process = sandbox.exec("bash", "-lc", command, timeout=timeout_seconds)

    if stream_output:
        for chunk in process.stdout:
            line = chunk.rstrip()
            if line:
                print(f"[{phase}] {line}")
        for chunk in process.stderr:
            line = chunk.rstrip()
            if line:
                print(f"[{phase}:err] {line}")
        exit_code = process.wait()
    else:
        stdout = process.stdout.read().strip()
        stderr = process.stderr.read().strip()
        exit_code = process.wait()

        if stdout:
            print(f"\n--- {phase} stdout ---")
            print(stdout)
        if stderr:
            print(f"\n--- {phase} stderr ---")
            print(stderr)

    if exit_code != 0:
        raise RuntimeError(f"{phase} failed with exit code {exit_code}")


def run_phase(
    sandbox: modal.Sandbox,
    name: str,
    command: str,
    timeout_seconds: int,
    stream_output: bool = False,
) -> None:
    started = time.monotonic()
    print(f"\n==> {name} (timeout {timeout_seconds}s)")
    run_shell(
        sandbox,
        command,
        timeout_seconds=timeout_seconds,
        phase=name,
        stream_output=stream_output,
    )
    print(f"<== {name} done in {time.monotonic() - started:.1f}s")


def write_remote_text(sandbox: modal.Sandbox, remote_path: str, content: str) -> None:
    parent = str(Path(remote_path).parent)
    run_shell(
        sandbox,
        f"mkdir -p {_quote(parent)}",
        timeout_seconds=60,
        phase="mkdir",
    )

    handle = sandbox.open(remote_path, "w")
    try:
        handle.write(content)
        handle.flush()
    finally:
        handle.close()


def print_tunnels(sandbox: modal.Sandbox) -> None:
    tunnels = sandbox.tunnels(timeout=TUNNEL_TIMEOUT_SECONDS)
    print("\nPreview URLs:")
    for port in sorted(tunnels.keys()):
        print(f"- {port}: {tunnels[port].url}")


def apply_preview_security_overrides(
    api_env_text: str,
    web_env_text: str,
    web_preview_url: str | None,
    api_preview_url: str | None,
) -> tuple[str, str]:
    if not web_preview_url or not api_preview_url:
        return api_env_text, web_env_text

    web_origin = _origin(web_preview_url)
    api_origin = _origin(api_preview_url)

    api_env_text = _upsert_env_value(api_env_text, "FRONTEND_URL", web_origin)
    api_env_text = _upsert_env_value(api_env_text, "BACKEND_URL", api_origin)
    api_env_text = _upsert_env_value(
        api_env_text,
        "CORS_ORIGINS",
        f"http://localhost:3000,{web_origin}",
    )

    web_env_text = _upsert_env_value(web_env_text, "API_BASE_URL", api_origin)

    return api_env_text, web_env_text


def stop_sandbox(sandbox_id: str) -> None:
    sandbox = modal.Sandbox.from_id(sandbox_id)
    sandbox.terminate()
    print(f"Terminated sandbox: {sandbox_id}")

    if (
        SANDBOX_ID_FILE.exists()
        and SANDBOX_ID_FILE.read_text(encoding="utf-8").strip() == sandbox_id
    ):
        SANDBOX_ID_FILE.unlink(missing_ok=True)


def resolve_env_paths() -> tuple[Path, Path]:
    project_root = Path(__file__).resolve().parent
    default_rlx_dir = (project_root / ".." / ".." / "rlx").resolve()

    api_env = Path(
        os.getenv(
            "RLX_API_ENV_PATH", str(default_rlx_dir / "apps" / "api" / ".env.sandbox")
        )
    )
    web_env = Path(
        os.getenv(
            "RLX_WEB_ENV_PATH", str(default_rlx_dir / "apps" / "web" / ".env.sandbox")
        )
    )
    return api_env, web_env


def wrap_with_env(command: str) -> str:
    return "\n".join(
        [
            "set -euo pipefail",
            "set -a",
            f"source {_quote(f'{RLX_REPO_DIR}/apps/api/.env.sandbox')}",
            f"source {_quote(f'{RLX_REPO_DIR}/apps/web/.env.sandbox')}",
            "set +a",
            f"cd {_quote(RLX_REPO_DIR)}",
            command,
        ]
    )


def create_and_start() -> None:
    api_env_path, web_env_path = resolve_env_paths()
    api_env_text = api_env_path.read_text(encoding="utf-8")
    web_env_text = web_env_path.read_text(encoding="utf-8")

    print(f"Using API sandbox env: {api_env_path}")
    print(f"Using web sandbox env: {web_env_path}")

    app = modal.App.lookup(APP_NAME, create_if_missing=True)

    image = (
        modal.Image.from_registry(BASE_IMAGE, add_python="3.13")
        .apt_install("git", "curl", "ca-certificates")
        .run_commands(
            "corepack enable",
            "corepack prepare pnpm@latest --activate",
            "python -m pip install --no-cache-dir uv",
        )
    )

    sandbox = modal.Sandbox.create(
        app=app,
        image=image,
        timeout=5400,
        idle_timeout=600,
        encrypted_ports=TUNNEL_PORTS,
    )
    print(f"Sandbox id: {sandbox.object_id}")

    tunnels = sandbox.tunnels(timeout=TUNNEL_TIMEOUT_SECONDS)
    web_preview_url = tunnels.get(3000).url if 3000 in tunnels else None
    api_preview_url = tunnels.get(8000).url if 8000 in tunnels else None

    if web_preview_url and api_preview_url:
        print(f"Derived web preview URL: {web_preview_url}")
        print(f"Derived api preview URL: {api_preview_url}")
        api_env_text, web_env_text = apply_preview_security_overrides(
            api_env_text,
            web_env_text,
            web_preview_url,
            api_preview_url,
        )
    else:
        print(
            "Warning: could not resolve both web/api preview URLs before startup; using env files as-is."
        )

    try:
        run_phase(
            sandbox,
            "clone",
            "\n".join(
                [
                    "set -euo pipefail",
                    f"rm -rf {_quote(RLX_REPO_DIR)}",
                    f"git clone --depth 1 --single-branch {_quote(RLX_REPO_URL)} {_quote(RLX_REPO_DIR)}",
                    "mkdir -p /tmp/codeflix-logs",
                ]
            ),
            timeout_seconds=CLONE_TIMEOUT_SECONDS,
            stream_output=True,
        )

        write_remote_text(
            sandbox, f"{RLX_REPO_DIR}/apps/api/.env.sandbox", api_env_text
        )
        write_remote_text(
            sandbox, f"{RLX_REPO_DIR}/apps/web/.env.sandbox", web_env_text
        )

        run_phase(
            sandbox,
            "setup",
            f"bash -lc {_quote(wrap_with_env('bash scripts/codeflix-setup.sh'))}",
            timeout_seconds=SETUP_TIMEOUT_SECONDS,
            stream_output=True,
        )

        run_phase(
            sandbox,
            "run",
            f"bash -lc {_quote(wrap_with_env('nohup bash scripts/codeflix-run.sh >/tmp/codeflix-logs/run.log 2>&1 & echo $! >/tmp/codeflix-logs/run.pid'))}",
            timeout_seconds=RUN_START_TIMEOUT_SECONDS,
        )

        print_tunnels(sandbox)

        SANDBOX_ID_FILE.write_text(f"{sandbox.object_id}\n", encoding="utf-8")
        print(f"\nSaved sandbox id to {SANDBOX_ID_FILE}")
        print("Sandbox left running. Stop it with: uv run python main.py --stop")
    except Exception:
        run_shell(
            sandbox,
            "tail -n 200 /tmp/codeflix-logs/run.log || true",
            timeout_seconds=60,
            phase="debug",
        )
        sandbox.terminate()
        print("Sandbox terminated due to failure.")
        raise


def main() -> None:
    parser = argparse.ArgumentParser(description="Run or stop a code-flix sandbox.")
    parser.add_argument(
        "--stop", action="store_true", help="Stop the last started sandbox."
    )
    parser.add_argument(
        "--sandbox-id",
        type=str,
        default="",
        help="Sandbox ID to stop (defaults to saved .codeflix_sandbox_id).",
    )
    args = parser.parse_args()

    if args.stop:
        sandbox_id = args.sandbox_id.strip()
        if not sandbox_id:
            if not SANDBOX_ID_FILE.exists():
                raise SystemExit(
                    f"No sandbox id provided and no saved id file at {SANDBOX_ID_FILE}."
                )
            sandbox_id = SANDBOX_ID_FILE.read_text(encoding="utf-8").strip()
        stop_sandbox(sandbox_id)
        return

    create_and_start()


if __name__ == "__main__":
    main()
