"""mini-coding-eval.py -- 10-task coding benchmark for the kit harness.

Runs 10 small coding problems via OpenCode three ways:
  1. with-kit       -- kit's lifecycle plugin active (default OpenCode behavior with kit installed)
  2. without-kit    -- opencode --pure (kit plugin disabled)
  3. raw-baseline   -- direct API call, no harness at all (only if you have a raw API key)

For each task: prompts the model to implement a small function, extracts the
function code from the response, runs the task's hand-written test cases,
and counts pass/fail.

Comparable to HumanEval-style published numbers (Kimi K2.6 published 80.2 SWE-bench
Verified and ~85% on HumanEval-class tasks). 10 tasks won't give statistical
significance, but it's enough to see a directional difference.

Usage:
    python benchmarks/mini-coding-eval.py --model github-copilot/claude-haiku-4.5
    python benchmarks/mini-coding-eval.py --model openrouter/moonshotai/kimi-k2.6 --modes with-kit,without-kit
    python benchmarks/mini-coding-eval.py --model deepseek/deepseek-v4-pro --tasks 0,1,2

Output:
    benchmarks/results-<timestamp>.json  -- raw per-task results
    Summary table to stdout

Requires: opencode on PATH, configured for the chosen model.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

# --- Tasks: 10 small coding problems with hand-written test cases ---
TASKS = [
    {
        "id": "is_palindrome",
        "prompt": "Write a Python function `is_palindrome(s: str) -> bool` that returns True if the string is a palindrome (case-insensitive, ignoring spaces and punctuation). Only output the function, no preamble.",
        "tests": [
            ("is_palindrome('racecar')", True),
            ("is_palindrome('A man a plan a canal Panama')", True),
            ("is_palindrome('hello')", False),
            ("is_palindrome('')", True),
            ("is_palindrome('No lemon, no melon')", True),
        ],
    },
    {
        "id": "fizzbuzz",
        "prompt": "Write a Python function `fizzbuzz(n: int) -> list[str]` that returns the first n fizzbuzz outputs as strings. 'Fizz' for multiples of 3, 'Buzz' for 5, 'FizzBuzz' for both, otherwise the number as a string. Only output the function.",
        "tests": [
            ("fizzbuzz(5)", ["1", "2", "Fizz", "4", "Buzz"]),
            ("fizzbuzz(15)[-1]", "FizzBuzz"),
            ("fizzbuzz(3)[2]", "Fizz"),
        ],
    },
    {
        "id": "balanced_brackets",
        "prompt": "Write a Python function `is_balanced(s: str) -> bool` that returns True iff brackets in the string are balanced. Brackets are: ()[]{}. Other characters are ignored. Only output the function.",
        "tests": [
            ("is_balanced('()')", True),
            ("is_balanced('([])')", True),
            ("is_balanced('([)]')", False),
            ("is_balanced('hello (world)')", True),
            ("is_balanced('(((')", False),
        ],
    },
    {
        "id": "word_frequencies",
        "prompt": "Write a Python function `word_frequencies(text: str) -> dict[str, int]` that returns a dict mapping each unique word (lowercase, stripped of punctuation) to its count. Only output the function.",
        "tests": [
            ("word_frequencies('hello hello world')", {"hello": 2, "world": 1}),
            ("word_frequencies('The cat sat on the mat')", {"the": 2, "cat": 1, "sat": 1, "on": 1, "mat": 1}),
            ("word_frequencies('')", {}),
        ],
    },
    {
        "id": "fib_iterative",
        "prompt": "Write a Python function `fib(n: int) -> int` that returns the n-th Fibonacci number (0-indexed: fib(0)=0, fib(1)=1). Use iteration, not recursion. Only output the function.",
        "tests": [
            ("fib(0)", 0),
            ("fib(1)", 1),
            ("fib(10)", 55),
            ("fib(20)", 6765),
        ],
    },
    {
        "id": "merge_sorted",
        "prompt": "Write a Python function `merge_sorted(a: list, b: list) -> list` that merges two sorted lists into a single sorted list, preserving sort order. Don't use sorted(). Only output the function.",
        "tests": [
            ("merge_sorted([1, 3, 5], [2, 4, 6])", [1, 2, 3, 4, 5, 6]),
            ("merge_sorted([], [1, 2])", [1, 2]),
            ("merge_sorted([1, 1, 2], [1, 3])", [1, 1, 1, 2, 3]),
        ],
    },
    {
        "id": "rotate_list",
        "prompt": "Write a Python function `rotate(lst: list, k: int) -> list` that rotates a list left by k positions. Negative k rotates right. Don't mutate input. Only output the function.",
        "tests": [
            ("rotate([1, 2, 3, 4, 5], 2)", [3, 4, 5, 1, 2]),
            ("rotate([1, 2, 3], -1)", [3, 1, 2]),
            ("rotate([1, 2, 3], 0)", [1, 2, 3]),
            ("rotate([1, 2, 3], 5)", [3, 1, 2]),
        ],
    },
    {
        "id": "sum_digits",
        "prompt": "Write a Python function `sum_digits(n: int) -> int` that returns the sum of the absolute values of the digits of n. sum_digits(-123) == 6. Only output the function.",
        "tests": [
            ("sum_digits(123)", 6),
            ("sum_digits(-123)", 6),
            ("sum_digits(0)", 0),
            ("sum_digits(99999)", 45),
        ],
    },
    {
        "id": "anagram_groups",
        "prompt": "Write a Python function `group_anagrams(words: list[str]) -> list[list[str]]` that groups anagrams together. Return groups in order of first occurrence; words within each group in original order. Only output the function.",
        "tests": [
            (
                "group_anagrams(['eat', 'tea', 'tan', 'ate', 'nat', 'bat'])",
                [["eat", "tea", "ate"], ["tan", "nat"], ["bat"]],
            ),
            ("group_anagrams([])", []),
        ],
    },
    {
        "id": "first_non_repeated",
        "prompt": "Write a Python function `first_non_repeated(s: str) -> str` that returns the first character in s that appears only once, or '' if all characters repeat. Case-sensitive. Only output the function.",
        "tests": [
            ("first_non_repeated('aabbcdd')", "c"),
            ("first_non_repeated('aabb')", ""),
            ("first_non_repeated('abc')", "a"),
            ("first_non_repeated('')", ""),
        ],
    },
]


def call_opencode(prompt: str, model: str, mode: str, timeout: int = 180) -> tuple[str, float, int]:
    """Run opencode with the given prompt. Returns (output, elapsed_sec, exit_code)."""
    cmd = ["opencode", "run", prompt, "-m", model]
    if mode == "without-kit":
        cmd.append("--pure")
    start = time.time()
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace"
        )
        elapsed = time.time() - start
        return result.stdout + "\n" + result.stderr, elapsed, result.returncode
    except subprocess.TimeoutExpired:
        return "[TIMEOUT]", float(timeout), -1


def call_raw_api(prompt: str, model: str, api_key: str | None) -> tuple[str, float, int]:
    """Direct raw API call -- no harness, no tools, just chat completion.
    Currently supports OpenRouter URL pattern. Returns the same triple."""
    if not api_key:
        return "[no api key for raw mode]", 0.0, -1
    try:
        import urllib.request
    except ImportError:
        return "[urllib not available]", 0.0, -1
    start = time.time()
    body = json.dumps(
        {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 600}
    ).encode("utf-8")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        elapsed = time.time() - start
        text = data["choices"][0]["message"]["content"]
        return text, elapsed, 0
    except Exception as e:
        return f"[raw api error: {e}]", time.time() - start, -1


CODE_BLOCK_RE = re.compile(r"```(?:python|py)?\n(.*?)```", re.DOTALL)


def extract_python(output: str) -> str | None:
    """Extract a Python function from the model output."""
    matches = CODE_BLOCK_RE.findall(output)
    if matches:
        for m in matches:
            if "def " in m:
                return m
        return matches[0]
    if "def " in output:
        idx = output.index("def ")
        snippet = output[idx:]
        # Cut off at the first non-indented non-def line after the function body
        lines = snippet.split("\n")
        end = len(lines)
        for i, line in enumerate(lines[1:], 1):
            if line.strip() and not line.startswith((" ", "\t")) and not line.startswith("def "):
                end = i
                break
        return "\n".join(lines[:end])
    return None


def run_tests(code: str, tests: list[tuple[str, object]]) -> tuple[int, int, list[str]]:
    """Run tests against extracted code. Returns (passed, total, errors)."""
    errors = []
    passed = 0
    for expr, expected in tests:
        try:
            ns = {}
            exec(code, ns)
            actual = eval(expr, ns)
            if actual == expected:
                passed += 1
            else:
                errors.append(f"{expr!r} -> expected {expected!r}, got {actual!r}")
        except Exception as e:
            errors.append(f"{expr!r} raised {type(e).__name__}: {e}")
    return passed, len(tests), errors


def main():
    parser = argparse.ArgumentParser(description="Mini coding benchmark for the kit")
    parser.add_argument("--model", required=True, help="opencode model id (e.g. github-copilot/claude-haiku-4.5)")
    parser.add_argument(
        "--modes",
        default="with-kit,without-kit",
        help="comma-separated modes: with-kit, without-kit, raw-baseline",
    )
    parser.add_argument("--tasks", default=None, help="comma-separated task indices (e.g. 0,1,2). default: all")
    parser.add_argument("--raw-api-key", default=None, help="API key for raw-baseline mode (OpenRouter)")
    parser.add_argument("--raw-model", default=None, help="model id for raw-baseline (OpenRouter format)")
    parser.add_argument("--out", default=None, help="results JSON path")
    args = parser.parse_args()

    modes = [m.strip() for m in args.modes.split(",") if m.strip()]
    if args.tasks:
        indices = [int(i) for i in args.tasks.split(",")]
        tasks = [TASKS[i] for i in indices]
    else:
        tasks = TASKS

    out_path = Path(args.out or f"benchmarks/results-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json")
    results = {"model": args.model, "modes": modes, "tasks": []}

    print(f"\nRunning {len(tasks)} task(s) x {len(modes)} mode(s) = {len(tasks) * len(modes)} total runs")
    print(f"Model: {args.model}")
    print(f"Modes: {modes}")
    print()

    for ti, task in enumerate(tasks):
        print(f"[{ti+1}/{len(tasks)}] {task['id']}")
        task_result = {"id": task["id"], "modes": {}}
        for mode in modes:
            print(f"  -> {mode}...", end=" ", flush=True)
            if mode == "raw-baseline":
                output, elapsed, exit_code = call_raw_api(
                    task["prompt"], args.raw_model or args.model, args.raw_api_key
                )
            else:
                output, elapsed, exit_code = call_opencode(task["prompt"], args.model, mode)

            code = extract_python(output)
            if code is None:
                passed, total, errors = 0, len(task["tests"]), ["could not extract function from output"]
            else:
                passed, total, errors = run_tests(code, task["tests"])
            task_result["modes"][mode] = {
                "passed": passed,
                "total": total,
                "elapsed_sec": round(elapsed, 1),
                "exit_code": exit_code,
                "errors": errors[:3],   # truncate
                "output_chars": len(output),
            }
            tag = "PASS" if passed == total else f"{passed}/{total}"
            print(f"{tag} ({elapsed:.1f}s)")
        results["tasks"].append(task_result)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(results, indent=2), encoding="utf-8")

    # --- Summary table ---
    print("\n" + "=" * 70)
    print(f"{'task':<22}", end="")
    for mode in modes:
        print(f"{mode:<18}", end="")
    print()
    print("-" * 70)
    totals = {m: [0, 0, 0.0] for m in modes}   # [passed, total, total_time]
    for tr in results["tasks"]:
        print(f"{tr['id']:<22}", end="")
        for mode in modes:
            r = tr["modes"][mode]
            print(f"{r['passed']}/{r['total']} ({r['elapsed_sec']}s){' ' * 4}", end="")
            totals[mode][0] += r["passed"]
            totals[mode][1] += r["total"]
            totals[mode][2] += r["elapsed_sec"]
        print()
    print("-" * 70)
    print(f"{'TOTAL':<22}", end="")
    for mode in modes:
        p, t, dur = totals[mode]
        pct = 100 * p / t if t else 0
        print(f"{p}/{t} ({pct:.0f}%; {dur:.0f}s){' ':>2}", end="")
    print()
    print("=" * 70)
    print(f"\nResults written to: {out_path}")
    print("\nNotes:")
    print("  - 10 tasks is too small for statistical significance; use directionally only")
    print("  - 'raw-baseline' calls model API directly, NO file editing or tool use")
    print("  - 'with-kit' uses lifecycle hooks; 'without-kit' uses opencode --pure (no kit plugin)")
    print("  - Compare to Kimi K2.6's published HumanEval-class numbers as a sanity check")


if __name__ == "__main__":
    main()
