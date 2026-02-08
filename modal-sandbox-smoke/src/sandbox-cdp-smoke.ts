import "dotenv/config";
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { App, Image } from "modal";

const APP_NAME = "rlx-video-smoke";
const IMAGE = "node:20-bookworm";
const CDP_PORT = "9222";
const TEST_URL = "https://example.com";
const SANDBOX_VIDEO_PATH = "/tmp/cdp-smoke.webm";
const SESSION = "modal-cdp-smoke";
const LOCAL_ARTIFACT_DIR = "artifacts";

const here = dirname(fileURLToPath(import.meta.url));
const projectRoot = join(here, "..");

function shQuote(value: string): string {
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}

async function main() {
  const app = await App.lookup(APP_NAME, { createIfMissing: true });
  let image = Image.fromRegistry(IMAGE).dockerfileCommands(
    [
      "RUN export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -yqq --no-install-recommends chromium ffmpeg curl ca-certificates && rm -rf /var/lib/apt/lists/*",
      "RUN npm install -g agent-browser && agent-browser install",
    ],
  );
  console.log("Building/reusing prebuilt image layer cache...");
  image = await image.build(app);

  console.log(`Creating sandbox in app '${APP_NAME}' with image '${IMAGE}'...`);
  const sb = await app.createSandbox(image, {
    timeout: 1800000,
    idleTimeout: 300000,
  });

  console.log(`Sandbox ready: ${sb.sandboxId}`);

  try {
    const cdpVersionUrl = `http://127.0.0.1:${CDP_PORT}/json/version`;

    const remoteScript = [
      "set -euo pipefail",
      "mkdir -p /tmp/chrome-cdp-profile",
      `chromium --headless=new --remote-debugging-address=127.0.0.1 --remote-debugging-port=${shQuote(
        CDP_PORT,
      )} --user-data-dir=/tmp/chrome-cdp-profile --no-sandbox --disable-dev-shm-usage about:blank >/tmp/chrome-cdp.log 2>&1 &`,
      `for i in $(seq 1 45); do if curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null 2>&1; then break; fi; sleep 1; done`,
      `curl -fsS ${shQuote(cdpVersionUrl)} >/dev/null`,
      "agent-browser --version",
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} open ${shQuote(TEST_URL)}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} wait 1200`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} record start ${shQuote(
        SANDBOX_VIDEO_PATH,
      )}`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} wait 1500`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} scroll down 600 || true`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} wait 800`,
      `agent-browser --session ${shQuote(SESSION)} --cdp ${shQuote(CDP_PORT)} record stop`,
      `test -s ${shQuote(SANDBOX_VIDEO_PATH)}`,
      `ls -lh ${shQuote(SANDBOX_VIDEO_PATH)}`,
    ].join("\n");

    const proc = await sb.exec(["bash", "-lc", remoteScript], {
      stdout: "pipe",
      stderr: "pipe",
      timeout: 1800000,
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
      throw new Error(`CDP smoke command failed with exit code ${code}`);
    }

    const remoteVideo = await sb.open(SANDBOX_VIDEO_PATH, "r");
    const bytes = await remoteVideo.read();
    await remoteVideo.close();

    const artifactDir = join(projectRoot, LOCAL_ARTIFACT_DIR);
    await mkdir(artifactDir, { recursive: true });

    const stamp = new Date().toISOString().replace(/[:.]/g, "-");
    const localVideoPath = join(artifactDir, `cdp-smoke-${stamp}.webm`);
    await Bun.write(localVideoPath, bytes);

    console.log(`\nSaved video artifact: ${localVideoPath}`);
    console.log(`Video bytes: ${bytes.byteLength}`);
  } finally {
    await sb.terminate();
    console.log("Sandbox terminated.");
  }
}

main().catch((err) => {
  console.error("CDP smoke test failed:", err);
  process.exit(1);
});
