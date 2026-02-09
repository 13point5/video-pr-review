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
const SESSION = "modal-rlx-cdp";
const SANDBOX_VIDEO_PATH = "/tmp/rlx-cdp.webm";
const LOCAL_ARTIFACT_DIR = "artifacts";

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
  openUrl: string;
  recordWaitMs: number;
  scrollPx: number;
};

function shQuote(value: string): string {
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
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

function toPositiveNumber(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return fallback;
}

function parseCodeflixConfig(rawText: string): CodeflixConfig {
  const parsed = JSON.parse(rawText) as Record<string, unknown>;

  if (typeof parsed.setup !== "string" || parsed.setup.trim().length === 0) {
    throw new Error("codeflix.json requires `setup` as a non-empty string.");
  }

  if (typeof parsed.run !== "string" || parsed.run.trim().length === 0) {
    throw new Error("codeflix.json requires `run` as a non-empty string.");
  }

  const openUrlRaw = parsed.openUrl ?? parsed.open_url;
  const openUrl =
    typeof openUrlRaw === "string" && openUrlRaw.trim().length > 0
      ? openUrlRaw
      : "http://127.0.0.1:3000/sign-in";

  const recordWaitMs = toPositiveNumber(parsed.recordWaitMs ?? parsed.record_wait_ms, 1200);
  const scrollPx = toPositiveNumber(parsed.scrollPx ?? parsed.scroll_px, 500);

  return {
    setup: parsed.setup,
    run: parsed.run,
    openUrl,
    recordWaitMs,
    scrollPx,
  };
}

function envWrappedCommand(command: string) {
  return [
    "set -euo pipefail",
    "set -a",
    `source ${shQuote(`${RLX_REPO_DIR}/apps/api/.env.sandbox`)}`,
    `source ${shQuote(`${RLX_REPO_DIR}/apps/web/.env.sandbox`)}`,
    "set +a",
    `cd ${shQuote(RLX_REPO_DIR)}`,
    command,
  ].join("\n");
}

async function main() {
  const [apiEnv, webEnv, codeflixRaw] = await Promise.all([
    readFile(API_ENV_LOCAL_PATH, "utf8"),
    readFile(WEB_ENV_LOCAL_PATH, "utf8"),
    readFile(CODEFLIX_CONFIG_LOCAL_PATH, "utf8"),
  ]);

  const codeflix = parseCodeflixConfig(codeflixRaw);

  console.log(`Using API sandbox env: ${API_ENV_LOCAL_PATH}`);
  console.log(`Using web sandbox env: ${WEB_ENV_LOCAL_PATH}`);
  console.log(`Using run config: ${CODEFLIX_CONFIG_LOCAL_PATH}`);

  const app = await App.lookup(APP_NAME, { createIfMissing: true });
  let image = Image.fromRegistry(IMAGE).dockerfileCommands([
    "RUN export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -yqq --no-install-recommends ca-certificates curl git python3 python3-pip chromium ffmpeg procps && rm -rf /var/lib/apt/lists/*",
    "RUN npm install -g agent-browser && agent-browser install",
  ]);

  console.log("Building/reusing image cache for RLX CDP run...");
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
      "for i in $(seq 1 240); do if curl -fsS http://127.0.0.1:3000/ >/dev/null 2>&1; then break; fi; sleep 2; done",
      "curl -fsS http://127.0.0.1:8000/ >/dev/null",
      "curl -fsS http://127.0.0.1:3000/ >/dev/null",
      "mkdir -p /tmp/chrome-cdp-profile",
      `chromium --headless=new --remote-debugging-address=127.0.0.1 --remote-debugging-port=${shQuote(
        CDP_PORT,
      )} --user-data-dir=/tmp/chrome-cdp-profile --no-sandbox --disable-dev-shm-usage about:blank >/tmp/chrome-cdp.log 2>&1 &`,
      `for i in $(seq 1 60); do if curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null 2>&1; then break; fi; sleep 1; done`,
      `curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} open ${shQuote(codeflix.openUrl)}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} record start ${shQuote(
        SANDBOX_VIDEO_PATH,
      )}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} wait ${shQuote(String(codeflix.recordWaitMs))}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} scroll down ${shQuote(String(codeflix.scrollPx))} || true`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} wait ${shQuote(String(
        Math.max(800, Math.floor(codeflix.recordWaitMs / 2)),
      ))}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} record stop`,
      `test -s ${shQuote(SANDBOX_VIDEO_PATH)}`,
      `ls -lh ${shQuote(SANDBOX_VIDEO_PATH)}`,
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

    const remoteVideo = await sb.open(SANDBOX_VIDEO_PATH, "r");
    const bytes = await remoteVideo.read();
    await remoteVideo.close();

    const artifactDir = join(projectRoot, LOCAL_ARTIFACT_DIR);
    await mkdir(artifactDir, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const localVideoPath = join(artifactDir, `rlx-cdp-${stamp}.webm`);
    await Bun.write(localVideoPath, bytes);

    console.log(`\nSaved video artifact: ${localVideoPath}`);
    console.log(`Video bytes: ${bytes.byteLength}`);
  } finally {
    await sb.terminate();
    console.log("Sandbox terminated.");
  }
}

main().catch((err) => {
  console.error("RLX sandbox CDP run failed:", err);
  process.exit(1);
});
