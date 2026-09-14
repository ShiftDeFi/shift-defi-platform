#!/usr/bin/env python3
"""PreToolUse hook: refuse to let the gate be edited instead of satisfied.

Accepting a finding, relaxing a threshold or disabling a hook is a human review
decision, and CLAUDE.md requires it to be proposed rather than made. This hook
declines the write and returns the reason, so the proposal happens.

Three checks, in order of how much of the file they claim:

  By path, against PROTECTED_PATHS — reviewed state, gate definitions, the hook
  scripts and CI. Nothing in these is routine, so any write is refused.

  By key, for foundry.toml — gate thresholds sit next to fuzz runs and the
  output directory, so what is refused is an edit whose text names a protected
  setting.

  By subtree, for the agent settings files — the hooks that run the gate sit
  next to permissions, model and theme. The edit is applied in memory and the
  result parsed; the write is refused only if the `hooks` or `env` subtree comes
  out different. Text matching would not do here: a nested edit can defang a
  hook without the word "hooks" appearing in it, and the string appears in every
  full-file rewrite whether or not the hooks changed.

Shell routes are not checked here. See wall_protected.py for why matching
command text was the wrong instrument, and wall_stop.py for what replaced it: a
comparison of the gate's actual state across the turn, which catches a write
through any route and cannot be fooled by a command that merely quotes a path.

This is not a security boundary. WALL_GUARD=0 in the session environment lifts
it, and the person at the terminal can always edit the file directly. What it
removes is the quiet path — silencing a lane becomes a deliberate act with a
diff attached, and review of that diff is what enforces the gate.

Exits 2 to block the call and return stderr to the model, 0 to allow it.
"""

import json
import os
import pathlib
import sys

from wall_protected import (
    FOUNDRY_TOML,
    PROTECTED_SETTINGS,
    ROOT,
    SETTINGS_GATE_KEYS,
    gate_subtrees,
    protected_path,
    settings_file,
)

WRITING_TOOLS = ("Write", "Edit", "MultiEdit", "NotebookEdit")

REFUSAL = (
    "Wall: {what}\n\n"
    "This file is the gate, not the code under test. Accepting a finding, "
    "relaxing a threshold or disabling a hook is a human review decision — "
    "CLAUDE.md requires it to be proposed, not made.\n\n"
    "Fix the code so the lane passes. If the finding is genuinely acceptable, "
    "explain why and what key or setting you would add, and let the human "
    "apply it.\n\n"
    "(A human can set WALL_GUARD=0 to lift this hook.)"
)


def touched_settings(tool_input: dict) -> list[str]:
    """Protected foundry.toml keys named in the text this call would write."""
    text = " ".join(
        str(tool_input.get(key) or "")
        for key in ("content", "old_string", "new_string")
    )
    return [setting for setting in PROTECTED_SETTINGS if setting in text]


def current_text(rel: str) -> str | None:
    try:
        return (ROOT / rel).read_text()
    except OSError:
        return None


def proposed_text(rel: str, tool_input: dict) -> str | None:
    """The file's content as this call would leave it, or None if that cannot
    be worked out — in which case the caller refuses rather than guesses."""
    if "content" in tool_input:
        return str(tool_input.get("content") or "")

    text = current_text(rel)
    if text is None:
        return None

    edits = tool_input.get("edits")
    if not isinstance(edits, list):
        edits = [tool_input]

    for edit in edits:
        if not isinstance(edit, dict):
            return None
        old = edit.get("old_string")
        new = edit.get("new_string")
        if old is None or new is None or old not in text:
            return None
        count = -1 if edit.get("replace_all") else 1
        text = text.replace(str(old), str(new), count)
    return text


def main() -> int:
    if os.environ.get("WALL_GUARD") == "0":
        return 0

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    if (payload.get("tool_name") or "") not in WRITING_TOOLS:
        return 0

    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path") or "")

    pattern = protected_path(path)
    if pattern:
        print(REFUSAL.format(what=f"{pattern} is protected."), file=sys.stderr)
        return 2

    if pathlib.Path(path).name == FOUNDRY_TOML:
        keys = touched_settings(tool_input)
        if keys:
            print(
                REFUSAL.format(
                    what="this edit changes gate settings in "
                    f"{FOUNDRY_TOML}: {', '.join(keys)}."
                ),
                file=sys.stderr,
            )
            return 2
        return 0

    rel = settings_file(path)
    if rel:
        proposed = proposed_text(rel, tool_input)
        if proposed is None:
            print(
                REFUSAL.format(
                    what=f"this edit to {rel} cannot be read before it is "
                    "applied, so whether it changes the gate is unknown."
                ),
                file=sys.stderr,
            )
            return 2
        after = gate_subtrees(proposed)
        if after == "<unparseable>":
            print(
                REFUSAL.format(
                    what=f"this edit would leave {rel} unparseable, so whether "
                    "it changes the gate is unknown."
                ),
                file=sys.stderr,
            )
            return 2
        if after != gate_subtrees(current_text(rel)):
            print(
                REFUSAL.format(
                    what=f"this edit changes the "
                    f"{' or '.join(SETTINGS_GATE_KEYS)} block in {rel}."
                ),
                file=sys.stderr,
            )
            return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
