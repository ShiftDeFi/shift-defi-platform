#!/usr/bin/env python3
"""Stop hook: the gate must be green, and must not have been moved.

Two checks run before a turn is allowed to end.

FIRST, the gate itself. wall_turn_start.py hashed every protected file when the
turn began; this compares them. A change means a lane was made green by editing
what it checks rather than what it tests — accepting a finding, relaxing a
threshold, switching off a hook — and that is a human review decision.

The comparison is against the start of the turn, not against HEAD, so work in
progress on the gate does not fail every turn: what is reported is what this
turn did. It is also an exact comparison of file contents, which is why
wall_guard.py no longer tries to recognise a write from the text of a shell
command (see wall_protected.py).

SECOND, `make verify`, when any .sol differs in the working tree. A red gate
exits 2 and returns the failing output, which prevents the turn from ending.

Two cases exit 0 with a notice instead of blocking:

  - Missing toolchain. `make verify` needs slither and aderyn; blocking every
    turn on an uninstalled binary would only lead to hooks being switched off.
    CI still enforces the gate.
  - stop_hook_active, set when the turn is resuming from a previous block by
    this hook. Each check runs once per turn so an unfixable failure does not
    trap the session; run `make verify` directly to see what remains.
"""

import json
import pathlib
import shutil
import subprocess
import sys

from wall_config import VERIFY_TOOLS
from wall_protected import STATE, compare, snapshot

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAX_OUTPUT_LINES = 120


def solidity_changed() -> bool:
    proc = subprocess.run(
        ["git", "status", "--porcelain", "--", "*.sol"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return bool(proc.stdout.strip())


def gate_moved() -> list[str]:
    """Protected files that changed during this turn.

    An absent baseline means the turn started without wall_turn_start.py
    running — a fresh clone, a resumed session, a hook not yet installed. There
    is nothing to compare against, so one is established and the turn passes.
    """
    try:
        baseline = json.loads(STATE.read_text())
    except (OSError, json.JSONDecodeError, ValueError):
        try:
            STATE.write_text(json.dumps(snapshot()))
        except OSError:
            pass
        return []
    return compare(baseline)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        payload = {}

    if payload.get("stop_hook_active"):
        return 0

    moved = gate_moved()
    if moved:
        listing = "\n".join(f"  - {path}" for path in moved)
        print(
            "Wall: these files define the gate, and this turn changed them:\n\n"
            f"{listing}\n\n"
            "Accepting a finding, relaxing a threshold or disabling a hook is a "
            "human review decision — CLAUDE.md requires it to be proposed, not "
            "made. Restore them to how they were when the turn started, then "
            "say what you would change and why, and let the human apply it.\n\n"
            "If the change was asked for, say so plainly and leave it in place; "
            "this check runs once per turn and will not block again.",
            file=sys.stderr,
        )
        return 2

    if not solidity_changed():
        return 0

    missing = [tool for tool in VERIFY_TOOLS if shutil.which(tool) is None]
    if missing:
        print(
            f"Wall: skipping `make verify` — not installed: {', '.join(missing)}. "
            "See the toolchain table in CLAUDE.md."
        )
        return 0

    verify = subprocess.run(
        ["make", "verify"], cwd=ROOT, capture_output=True, text=True
    )
    if verify.returncode != 0:
        out = (verify.stdout + verify.stderr).strip().splitlines()
        tail = "\n".join(out[-MAX_OUTPUT_LINES:])
        print(
            "Wall: `make verify` is red and Solidity changed in this turn. Fix "
            "the failing lane below, or state plainly that it is unresolved.\n\n"
            + tail,
            file=sys.stderr,
        )
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
