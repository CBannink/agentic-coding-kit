"""playwright-runner.py — capture stable screenshots from a YAML screen-flow.

Usage (typically invoked through playwright-runner.ps1):
    python playwright-runner.py \
        --config .agents/screen-flows.yaml \
        --base-url http://localhost:3000 \
        --out-dir .agents/session-state/<id>/screenshots/before

Config format (YAML):
    base_url: http://localhost:3000              # default base URL
    viewport: {width: 1920, height: 1080}        # default viewport
    device_scale: 2                              # 2x DPI = retina-quality PNGs
    auth:                                         # optional pre-flight login
        url: /signin
        email_selector: "input[type='email']"
        password_selector: "input[type='password']"
        submit_selector: "button[type='submit']"
        email_env: DEMO_EMAIL                    # env var holding email
        password_env: DEMO_PASSWORD
    screens:
      - name: dashboard
        path: /dashboard
        wait_for:                                # any-of selectors
          - "[data-testid='dashboard']"
          - "h1"
        actions:                                 # optional pre-shot interactions
          - {kind: dismiss_cookies}
          - {kind: scroll_top}
          - {kind: shot, label: hero}
          - {kind: scroll_by, pixels: 500}
          - {kind: shot, label: scrolled_1}

Patterns ported from `C:/demo-producer/take_screenshots.py`:
    - safe_goto with networkidle → domcontentloaded fallback
    - wait_for_any (selector polling, AI-rendered UIs)
    - multi-fallback selectors
    - dismiss_cookies before interactions
    - numbered + labeled output for diffability
    - 2x DPI for crisp diffs
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("Missing dependency: pyyaml. Install with `pip install pyyaml`.\n")
    sys.exit(1)

try:
    from playwright.async_api import async_playwright, Page
except ImportError:
    sys.stderr.write(
        "Missing dependency: playwright. Install with `pip install playwright` "
        "and `python -m playwright install chromium`.\n"
    )
    sys.exit(1)


SHOT_INDEX = 0


async def shot(page: Page, out_dir: Path, screen_name: str, label: str, full_page: bool = True):
    global SHOT_INDEX
    SHOT_INDEX += 1
    filename = f"{SHOT_INDEX:03d}_{screen_name}__{label}.png"
    path = out_dir / filename
    try:
        await page.screenshot(path=str(path), full_page=full_page)
        size_kb = path.stat().st_size // 1024
        print(f"  [{SHOT_INDEX:03d}] {filename} ({size_kb}KB)")
    except Exception as e:
        print(f"  [{SHOT_INDEX:03d}] FAIL {filename}: {e}", file=sys.stderr)


async def safe_goto(page: Page, url: str, settle: float = 1.5):
    try:
        await page.goto(url, wait_until="networkidle", timeout=30000)
    except Exception:
        try:
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)
        except Exception as e:
            print(f"  goto failed: {url} — {e}", file=sys.stderr)
            return False
    await asyncio.sleep(settle)
    return True


async def wait_for_any(page: Page, selectors: list[str], timeout_ms: int = 10000) -> bool:
    deadline = asyncio.get_event_loop().time() + (timeout_ms / 1000)
    while asyncio.get_event_loop().time() < deadline:
        for sel in selectors:
            try:
                el = await page.query_selector(sel)
                if el and await el.is_visible():
                    return True
            except Exception:
                continue
        await asyncio.sleep(0.3)
    return False


async def dismiss_cookies(page: Page):
    for text in ("Accept", "Accept all", "I agree", "Agree", "Got it"):
        try:
            btn = page.locator(f"button:has-text('{text}')")
            if await btn.count() > 0:
                await btn.first.click(timeout=2000)
                await asyncio.sleep(0.4)
                return
        except Exception:
            continue


async def scroll_top(page: Page):
    try:
        await page.evaluate("window.scrollTo({top: 0, behavior: 'instant'})")
        await asyncio.sleep(0.3)
    except Exception:
        pass


async def scroll_by(page: Page, pixels: int):
    try:
        await page.evaluate(f"window.scrollBy({{top: {pixels}, behavior: 'instant'}})")
        await asyncio.sleep(0.6)
    except Exception:
        pass


async def login_if_configured(page: Page, auth: dict, base_url: str):
    if not auth:
        return
    email = os.environ.get(auth.get("email_env", "DEMO_EMAIL"), "")
    password = os.environ.get(auth.get("password_env", "DEMO_PASSWORD"), "")
    if not email or not password:
        print("  auth: env vars not set — skipping login", file=sys.stderr)
        return
    url = base_url.rstrip("/") + auth["url"]
    if not await safe_goto(page, url):
        return
    try:
        await page.fill(auth["email_selector"], email)
        await page.fill(auth["password_selector"], password)
        await page.click(auth["submit_selector"])
        await asyncio.sleep(3.0)
        print(f"  auth: logged in — now at {page.url}")
    except Exception as e:
        print(f"  auth: login failed — {e}", file=sys.stderr)


async def run_screen(page: Page, screen: dict, base_url: str, out_dir: Path):
    name = screen["name"]
    path = screen.get("path", "/")
    url = base_url.rstrip("/") + path
    print(f"\n--- {name} ({path}) ---")
    if not await safe_goto(page, url):
        return

    if screen.get("wait_for"):
        ok = await wait_for_any(page, screen["wait_for"], timeout_ms=15000)
        if not ok:
            print(f"  wait_for: none matched — capturing anyway", file=sys.stderr)

    for action in screen.get("actions", []):
        kind = action.get("kind")
        if kind == "dismiss_cookies":
            await dismiss_cookies(page)
        elif kind == "scroll_top":
            await scroll_top(page)
        elif kind == "scroll_by":
            await scroll_by(page, action.get("pixels", 500))
        elif kind == "click":
            try:
                await page.click(action["selector"], timeout=action.get("timeout", 5000))
                await asyncio.sleep(action.get("settle", 1.0))
            except Exception as e:
                print(f"  click failed ({action['selector']}): {e}", file=sys.stderr)
        elif kind == "fill":
            try:
                await page.fill(action["selector"], action["value"])
                await asyncio.sleep(0.3)
            except Exception as e:
                print(f"  fill failed ({action['selector']}): {e}", file=sys.stderr)
        elif kind == "shot":
            await shot(page, out_dir, name, action.get("label", "default"),
                       full_page=action.get("full_page", True))
        elif kind == "wait":
            await asyncio.sleep(action.get("seconds", 1.0))
        else:
            print(f"  unknown action kind: {kind}", file=sys.stderr)

    # Default shot at end if no explicit shots taken for this screen
    if not any(a.get("kind") == "shot" for a in screen.get("actions", [])):
        await shot(page, out_dir, name, "default", full_page=True)


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--base-url", default=None)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--headless", default="true")
    args = parser.parse_args()

    cfg = yaml.safe_load(Path(args.config).read_text(encoding="utf-8"))
    base_url = args.base_url or cfg.get("base_url", "http://localhost:3000")
    viewport = cfg.get("viewport", {"width": 1920, "height": 1080})
    device_scale = cfg.get("device_scale", 2)

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"playwright-runner — base_url={base_url} out_dir={out_dir}")

    async with async_playwright() as p:
        browser = await p.chromium.launch(headless=(args.headless.lower() != "false"))
        context = await browser.new_context(
            viewport=viewport,
            device_scale_factor=device_scale,
        )
        page = await context.new_page()

        await login_if_configured(page, cfg.get("auth"), base_url)

        for screen in cfg.get("screens", []):
            await run_screen(page, screen, base_url, out_dir)

        await browser.close()

    print(f"\nDone — {SHOT_INDEX} screenshots written to {out_dir}")


if __name__ == "__main__":
    asyncio.run(main())
