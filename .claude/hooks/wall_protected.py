#!/usr/bin/env python3
"""The files that define the gate, shared by the hooks that protect them.

A lane can be made green by editing one of these instead of the code: a finding
accepted into aderyn.triage or slither.db.json, a rule dropped from [lint]
exclude_lints, a threshold loosened in wall.mk, a hook switched off in
.claude/settings.json. None of those are code fixes, and none of them are
visible in a green run.

Two hooks share this list, and they check it in different ways.

wall_guard.py refuses Write and Edit against it. That check is exact, because
the tool call names the file it is about to write.

Shell routes are deliberately not pattern-matched. Matching regexes against
command text was tried and is the wrong instrument: it blocked commands that
merely quoted a protected path — documentation about the gate, a `cmp` of two
files, an `echo` containing the word "patch" — while still missing a write
buried in a heredoc body, which is where a script's real work lives. It guesses
what a command will do from how it reads. So instead wall_turn_start.py records
a hash per file when the turn begins and wall_stop.py compares them when it
ends: a write is caught by its effect, whatever route it took, and a command
that only mentions a path is not a write.

Three files are mixed rather than protected outright, and are compared by the
part of them that is the gate:

  foundry.toml carries gate thresholds next to routine settings, so what is
  compared is the subset of its lines naming a protected setting. Editing fuzz
  runs is ordinary work; relaxing exclude_lints is not.

  .claude/settings.json and .claude/settings.local.json carry the hooks that
  run the gate next to permissions, model and theme. What is compared is the
  `hooks` and `env` subtrees — `env` because it can set WALL_GUARD=0 — parsed
  rather than matched as text, since a nested edit can defang a hook without
  the word "hooks" appearing anywhere in it.
"""

import fnmatch
import hashlib
import json
import pathlib

from wall_config import PROTECTED_PATHS, PROTECTED_SETTINGS

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Per-clone, never committed, and alongside the post-edit hook's own snapshot.
STATE = ROOT / ".git" / "wall-protected-state.json"

FOUNDRY_TOML = "foundry.toml"

# Agent settings files, protected by subtree rather than by path.
SETTINGS_FILES = (
    ".claude/settings.json",
    ".claude/settings.local.json",
)

# `hooks` wires the gate into the session. `env` can lift the guard with
# WALL_GUARD=0, or waive the invariant requirement.
SETTINGS_GATE_KEYS = ("hooks", "env")


def protected_path(raw: str) -> str | None:
    """The matched pattern if `raw` names a fully protected file, else None."""
    if not raw:
        return None
    rel = relative(raw)
    if rel is None:
        return None
    for pattern in PROTECTED_PATHS:
        if fnmatch.fnmatch(rel, pattern):
            return pattern
    return None


def settings_file(raw: str) -> str | None:
    """The matched settings file if `raw` names one, else None."""
    if not raw:
        return None
    rel = relative(raw)
    if rel is None:
        return None
    return rel if rel in SETTINGS_FILES else None


def relative(raw: str) -> str | None:
    """`raw` as a repo-relative posix path, or None if it is outside the repo.

    Agent settings and hooks can be addressed from outside the tree, so those
    are recognised by their tail.
    """
    path = pathlib.Path(raw)
    if not path.is_absolute():
        path = ROOT / path
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        pass
    tail = path.as_posix()
    for candidate in SETTINGS_FILES:
        if fnmatch.fnmatch(tail, f"*/{candidate}"):
            return candidate
    if fnmatch.fnmatch(tail, "*/.claude/hooks/*.py"):
        return f".claude/hooks/{path.name}"
    return None


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_files() -> dict[str, str]:
    """A hash per protected file that exists. A file appearing or disappearing
    is itself a change to the gate, so the key set matters as much as the
    values."""
    out: dict[str, str] = {}
    for pattern in PROTECTED_PATHS:
        for path in sorted(ROOT.glob(pattern)):
            if path.is_file():
                try:
                    out[path.relative_to(ROOT).as_posix()] = digest(path)
                except OSError:
                    continue
    return out


def settings_fingerprint() -> list[str]:
    """The lines of foundry.toml that name a protected setting. Editing fuzz
    runs or the output directory does not move this; relaxing the gate does."""
    try:
        lines = (ROOT / FOUNDRY_TOML).read_text().splitlines()
    except OSError:
        return []
    return [
        " ".join(line.split())
        for line in lines
        if any(setting in line for setting in PROTECTED_SETTINGS)
    ]


def gate_subtrees(text: str | None) -> str:
    """The `hooks` and `env` subtrees of a settings document, canonically
    serialised so two documents that differ only in formatting, key order or
    unrelated keys compare equal.

    Text that does not parse returns a sentinel rather than raising: a caller
    comparing two documents should treat unparseable as different from
    anything, and wall_guard.py refuses an edit whose result cannot be read.
    """
    if text is None:
        return json.dumps({}, sort_keys=True)
    try:
        data = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        return "<unparseable>"
    if not isinstance(data, dict):
        return "<unparseable>"
    return json.dumps(
        {key: data.get(key) for key in SETTINGS_GATE_KEYS},
        sort_keys=True,
        separators=(",", ":"),
    )


def agent_settings_fingerprint() -> dict[str, str]:
    """The gate subtrees of every settings file that exists."""
    out = {}
    for rel in SETTINGS_FILES:
        path = ROOT / rel
        try:
            out[rel] = gate_subtrees(path.read_text())
        except OSError:
            continue
    return out


def snapshot() -> dict:
    return {
        "files": protected_files(),
        "settings": settings_fingerprint(),
        "agent": agent_settings_fingerprint(),
    }


def compare(baseline: dict) -> list[str]:
    """What changed since `baseline`, as human-readable path descriptions."""
    current_files = protected_files()
    baseline_files = baseline.get("files") or {}

    changed = []
    for rel, value in current_files.items():
        if rel not in baseline_files:
            changed.append(f"{rel} (added)")
        elif baseline_files[rel] != value:
            changed.append(rel)
    for rel in baseline_files:
        if rel not in current_files:
            changed.append(f"{rel} (removed)")

    if (baseline.get("settings") or []) != settings_fingerprint():
        changed.append(f"{FOUNDRY_TOML} (gate settings)")

    # A baseline written before this dimension existed cannot be compared
    # against; the next turn records one.
    if "agent" in baseline:
        current_agent = agent_settings_fingerprint()
        baseline_agent = baseline.get("agent") or {}
        for rel in sorted(set(baseline_agent) | set(current_agent)):
            if baseline_agent.get(rel) != current_agent.get(rel):
                changed.append(f"{rel} ({', '.join(SETTINGS_GATE_KEYS)})")

    return sorted(changed)
