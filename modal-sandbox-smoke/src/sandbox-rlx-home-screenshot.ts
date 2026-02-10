import "dotenv/config";
import { mkdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { App, Image } from "modal";

const APP_NAME = process.env.MODAL_APP_NAME ?? "rlx-video-smoke";
const IMAGE = process.env.MODAL_IMAGE ?? "node:20-bookworm";
const RLX_REPO_URL = process.env.RLX_REPO_URL ?? "https://github.com/13point5/rlx.git";
const RLX_REPO_DIR = "/workspace/rlx";

const CDP_PORT = "9222";
const SESSION = "modal-rlx-home-screenshot";
const SIGN_IN_URL = "http://localhost:3000/sign-in";
const HOME_URL = "http://localhost:3000/home";
const SANDBOX_SCREENSHOT_PATH = "/tmp/rlx-home.png";
const LOCAL_ARTIFACT_DIR = "artifacts";

const TEST_EMAIL = (process.env.CLERK_TEST_EMAIL ?? "").trim();
const TEST_CODE = (process.env.CLERK_TEST_CODE ?? "424242").trim();

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..");
const defaultRlxLocalDir = join(projectRoot, "..", "..", "rlx");
const RLX_LOCAL_DIR = process.env.RLX_LOCAL_DIR ?? defaultRlxLocalDir;

const API_ENV_LOCAL_PATH =
  process.env.RLX_API_ENV_PATH ?? join(RLX_LOCAL_DIR, "apps", "api", ".env.sandbox");
const WEB_ENV_LOCAL_PATH =
  process.env.RLX_WEB_ENV_PATH ?? join(RLX_LOCAL_DIR, "apps", "web", ".env.sandbox");
const CODEFLIX_CONFIG_LOCAL_PATH =
  process.env.CODEFLIX_CONFIG_PATH ?? join(RLX_LOCAL_DIR, "codeflix.json");

type CodeflixConfig = {
  setup: string;
  run: string;
};

function shQuote(value: string): string {
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function buildSignInEval(email: string, code: string): string {
  const credsJson = JSON.stringify({ email, code });

  return `
    (async () => {
      const creds = ${credsJson};

      const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

      const isVisible = (el) => {
        if (!(el instanceof Element)) return false;
        const style = window.getComputedStyle(el);
        if (!style) return false;
        if (style.display === "none" || style.visibility === "hidden") return false;
        return el.getClientRects().length > 0;
      };

      const waitFor = async (factory, timeoutMs = 20000) => {
        const started = Date.now();
        while (Date.now() - started < timeoutMs) {
          const result = factory();
          if (result) return result;
          await sleep(250);
        }
        throw new Error("Timed out waiting for sign-in step");
      };

      const setInputValue = (input, value) => {
        const descriptor = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value");
        if (descriptor?.set) {
          descriptor.set.call(input, value);
        } else {
          input.value = value;
        }
        input.dispatchEvent(new Event("input", { bubbles: true }));
        input.dispatchEvent(new Event("change", { bubbles: true }));
      };

      const firstVisibleInput = (selectors) => {
        for (const selector of selectors) {
          const nodes = Array.from(document.querySelectorAll(selector));
          const match = nodes.find((node) => node instanceof HTMLInputElement && isVisible(node));
          if (match) return match;
        }
        return null;
      };

      const clickByLabel = (labels) => {
        const wanted = labels.map((label) => label.trim().toLowerCase());
        const candidates = Array.from(document.querySelectorAll("button, [role='button'], input[type='submit']"));
        for (const node of candidates) {
          if (!isVisible(node)) continue;
          const text = ((node.textContent ?? "").trim() || node.getAttribute("value") || "").toLowerCase();
          if (wanted.some((label) => text.includes(label))) {
            node.click();
            return true;
          }
        }
        return false;
      };

      const emailInput = await waitFor(
        () =>
          firstVisibleInput([
            'input[type="email"]',
            'input[name="identifier"]',
            'input[name*="identifier"]',
            'input[autocomplete="email"]',
          ]),
        20000,
      );

      emailInput.focus();
      setInputValue(emailInput, creds.email);
      await sleep(200);

      if (!clickByLabel(["Continue", "Sign in", "Sign In", "Next"])) {
        emailInput.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
        emailInput.dispatchEvent(new KeyboardEvent("keyup", { key: "Enter", bubbles: true }));
      }

      const otpInputs = await waitFor(() => {
        const nodes = Array.from(
          document.querySelectorAll(
            'input[autocomplete="one-time-code"], input[inputmode="numeric"], input[name*="code"]',
          ),
        ).filter((node) => node instanceof HTMLInputElement && isVisible(node));

        return nodes.length > 0 ? nodes : null;
      }, 25000);

      if (otpInputs.length >= creds.code.length && otpInputs.length <= 8) {
        for (let i = 0; i < creds.code.length; i += 1) {
          const input = otpInputs[i];
          if (!(input instanceof HTMLInputElement)) break;
          input.focus();
          setInputValue(input, creds.code[i]);
          await sleep(60);
        }
      } else {
        const first = otpInputs[0];
        if (!(first instanceof HTMLInputElement)) {
          throw new Error("OTP input did not resolve to a usable input element");
        }
        first.focus();
        setInputValue(first, creds.code);
      }

      clickByLabel(["Continue", "Verify", "Sign in", "Sign In"]);

      await waitFor(() => !location.pathname.includes("/sign-in"), 30000);
      return { ok: true, url: location.href };
    })();
  `
    .trim()
    .replace(/\n\s*/g, " ");
}

async function buildImageWithRetry(image: Image, app: App) {
  const maxAttempts = 3;

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await image.build(app);
    } catch (err) {
      const text = String(err);
      const transient =
        text.includes("ImageJoinStreaming") ||
        text.includes("RST_STREAM") ||
        text.includes("INTERNAL");

      if (!transient || attempt === maxAttempts) {
        throw err;
      }

      const delayMs = attempt * 4000;
      console.warn(
        `Image build stream error (attempt ${attempt}/${maxAttempts}). Retrying in ${delayMs}ms...`,
      );
      await sleep(delayMs);
    }
  }

  throw new Error("Image build retries exhausted");
}

