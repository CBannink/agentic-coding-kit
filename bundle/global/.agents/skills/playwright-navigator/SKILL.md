---
name: playwright-navigator
description: Figures out HOW Playwright should reach a target screen — auth steps, route, navigation actions, wait conditions — and emits a screen-flows.yaml block. Used by playwright-explorer when a route isn't already mapped. Prevents brittle "click around until found" automation.
---

# Playwright Navigator Skill

The agent that **discovers the navigation path** to a target screen and writes
the YAML block that drives `playwright-runner.ps1`. Keeps the screenshot
pipeline robust by separating "how do I get there" reasoning from "capture
the shot" mechanics.

## When this fires

- A new screen is added to `.wiki/features.md` and needs to be in `screen-flows.yaml`.
- `playwright-explorer` is asked to capture a screen the YAML doesn't cover.
- A redesign expands scope to screens not previously screenshotted.
- A screen's route or auth requirements changed (existing flow is broken).

## Inputs

- target screen description (e.g., "the proxy management page after selecting a profile")
- base URL (default `http://localhost:3000`)
- routing source files (router config, app dir for Next.js, route file for Vue/Svelte)
- auth state requirements (logged-in user, specific role, seeded data)
- `.wiki/features.md` (to confirm the screen is actually a documented surface)

## What this agent does

1. **Find the route**:
   - Read the framework's routing config:
     - Next.js: `app/**/page.tsx`, `pages/**/*.tsx`
     - React Router: search for `<Route path=` definitions
     - Vue Router: `routes` array in router file
     - SvelteKit: `src/routes/**/+page.svelte`
   - Match the screen description to the actual path.

2. **Determine auth state**:
   - Is the route public, authenticated, or role-gated? Check route guards / middleware.
   - If auth is required: identify the test user credentials (env, fixture, or `.env.test`).
   - If a seeded fixture is required: identify the seeding command.

3. **Map navigation actions**:
   - From the base URL, what's the click sequence to reach the target?
   - Prefer direct route navigation (`page.goto(url)`) over click-through when the
     URL is stable. Only use click sequences when the screen is reached through
     in-app state (e.g., a modal that requires opening a parent first).

4. **Identify stable wait selectors**:
   - Inspect the target screen's component file.
   - Pick selectors in this order:
     1. `data-testid` if the component has one
     2. semantic HTML (`main h1`, `[role='main']`)
     3. stable class fragment (`[class*='ProxyList']`)
     4. text content (last resort, brittle to copy changes)
   - Always provide ≥3 fallback selectors.

5. **Detect dynamic content delays**:
   - Does the screen fetch async data? Note expected load duration.
   - Does it use Suspense / React.lazy / streaming SSR? Add `waitForLoadState('networkidle')`.
   - Are there entrance animations? Add a small `waitForTimeout` after navigation
     to let them complete.

6. **Cookie banners and interstitials**:
   - Identify any modal / banner that appears on first load (cookies, onboarding tooltip).
   - Add to the `dismiss_first` list with selectors.

## Output contract

Emit a YAML block ready to paste into `.agents/screen-flows.yaml`:

```yaml
- id: <screen_slug>
  description: <one sentence>
  auth: <none|logged-in:<user-fixture>|role:<role>>
  prep:
    - <command to seed fixtures, if needed>
  navigation:
    - kind: goto
      url: <base>/<path>
    # OR for click sequences:
    - kind: goto
      url: <base>/<entry-path>
    - kind: click
      selectors:
        - "[data-testid='open-detail']"
        - "button:has-text('View')"
        - ".profile-card a"
  wait_for:
    - "[data-testid='proxy-list-loaded']"
    - "main [class*='ProxyList']"
    - "main h1"
  dismiss_first:
    - selector: "[data-testid='cookie-accept']"
    - selector: "button:has-text('Accept')"
  shots:
    - {kind: shot, label: <screen_slug>_initial}
    - {kind: scroll_top}
    - {kind: shot, label: <screen_slug>_top}
```

Plus a confidence note:

```
NAV-CONFIDENCE: <high|medium|low>
RATIONALE: <one sentence — why this confidence>
NEXT: <ready-to-screenshot | needs-auth-fixture | needs-route-clarification>
```

## How to verify the YAML works

After emitting, the orchestrator should:

1. Run `playwright-runner.ps1` with the new YAML against the running dev server.
2. Confirm the screenshot is non-empty AND shows the expected screen
   (a wait-selector matched the right element).
3. If the run fails: capture the failure (which selector didn't match, what
   was on screen instead) and re-spawn the navigator with that feedback.

## Anti-patterns

- **Inventing a route** — never guess. If the routing config doesn't reveal it,
  ask the user or stop. A wrong route screenshots the 404 page.
- **Single-selector waits** — always provide ≥3 fallbacks. The first selector
  is the goal; the rest are insurance.
- **Skipping auth** — if the screen requires login, the YAML must include the
  auth step. Captured login pages are useless.
- **Hardcoding test data** — reference fixtures by name (`auth: logged-in:test-user`),
  not by hardcoded credentials. The runner resolves fixtures from `.env.test`.
- **Click-through when goto would work** — if the route URL is stable, navigate
  directly. Click sequences are brittle.

## Integration

| Caller | When |
|---|---|
| `playwright-explorer` | Asked to capture a screen not in YAML — spawns navigator first |
| `redesign` | Step 1 (capture current state) — navigator runs for any uncovered screen before runner fires |
| `/build` (frontend gate) | New page added in the diff — navigator generates YAML, runner captures, ux-driver and ui-driver review |
