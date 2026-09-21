#!/usr/bin/env python3
"""forge lint gate.

`forge lint` reports findings but exits 0, so on its own it cannot gate a
build. This runs it with JSON output, counts the diagnostics, and fails when
any are present.

Suppression is configured natively in foundry.toml rather than in a triage file
next to this script: `[lint] exclude_lints` silences a rule outright, and
`mixed_case_exceptions` allows specific casing (ERC, URI, ...). `[lint]
severity` selects which severities run at all.

Usage:
  python3 gate_lint.py [path ...]      # defaults to the configured src dir
"""

import json
import os
import subprocess
import sys


def diagnostics(paths: list[str]) -> list[dict]:
    proc = subprocess.run(
        ["forge", "lint", "--json", *paths],
        capture_output=True,
        text=True,
    )
    # forge lint writes its JSON diagnostics to stderr, not stdout. Read both
    # so the gate does not silently pass when the stream layout changes.
    found = []
    for line in (proc.stdout + "\n" + proc.stderr).splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("$message_type") == "diagnostic":
            found.append(obj)
    if not found and proc.returncode != 0:
        sys.stderr.write(proc.stderr)
    return found


def describe(diag: dict) -> str:
    code = (diag.get("code") or {}).get("code", "?")
    level = diag.get("level", "?")
    spans = diag.get("spans") or [{}]
    span = next((s for s in spans if s.get("is_primary")), spans[0])
    path = span.get("file_name", "?")
    line = span.get("line_start", "?")
    return f"{level}[{code}] {path}:{line} — {diag.get('message', '')}"


def main(argv: list[str]) -> int:
    paths = argv[1:] or [os.environ.get("SRC_DIR", "src")]
    found = diagnostics(paths)

    print(f"gate_lint: {len(found)} finding(s).")
    if found:
        print("WALL: forge lint findings:")
        for d in found:
            print(f"  - {describe(d)}")
        print(
            "Fix the code, or configure [lint] exclude_lints / "
            "mixed_case_exceptions in foundry.toml after review."
        )
        print("The wall-triage skill covers deciding between the two.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
