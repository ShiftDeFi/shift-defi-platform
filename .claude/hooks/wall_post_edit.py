#!/usr/bin/env python3
"""PostToolUse hook: format and compile after Solidity changes.

Receives the tool-call context as JSON on stdin. Calls that changed no
Solidity exit 0 immediately.

Formatting is applied rather than reported, so a formatting difference does not
cost a round trip. A compile failure exits 2, which returns stderr as feedback.

Write and Edit name the file they touched. Bash does not, and a contract
written with a heredoc, `sed -i` or a script is just as much an edit — so for
Bash the hook compares a snapshot of every .sol file's mtime and size against
the previous call and formats whatever moved. Without this the in-turn compile
loop is silently off for any agent that edits through the shell.

The snapshot lives in .git/, which is per-clone and never committed. It is
written after formatting, since the formatter moves the mtimes the next call
would otherwise read as a fresh edit, and it is written on failure too, so a
broken tree is reported once per change rather than once per shell command.
The Stop hook is what catches a tree that never compiled.
"""

import json
import pathlib
import shutil
import subprocess
import sys

from wall_config import FMT_CMD, REQUIRED_TOOL

ROOT = pathlib.Path(__file__).resolve().parents[2]
STATE = ROOT / ".git" / "wall-post-edit-state.json"
MAX_OUTPUT_LINES = 80


def sol_files() -> list[str]:
    """Every tracked or untracked .sol path. Submodules under lib/ are a
    gitlink to the superproject and ignored trees are excluded, so out/ and
    cache/ build artefacts do not appear."""
    proc = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "--", "*.sol"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return [line for line in proc.stdout.splitlines() if line]


def snapshot() -> dict[str, list[int]]:
    out = {}
    for rel in sol_files():
        try:
            st = (ROOT / rel).stat()
        except OSError:
            continue
        out[rel] = [st.st_mtime_ns, st.st_size]
    return out


def load_state() -> dict[str, list[int]] | None:
    try:
        return json.loads(STATE.read_text())
    except (OSError, json.JSONDecodeError, ValueError):
        return None


def save_state(state: dict[str, list[int]]) -> None:
    try:
        STATE.write_text(json.dumps(state))
    except OSError:
        pass


def changed_via_shell() -> list[str]:
    """Paths whose mtime or size moved since the previous call. An absent
    snapshot means there is no baseline to compare against, so nothing is
    reported and the baseline is established instead."""
    current = snapshot()
    previous = load_state()
    if previous is None:
        save_state(current)
        return []
    return [rel for rel, stamp in current.items() if previous.get(rel) != stamp]


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if shutil.which(REQUIRED_TOOL) is None:
        return 0

    tool = payload.get("tool_name") or ""
    tool_input = payload.get("tool_input") or {}
    tool_response = payload.get("tool_response") or {}

    if tool == "Bash":
        changed = changed_via_shell()
    else:
        path = tool_input.get("file_path") or tool_response.get("filePath") or ""
        changed = [path] if path.endswith(".sol") else []

    if not changed:
        return 0

    # One invocation for the whole set: the formatter runs through npx, whose
    # startup dominates the run, and a shell edit can move several files at once.
    present = [path for path in changed if (ROOT / path).exists()]
    if present:
        subprocess.run([*FMT_CMD, *present], cwd=ROOT, capture_output=True, text=True)

    build = subprocess.run(["forge", "build"], cwd=ROOT, capture_output=True, text=True)
    save_state(snapshot())

    if build.returncode != 0:
        out = (build.stdout + build.stderr).strip().splitlines()
        tail = "\n".join(out[-MAX_OUTPUT_LINES:])
        names = ", ".join(sorted(pathlib.Path(p).name for p in changed))
        print(f"Wall: {names} does not compile.\n\n{tail}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
