# Agent Video Automation Flow (How OpenCode Did It)

This document describes the exact flow used to generate deterministic app walkthrough videos in this repo, including intermediate exploration, command discovery, and script assembly.

It is written as an implementation reference you can later generalize for a cloud workflow (Browserbase + Playwright + agent orchestration).

## Goal

Create a repeatable video that shows:

- existing projects
- existing runs
- run job logs
- no new run creation

Then make it deterministic enough to run from one command.

## 1) Load Browser Skill + Discover Tooling

The first step was to load the browser automation skill docs and inspect local tool capabilities.

What was checked:

- `agent-browser --help`
- `agent-browser record --help`
- availability of `ffmpeg`
- whether app was up on `http://localhost:3000`

Why:

- confirm there is native recording support (`record start/stop`)
- confirm CDP attach support (`connect` and `--cdp`)
- confirm video conversion path exists (`ffmpeg`)

## 2) Codebase Recon to Find a Safe Navigation Path

Before touching automation, the app structure was explored to identify routes/components involved in runs and logs.

Files reviewed included:

- `apps/web/proxy.ts` (auth and route protection)
- `apps/web/app/(auth)/home/page.tsx`
- `apps/web/app/(auth)/projects/[id]/page.tsx`
- `apps/web/app/(auth)/projects/[id]/runs/[runId]/page.tsx`
- `apps/web/app/(auth)/projects/[id]/runs/[runId]/jobs-panel.tsx`
- `apps/web/app/(auth)/projects/[id]/runs-table.tsx`

What this gave us:

- exact URL patterns we can safely target:
  - project page: `/projects/{id}`
  - run page: `/projects/{id}/runs/{runId}`
- confirmation where logs are shown (jobs panel, expandable rows)
- confidence we can avoid clicking `New Run`

## 3) Validate Runtime Preconditions

Runtime checks were done before final scripting:

- app health (`curl` to port 3000)
- auth behavior (`/home` redirect to sign-in if unauthenticated)
- CDP availability (`http://localhost:9222/json/version`)

This identified a key requirement:

- CDP-driven automation only works if Chrome is launched with remote debugging.

## 4) Session Persistence Strategy

To avoid repeated Clerk/Google logins, persistence was set up at two levels:

1. **Chrome profile persistence**
   - launch with a dedicated user data dir
   - example: `--user-data-dir="$HOME/Library/Application Support/Google/Chrome-RemoteDebug-RLX"`

2. **Agent-browser session persistence**
   - use a fixed session name (`--session rlx-demo`)
   - connect once via `agent-browser connect 9222`
   - then run commands without `--cdp` each time (session context reused)

Result:

- cookies/localStorage persist in that profile
- repeated runs do not require logging in again unless tokens expire

## 5) Build Intermediate Helpers First

Two helper scripts were created before final tuning:

- `scripts/relaunch-chrome-cdp.sh`
  - closes existing Chrome
  - relaunches with CDP + persistent profile
  - waits until CDP endpoint is live

- `scripts/record-existing-runs-demo.sh`
  - validates dependencies and CDP reachability
  - connects session
  - runs deterministic action sequence
  - starts/stops recording

Why this split matters:

- relaunch concerns are isolated from recording logic
- easier to reuse and debug in CI/cloud later

## 6) Move from Ad-hoc Commands to Deterministic Script

Early checks were ad-hoc CLI commands to validate behavior. After that, commands were assembled into one deterministic flow.

Core deterministic sequence:

1. open `/home`
2. verify we are not on `/sign-in`
3. start recording
4. open first project link matching `/projects/{id}`
5. open first run link matching `/projects/{id}/runs/{runId}`
6. expand first job row in logs panel
7. scroll for context
8. stop recording

A practical detail:

- instead of brittle CSS text selectors, URL-pattern matching was used inside `eval` to find safe anchors.

## 7) Make Clicks Visible in Video

To make the demo easier to watch, visual overlays were injected during click actions:

- synthetic cursor element
- click ripple ring animation

This created a visible "agent pointer + click indicator" without changing app source code.

## 8) Headless Mode Support

The script was updated to support headless launch while retaining CDP and profile persistence:

- `HEADLESS=true` default
- when auto-launching Chrome, pass `--headless=new`

This allows unattended recording jobs.

## 9) Video Outputs and Post-processing

`agent-browser` recording emits WebM. A conversion step to MP4 was added with ffmpeg:

- input: `tmp/*.webm`
- output: `tmp/*.mp4`

This made outputs easier to preview/share.

## 10) Important Constraint Found

In this version of `agent-browser`, recording resolution is hardcoded to 1280x720 in its recording context implementation.

Implication:

- setting viewport externally does not change recording size for `record start`.
- high-quality outputs can be re-encoded/upscaled, but source capture remains 720p unless tool internals are changed.

## 11) Why This Flow Worked Reliably

- code-aware route discovery first
- explicit precondition checks (app up, CDP up, auth present)
- deterministic sequence with waits
- non-destructive target path (existing runs/logs only)
- persistent browser/session model

## 12) How to Generalize for Browserbase + Playwright Cloud

Use the same architecture, just swap local browser control for remote browser sessions.

Recommended cloud pipeline:

1. **Discover phase**
   - repo scan (routes/components/actions)
   - generate candidate safe navigation graph

2. **Probe phase**
   - run tiny Playwright checks in Browserbase sessions
   - verify selectors/navigation without recording

3. **Plan phase**
   - produce deterministic action timeline with guardrails

4. **Record phase**
   - run one clean execution with tracing + screenshots on failure
   - save video artifact

5. **Post phase**
   - transcode
   - subtitles from event timeline (then optional multimodal enrichment)

Design principles to keep:

- persistent auth/session per workspace
- strict safe-mode policy for destructive UI actions
- action/event logs as first-class artifacts
- replayability from a stored plan

## 13) Minimal Event Schema (for subtitles and replay)

Even before multimodal captioning, generate subtitles from structured events:

- `t_start_ms`
- `t_end_ms`
- `action` (open/click/expand/scroll)
- `target` (url pattern, selector, ref)
- `url_before`
- `url_after`
- `caption_text`

This gives immediate subtitle support and strong replay/debug value.

## 14) Final Notes

This was intentionally built as:

- agent-assisted exploration
- followed by deterministic automation

That split is the core pattern to keep when productizing: use the agent to discover and validate, then execute a stable generated script for production runs.
