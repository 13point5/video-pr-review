import argparse
import os
from datetime import datetime
from pathlib import Path
from urllib.parse import urlsplit

import modal
from browserbase import Browserbase
from dotenv import load_dotenv
from playwright.sync_api import (
    Page,
    TimeoutError as PlaywrightTimeoutError,
    sync_playwright,
)

load_dotenv()


SANDBOX_ID_FILE = Path(__file__).resolve().parent / ".codeflix_sandbox_id"


def _origin(url: str) -> str:
    parsed = urlsplit(url)
    if not parsed.scheme or not parsed.netloc:
        return url.rstrip("/")
    return f"{parsed.scheme}://{parsed.netloc}"


def resolve_web_preview_url(sandbox_id: str, timeout: int = 120) -> str:
    sandbox = modal.Sandbox.from_id(sandbox_id)
    tunnels = sandbox.tunnels(timeout=timeout)
    if 3000 not in tunnels:
        raise RuntimeError(f"Sandbox {sandbox_id} has no tunnel for port 3000")
    return tunnels[3000].url.rstrip("/")


def _first_visible(page: Page, selectors: list[str], timeout_ms: int = 1500):
    for selector in selectors:
        locator = page.locator(selector)
        try:
            if locator.count() > 0 and locator.first.is_visible(timeout=timeout_ms):
                return locator.first
        except Exception:  # noqa: BLE001
            continue
    return None


def _click_first_button(page: Page, labels: list[str]) -> bool:
    for label in labels:
        button = page.get_by_role("button", name=label)
        try:
            if button.count() > 0 and button.first.is_visible(timeout=1200):
                button.first.click()
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def sign_in_with_test_email_code(
    page: Page, web_url: str, email: str, code: str
) -> None:
    page.goto(f"{web_url}/sign-in", wait_until="domcontentloaded")

    email_input = _first_visible(
        page,
        [
            'input[type="email"]',
            'input[name="identifier"]',
            'input[name*="identifier"]',
            'input[autocomplete="email"]',
        ],
        timeout_ms=4000,
    )
    if email_input is None:
        raise RuntimeError(
            "Could not find Clerk email/identifier input on sign-in page"
        )

    email_input.fill(email)

    if not _click_first_button(page, ["Continue", "Sign in", "Next"]):
        email_input.press("Enter")

    page.wait_for_timeout(1000)

    otp_fields = page.locator(
        'input[autocomplete="one-time-code"], input[inputmode="numeric"], input[name*="code"]'
    )

    try:
        otp_fields.first.wait_for(state="visible", timeout=15000)
    except PlaywrightTimeoutError as exc:
        raise RuntimeError(
            "OTP input fields did not appear after entering email"
        ) from exc

    count = otp_fields.count()
    if count >= len(code):
        for i, digit in enumerate(code):
            otp_fields.nth(i).fill(digit)
    else:
        otp_fields.first.fill(code)

    _click_first_button(page, ["Continue", "Verify", "Sign in"])

    page.wait_for_url("**/home", timeout=30000)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sign in to RLX via Browserbase and capture settings screenshot."
    )
    parser.add_argument(
        "--sandbox-id",
        type=str,
        default="",
        help="Modal sandbox id (defaults to .codeflix_sandbox_id)",
    )
    parser.add_argument(
        "--web-url",
        type=str,
        default="",
        help="Override preview web URL directly (skips sandbox tunnel lookup)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="",
        help="Output screenshot path (default: artifacts/settings-<timestamp>.png)",
    )
    args = parser.parse_args()

    api_key = os.getenv("BROWSERBASE_API_KEY", "").strip()
    project_id = os.getenv("BROWSERBASE_PROJECT_ID", "").strip()
    test_email = os.getenv("CLERK_TEST_EMAIL", "").strip()
    test_code = os.getenv("CLERK_TEST_CODE", "424242").strip()
    context_id = os.getenv("BROWSERBASE_CONTEXT_ID", "").strip()

    if not api_key or not project_id:
        raise SystemExit(
            "Missing Browserbase credentials. Set BROWSERBASE_API_KEY and BROWSERBASE_PROJECT_ID."
        )
    if not test_email:
        raise SystemExit("Missing CLERK_TEST_EMAIL in env.")

    sandbox_id = args.sandbox_id.strip()
    if not sandbox_id and not args.web_url.strip():
        if not SANDBOX_ID_FILE.exists():
            raise SystemExit(
                f"No --sandbox-id or --web-url provided and id file missing: {SANDBOX_ID_FILE}"
            )
        sandbox_id = SANDBOX_ID_FILE.read_text(encoding="utf-8").strip()

    web_url = args.web_url.strip().rstrip("/")
    if not web_url:
        web_url = resolve_web_preview_url(sandbox_id)
    web_origin = _origin(web_url)

    print(f"Using web origin: {web_origin}")

    bb = Browserbase(api_key=api_key)

    session_kwargs = {"project_id": project_id}
    if context_id:
        session_kwargs["browser_settings"] = {
            "context": {"id": context_id, "persist": True}
        }

    session = bb.sessions.create(**session_kwargs)
    print(f"Browserbase session: {session.id}")
    print(f"Replay URL: https://www.browserbase.com/sessions/{session.id}")

    try:
        debug = bb.sessions.debug(session.id)
        live = getattr(debug, "debugger_fullscreen_url", None)
        if live:
            print(f"Live view URL: {live}")
    except Exception:  # noqa: BLE001
        pass

    with sync_playwright() as playwright:
        browser = playwright.chromium.connect_over_cdp(session.connect_url)
        context = browser.contexts[0]
        page = context.pages[0] if context.pages else context.new_page()

        sign_in_with_test_email_code(page, web_origin, test_email, test_code)

        page.goto(f"{web_origin}/settings", wait_until="domcontentloaded")
        page.get_by_role("heading", name="Settings").wait_for(timeout=20000)

        output_path = args.output.strip()
        if not output_path:
            artifacts_dir = Path(__file__).resolve().parent / "artifacts"
            artifacts_dir.mkdir(parents=True, exist_ok=True)
            stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            output_path = str(artifacts_dir / f"settings-{stamp}.png")

        page.screenshot(path=output_path, full_page=True)
        print(f"Saved screenshot: {output_path}")

        browser.close()


if __name__ == "__main__":
    main()
