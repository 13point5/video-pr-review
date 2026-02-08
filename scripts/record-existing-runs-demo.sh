#!/usr/bin/env bash

set -euo pipefail

CDP_PORT="${CDP_PORT:-9222}"
SESSION="${SESSION:-rlx-demo}"
APP_URL="${APP_URL:-http://localhost:3000/home}"
OUTPUT_VIDEO="${1:-tmp/rlx-runs-demo.webm}"
AUTO_LAUNCH_CHROME="${AUTO_LAUNCH_CHROME:-true}"
CHROME_PROFILE_DIR="${CHROME_PROFILE_DIR:-$HOME/Library/Application Support/Google/Chrome-RemoteDebug-RLX}"
USE_CONNECT_ONCE="${USE_CONNECT_ONCE:-true}"
HEADLESS="${HEADLESS:-true}"

if ! command -v agent-browser >/dev/null 2>&1; then
  echo "Error: agent-browser is not installed or not on PATH."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required."
  exit 1
fi

if ! curl -sS "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  if [[ "${AUTO_LAUNCH_CHROME}" == "true" && "$(uname -s)" == "Darwin" ]]; then
    echo "CDP endpoint not found. Launching Chrome with remote debugging..."
    mkdir -p "${CHROME_PROFILE_DIR}"
    CHROME_ARGS=("--remote-debugging-port=${CDP_PORT}" "--user-data-dir=${CHROME_PROFILE_DIR}")
    if [[ "${HEADLESS}" == "true" ]]; then
      CHROME_ARGS+=("--headless=new")
    fi
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "${CHROME_ARGS[@]}" >/tmp/rlx-chrome-cdp.log 2>&1 &
    sleep 3
  fi
fi

if ! curl -sS "http://localhost:${CDP_PORT}/json/version" >/dev/null 2>&1; then
  echo "Error: CDP endpoint is not available on port ${CDP_PORT}."
  echo "Start Chrome with remote debugging, for example:"
  echo "  google-chrome --remote-debugging-port=${CDP_PORT}"
  echo "or on macOS:"
  echo "  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --remote-debugging-port=${CDP_PORT}"
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_VIDEO}")"

if [[ "${USE_CONNECT_ONCE}" == "true" ]]; then
  echo "Connecting agent-browser session '${SESSION}' to CDP ${CDP_PORT}..."
  agent-browser --session "${SESSION}" connect "${CDP_PORT}" >/dev/null
fi

ab() {
  if [[ "${USE_CONNECT_ONCE}" == "true" ]]; then
    agent-browser --session "${SESSION}" "$@"
  else
    agent-browser --cdp "${CDP_PORT}" --session "${SESSION}" "$@"
  fi
}

echo "Opening app..."
ab open "${APP_URL}" >/dev/null

CURRENT_URL="$(ab get url | tr -d '\r')"
if [[ "${CURRENT_URL}" == *"/sign-in"* ]]; then
  echo "Error: current browser session is not authenticated in RLX."
  echo "Please sign in in that Chrome profile, then re-run this script."
  exit 1
fi

echo "Starting recording to ${OUTPUT_VIDEO}..."
ab record start "${OUTPUT_VIDEO}" >/dev/null

# Keep sequence explicit and human-like for the demo.
ab wait 1200 >/dev/null

echo "Opening first project..."
ab eval '(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const ensureDemo = () => {
    if (window.__rlxDemo) return window.__rlxDemo;
    const cursor = document.createElement("div");
    cursor.id = "rlx-demo-cursor";
    cursor.style.cssText = "position:fixed;left:0;top:0;width:16px;height:16px;border-radius:50%;background:#fff;border:2px solid #111;box-shadow:0 0 0 2px rgba(255,255,255,.35),0 2px 10px rgba(0,0,0,.35);transform:translate(24px,24px);z-index:2147483646;pointer-events:none;transition:transform .35s ease";
    const ring = document.createElement("div");
    ring.id = "rlx-demo-ring";
    ring.style.cssText = "position:fixed;left:0;top:0;width:18px;height:18px;border-radius:999px;border:2px solid #38bdf8;opacity:0;transform:translate(-9999px,-9999px) scale(.2);z-index:2147483647;pointer-events:none";
    document.body.appendChild(cursor);
    document.body.appendChild(ring);
    window.__rlxDemo = {
      async click(el) {
        el.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
        await sleep(350);
        const r = el.getBoundingClientRect();
        const x = Math.round(r.left + r.width / 2);
        const y = Math.round(r.top + r.height / 2);
        cursor.style.transform = `translate(${x}px, ${y}px)`;
        await sleep(320);
        ring.style.transform = `translate(${x - 9}px, ${y - 9}px) scale(.25)`;
        ring.style.opacity = "1";
        ring.animate([
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(.25)`, opacity: 1 },
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(2.1)`, opacity: 0 },
        ], { duration: 540, easing: "ease-out" });
        el.click();
        await sleep(560);
      },
    };
    return window.__rlxDemo;
  };
  const links = [...document.querySelectorAll("a[href]")];
  const target = links.find((a) => /^\/projects\/\d+$/.test(new URL(a.href, location.origin).pathname));
  if (!target) throw new Error("No project link found on this page.");
  await ensureDemo().click(target);
  return target.getAttribute("href");
})()' >/dev/null
ab wait 2000 >/dev/null

