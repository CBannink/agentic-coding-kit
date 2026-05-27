---
name: playwright-explorer
description: Captures stable annotated screenshots of local app flows for redesign, UX/UI review, and visual verification loops.
---

# Playwright Explorer Skill

Spawned to **navigate a running app and capture screenshots** that other agents
(usually `design-driver`) judge. The explorer never edits code — its only job
is to produce reliable visual ground truth.

## Inputs

- a config at `.agents/screen-flows.yaml` (or path passed in)
- a base URL (default `http://localhost:3000`)
- session output directory under `${AGENTS_SESSION_ROOT}/{id}/screenshots/`

If `.agents/screen-flows.yaml` doesn't exist, generate one:
1. read `.wiki/features.md` to learn the user-visible flows
2. visit the base URL, list links and primary actions
3. write a draft `screen-flows.yaml` covering the must-have flows
4. ask the user to confirm before running

## Selector resilience (the hard part)

Web UIs change. Brittle selectors are why most screenshot suites die.
**Always provide multiple fallback selectors** for any wait or click:

```yaml
wait_for:
  - "[data-testid='dashboard-hero']"
  - "[class*='Dashboard'][class*='Hero']"
  - "main h1"
  - "main"
```

Wait order: prefer `data-testid` → semantic class → tag/role.

For clicks, use the same multi-selector pattern (the runner accepts arrays
in actions if needed; otherwise probe before clicking).

## Patterns ported from production

The runner was built from the homescout demo-producer screenshot pipeline.
Battle-tested patterns it ships with:

- **`safe_goto`** — tries `networkidle` first, falls back to `domcontentloaded`
- **`wait_for_any`** — polls multiple selectors until one is visible (essential
  for AI-rendered UIs that take 5-25s to populate)
- **`dismiss_cookies`** — clicks "Accept" / "I agree" / "Got it" before
  interactions to avoid an interstitial covering the next shot
- **`scroll_top`** — repeatable framing reset between shots
- **2x device scale factor** — retina-quality 3840×2160 PNGs for crisp diffs
- **Numbered + labeled output** — `001_dashboard__hero.png`, sortable, diffable

## Authoring `screen-flows.yaml`

Minimal example:

```yaml
base_url: http://localhost:3000
viewport: {width: 1920, height: 1080}
device_scale: 2

screens:
  - name: dashboard
    path: /dashboard
    wait_for:
      - "[data-testid='dashboard']"
      - "main h1"
    actions:
      - {kind: dismiss_cookies}
      - {kind: scroll_top}
      - {kind: shot, label: hero}
      - {kind: scroll_by, pixels: 600}
      - {kind: shot, label: middle}

  - name: settings
    path: /settings
    wait_for: ["form"]
    actions:
      - {kind: shot, label: form}
      - {kind: fill, selector: "input[name='display_name']", value: "Test User"}
      - {kind: shot, label: form_filled}
```

Auth (optional):

```yaml
auth:
  url: /signin
  email_selector: "input[type='email']"
  password_selector: "input[type='password']"
  submit_selector: "button[type='submit']"
  email_env: APP_TEST_EMAIL          # the script reads $env:APP_TEST_EMAIL
  password_env: APP_TEST_PASSWORD
```

Never hardcode credentials in the YAML. Always env-var them.

## Running

```powershell
pwsh ~/.agents/tools/playwright-runner.ps1 \
    -ConfigPath .agents/screen-flows.yaml \
    -OutDir ${AGENTS_SESSION_ROOT}/$SessionId/screenshots/before
```

For after-state capture, repeat with `/screenshots/after`.

## Output contract

The runner writes:
- `NNN_{screen}__{label}.png` for each shot
- nothing else

Downstream agents (`design-driver`, `visual-diff`) read this directory.

## Failure modes

- **Local dev server not running** — runner times out on `safe_goto`. Either
  start the server or pass a deployed URL.
- **Selectors don't match** — `wait_for_any` returns False, runner shoots
  anyway. Update selectors and re-run.
- **Auth env vars not set** — login is skipped silently with a warning. The
  authenticated flows then 404 / redirect — symptom: lots of "sign in" pages
  in the screenshots.
- **Cookie banner blocks shot** — add `{kind: dismiss_cookies}` action before
  the first shot of each screen.

## When to use this skill standalone

- Capturing baseline screenshots before any UI change
- Producing marketing/blog assets (full-page, 2x DPI)
- Visual regression checks in CI
- Generating ground truth for the `design-driver` skill