async function runShell(sb: any, command: string, timeout = 1800000) {
  const proc = await sb.exec(["bash", "-lc", command], {
    stdout: "pipe",
    stderr: "pipe",
    timeout,
  });

  const [stdout, stderr, code] = await Promise.all([
    proc.stdout.readText(),
    proc.stderr.readText(),
    proc.wait(),
  ]);

  if (stdout.trim()) {
    console.log("\n--- sandbox stdout ---");
    console.log(stdout.trim());
  }

  if (stderr.trim()) {
    console.log("\n--- sandbox stderr ---");
    console.log(stderr.trim());
  }

  if (code !== 0) {
    throw new Error(`Sandbox command failed with exit code ${code}`);
  }
}

async function writeRemoteText(sb: any, remotePath: string, content: string) {
  const remoteDir = dirname(remotePath);
  await runShell(sb, `mkdir -p ${shQuote(remoteDir)}`);
  const handle = await sb.open(remotePath, "w");
  await handle.write(new TextEncoder().encode(content));
  await handle.flush();
  await handle.close();
}

function parseCodeflixConfig(rawText: string): CodeflixConfig {
  const parsed = JSON.parse(rawText) as Record<string, unknown>;

  if (typeof parsed.setup !== "string" || parsed.setup.trim().length === 0) {
    throw new Error("codeflix.json requires `setup` as a non-empty string.");
  }

  if (typeof parsed.run !== "string" || parsed.run.trim().length === 0) {
    throw new Error("codeflix.json requires `run` as a non-empty string.");
  }

  return {
    setup: parsed.setup,
    run: parsed.run,
  };
}

function envWrappedCommand(command: string) {
  return [
    "set -euo pipefail",
    "set -a",
    `source ${shQuote(`${RLX_REPO_DIR}/apps/api/.env.sandbox`)}`,
    `source ${shQuote(`${RLX_REPO_DIR}/apps/web/.env.sandbox`)}`,
    "set +a",
    "export PIP_BREAK_SYSTEM_PACKAGES=1",
    `cd ${shQuote(RLX_REPO_DIR)}`,
    command,
  ].join("\n");
}

