#!/usr/bin/env bash

set -euo pipefail

SESSION="${SESSION:-rlx-demo}"
PROFILE_DIR="${PROFILE_DIR:-$HOME/.rlx-profile}"
APP_URL="${APP_URL:-http://localhost:3000/home}"
OUTPUT_VIDEO="${1:-tmp/rlx-runs-demo-profile.webm}"
HEADED="${HEADED:-true}"
CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

if ! command -v agent-browser >/dev/null 2>&1; then
  echo "Error: agent-browser is not installed or not on PATH."
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required."
  exit 1
fi

if ! curl -sS "http://localhost:3000" >/dev/null 2>&1; then
  echo "Error: app does not appear to be running on localhost:3000."
  exit 1
fi

mkdir -p "${PROFILE_DIR}"
mkdir -p "$(dirname "${OUTPUT_VIDEO}")"

# Prevent stale daemon/session state from ignoring new profile options.
agent-browser close --session "${SESSION}" >/dev/null 2>&1 || true
agent-browser close >/dev/null 2>&1 || true

ab() {
  local args=(--session "${SESSION}" --profile "${PROFILE_DIR}")
  if [[ "${HEADED}" == "true" ]]; then
    args+=(--headed)
  fi
  agent-browser "${args[@]}" "$@"
}

echo "Opening app with profile: ${PROFILE_DIR}"
ab open "${APP_URL}" >/dev/null

CURRENT_URL="$(ab get url | tr -d '\r')"
if [[ "${CURRENT_URL}" == *"/sign-in"* ]]; then
  echo "Warning: this profile is not authenticated yet."
  echo "Google can block automated logins with 'This browser may not be secure'."
  echo "Opening regular Chrome with the same profile for manual Clerk + Google login..."
  if [[ "$(uname -s)" == "Darwin" && -x "${CHROME_BIN}" ]]; then
    open -na "Google Chrome" --args --user-data-dir="${PROFILE_DIR}" --new-window "${APP_URL}" >/dev/null 2>&1 || true
  else
    echo "Could not auto-open Chrome on this OS."
  fi
  echo ""
  echo "WARNING: Finish authentication in that Chrome window, then rerun this script."
  echo "If needed, manual command:"
  echo "  open -na \"Google Chrome\" --args --user-data-dir=\"${PROFILE_DIR}\" --new-window \"${APP_URL}\""
  exit 1
fi

echo "Starting recording to ${OUTPUT_VIDEO}..."
ab record start "${OUTPUT_VIDEO}" >/dev/null

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