echo "Opening first existing run..."
ab eval '(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const ensureDemo = () => {
    if (window.__rlxDemo) return window.__rlxDemo;
    const cursor = document.createElement("div");
    cursor.id = "rlx-demo-cursor";
    cursor.style.cssText = "position:fixed;left:0;top:0;width:16px;height:16px;border-radius:50%;background:#fff;border:2px solid #111;box-shadow:0 0 0 2px rgba(255,255,255,.35),0 2px 10px rgba(0,0,0,.35);transform:translate(24px,24px);z-index:2147483646;pointer-events:none;transition:transform .35s ease";
    const ring = document.createElement("div");
    ring.id = "rlx-demo-ring";
    ring.style.cssText = "position:fixed;left:0;top:0;width:18px;height:18px;border-radius:999px;border:2px solid #38bdf8;opacity:0;transform:translate(-9999px,-9999px) scale(.2);z-index:2147483647;pointer-events:none";
    document.body.appendChild(cursor);
    document.body.appendChild(ring);
    window.__rlxDemo = {
      async click(el) {
        el.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
        await sleep(350);
        const r = el.getBoundingClientRect();
        const x = Math.round(r.left + r.width / 2);
        const y = Math.round(r.top + r.height / 2);
        cursor.style.transform = `translate(${x}px, ${y}px)`;
        await sleep(320);
        ring.style.transform = `translate(${x - 9}px, ${y - 9}px) scale(.25)`;
        ring.style.opacity = "1";
        ring.animate([
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(.25)`, opacity: 1 },
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(2.1)`, opacity: 0 },
        ], { duration: 540, easing: "ease-out" });
        el.click();
        await sleep(560);
      },
    };
    return window.__rlxDemo;
  };
  const links = [...document.querySelectorAll("a[href]")];
  const target = links.find((a) => /^\/projects\/\d+\/runs\/\d+$/.test(new URL(a.href, location.origin).pathname));
  if (!target) throw new Error("No existing run link found on this page.");
  await ensureDemo().click(target);
  return target.getAttribute("href");
})()' >/dev/null
ab wait 2500 >/dev/null

echo "Expanding job output/logs..."
ab eval '(async () => {
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const ensureDemo = () => {
    if (window.__rlxDemo) return window.__rlxDemo;
    const cursor = document.createElement("div");
    cursor.id = "rlx-demo-cursor";
    cursor.style.cssText = "position:fixed;left:0;top:0;width:16px;height:16px;border-radius:50%;background:#fff;border:2px solid #111;box-shadow:0 0 0 2px rgba(255,255,255,.35),0 2px 10px rgba(0,0,0,.35);transform:translate(24px,24px);z-index:2147483646;pointer-events:none;transition:transform .35s ease";
    const ring = document.createElement("div");
    ring.id = "rlx-demo-ring";
    ring.style.cssText = "position:fixed;left:0;top:0;width:18px;height:18px;border-radius:999px;border:2px solid #38bdf8;opacity:0;transform:translate(-9999px,-9999px) scale(.2);z-index:2147483647;pointer-events:none";
    document.body.appendChild(cursor);
    document.body.appendChild(ring);
    window.__rlxDemo = {
      async click(el) {
        el.scrollIntoView({ block: "center", inline: "center", behavior: "smooth" });
        await sleep(350);
        const r = el.getBoundingClientRect();
        const x = Math.round(r.left + r.width / 2);
        const y = Math.round(r.top + r.height / 2);
        cursor.style.transform = `translate(${x}px, ${y}px)`;
        await sleep(320);
        ring.style.transform = `translate(${x - 9}px, ${y - 9}px) scale(.25)`;
        ring.style.opacity = "1";
        ring.animate([
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(.25)`, opacity: 1 },
          { transform: `translate(${x - 9}px, ${y - 9}px) scale(2.1)`, opacity: 0 },
        ], { duration: 540, easing: "ease-out" });
        el.click();
        await sleep(560);
      },
    };
    return window.__rlxDemo;
  };
  const rows = [...document.querySelectorAll("[role=\"button\"][tabindex=\"0\"]")];
  if (rows.length === 0) return "No job rows found";
  await ensureDemo().click(rows[0]);
  return "expanded-first-job";
})()' >/dev/null
ab wait 1200 >/dev/null

ab scroll down 700 >/dev/null || true
ab wait 800 >/dev/null
ab scroll down 700 >/dev/null || true
ab wait 800 >/dev/null
ab scroll up 350 >/dev/null || true
ab wait 1200 >/dev/null

echo "Stopping recording..."
ab record stop >/dev/null

echo "Done: ${OUTPUT_VIDEO}"
echo "Optional MP4 conversion:"
echo "  ffmpeg -y -i \"${OUTPUT_VIDEO}\" -c:v libx264 -pix_fmt yuv420p \"${OUTPUT_VIDEO%.webm}.mp4\""