async function main() {
  if (!TEST_EMAIL) {
    throw new Error("Missing CLERK_TEST_EMAIL. Set it in env before running this script.");
  }

  const [apiEnv, webEnv, codeflixRaw] = await Promise.all([
    readFile(API_ENV_LOCAL_PATH, "utf8"),
    readFile(WEB_ENV_LOCAL_PATH, "utf8"),
    readFile(CODEFLIX_CONFIG_LOCAL_PATH, "utf8"),
  ]);

  const codeflix = parseCodeflixConfig(codeflixRaw);
  const signInEval = buildSignInEval(TEST_EMAIL, TEST_CODE);

  console.log(`Using API sandbox env: ${API_ENV_LOCAL_PATH}`);
  console.log(`Using web sandbox env: ${WEB_ENV_LOCAL_PATH}`);
  console.log(`Using run config: ${CODEFLIX_CONFIG_LOCAL_PATH}`);

  const app = await App.lookup(APP_NAME, { createIfMissing: true });
  let image = Image.fromRegistry(IMAGE).dockerfileCommands([
    "RUN export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -yqq --no-install-recommends ca-certificates curl git python3 python3-pip chromium ffmpeg procps && rm -rf /var/lib/apt/lists/*",
    "RUN npm install -g agent-browser && agent-browser install",
  ]);

  console.log("Building/reusing image cache for RLX screenshot run...");
  image = await buildImageWithRetry(image, app);

  console.log(`Creating sandbox in app '${APP_NAME}' with image '${IMAGE}'...`);
  const sb = await app.createSandbox(image, {
    timeout: 5400000,
    idleTimeout: 600000,
  });

  console.log(`Sandbox ready: ${sb.sandboxId}`);

  try {
    const bootstrap = [
      "set -euo pipefail",
      `rm -rf ${shQuote(RLX_REPO_DIR)}`,
      `git clone --depth 1 ${shQuote(RLX_REPO_URL)} ${shQuote(RLX_REPO_DIR)}`,
      "mkdir -p /tmp/codeflix-logs",
    ].join("\n");
    await runShell(sb, bootstrap);

    await writeRemoteText(sb, `${RLX_REPO_DIR}/apps/api/.env.sandbox`, apiEnv);
    await writeRemoteText(sb, `${RLX_REPO_DIR}/apps/web/.env.sandbox`, webEnv);
    await writeRemoteText(sb, `${RLX_REPO_DIR}/codeflix.json`, codeflixRaw);

    const cdpVersionUrl = `http://127.0.0.1:${CDP_PORT}/json/version`;
    const runScript = [
      "set -euo pipefail",
      `bash -lc ${shQuote(envWrappedCommand(codeflix.setup))}`,
      `bash -lc ${shQuote(envWrappedCommand(codeflix.run))} >/tmp/codeflix-logs/run.log 2>&1 & echo $! >/tmp/codeflix-logs/run.pid`,
      "for i in $(seq 1 240); do if curl -fsS http://127.0.0.1:8000/ >/dev/null 2>&1; then break; fi; sleep 2; done",
      "for i in $(seq 1 240); do if curl -fsS http://localhost:3000/ >/dev/null 2>&1; then break; fi; sleep 2; done",
      "curl -fsS http://127.0.0.1:8000/ >/dev/null",
      "curl -fsS http://localhost:3000/ >/dev/null",
      "mkdir -p /tmp/chrome-cdp-profile",
      `chromium --headless=new --remote-debugging-address=127.0.0.1 --remote-debugging-port=${shQuote(
        CDP_PORT,
      )} --user-data-dir=/tmp/chrome-cdp-profile --no-sandbox --disable-dev-shm-usage about:blank >/tmp/chrome-cdp.log 2>&1 &`,
      `for i in $(seq 1 60); do if curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null 2>&1; then break; fi; sleep 1; done`,
      `curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null`,
      `ab() { agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} "$@"; }`,
      `ab open ${shQuote(SIGN_IN_URL)}`,
      "ab wait 1000",
      `ab eval ${shQuote(signInEval)} || true`,
      "ab wait 800",
      `ab open ${shQuote(HOME_URL)}`,
      "ab wait 1200",
      "CURRENT_URL=$(ab get url | tr -d '\\r')",
      "if [[ \"$CURRENT_URL\" == *\"/sign-in\"* ]]; then echo \"Sign-in did not complete; still on sign-in page.\" >&2; exit 1; fi",
      `ab --full screenshot ${shQuote(SANDBOX_SCREENSHOT_PATH)}`,
      `test -s ${shQuote(SANDBOX_SCREENSHOT_PATH)}`,
      `ls -lh ${shQuote(SANDBOX_SCREENSHOT_PATH)}`,
    ].join("\n");

    try {
      await runShell(sb, runScript, 5400000);
    } catch (err) {
      const debug = [
        "set +e",
        "if [ -d /tmp/codeflix-logs ]; then",
        "  ls -lah /tmp/codeflix-logs || true",
        "  if [ -f /tmp/codeflix-logs/run.log ]; then echo '--- /tmp/codeflix-logs/run.log ---'; tail -n 300 /tmp/codeflix-logs/run.log; fi",
        "fi",
        "echo '--- chrome-cdp.log ---'",
        "tail -n 200 /tmp/chrome-cdp.log || true",
      ].join("\n");
      await runShell(sb, debug, 300000).catch(() => undefined);
      throw err;
    }

    const remoteScreenshot = await sb.open(SANDBOX_SCREENSHOT_PATH, "r");
    const bytes = await remoteScreenshot.read();
    await remoteScreenshot.close();

    const artifactDir = join(projectRoot, LOCAL_ARTIFACT_DIR);
    await mkdir(artifactDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const localScreenshotPath = join(artifactDir, `rlx-home-${stamp}.png`);
    await Bun.write(localScreenshotPath, bytes);

    console.log(`\nSaved screenshot artifact: ${localScreenshotPath}`);
    console.log(`Screenshot bytes: ${bytes.byteLength}`);
  } finally {
    await sb.terminate();
    console.log("Sandbox terminated.");
  }
}

main().catch((err) => {
  console.error("RLX sandbox screenshot run failed:", err);
  process.exit(1);
});
