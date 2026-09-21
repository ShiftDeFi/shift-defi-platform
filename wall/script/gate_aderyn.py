#!/usr/bin/env python3
"""Aderyn gate — per-finding triage, keyed by detector + path + line + anchor.

Fails the build if any current gated finding instance is not in the
acknowledged set. This is a per-finding model rather than a count: a new
instance of an already-accepted detector is a new key, so it still fails.

What gates: every HIGH-severity finding, plus the LOW-severity detectors named
in GATED_LOW_DETECTORS. Aderyn reports only two severities, and its low band
carries both advisory findings and rules this repo enforces, so detectors are
listed individually rather than by severity.

The anchor is a short digest of the source line the finding sits on, with
whitespace collapsed so a reflow is not a change. It makes the key
self-describing: an accepted entry carries the text it was accepted against, so
a finding that only moved can be recognised as the same finding without
consulting git. retriage_aderyn.py pairs on it, and the failure output below
uses it to say whether an un-triaged instance moved, changed, or is new.

Entries written before the anchor field are honoured on detector, path and line
alone. They are reported, because a key without an anchor cannot be re-anchored.

Report schema:
  report["high_issues"]["issues"] is a list of issue objects, one per detector.
  Each has "detector_name" and an "instances" list; each instance has
  "contract_path" and "line_no". Aderyn groups by detector, so the number of
  issue objects is not the number of findings — descend into instances.
  report["low_issues"] has the same shape.

Files (relative to the repo root):
  aderyn.out.json   the report (input, regenerated each run)
  aderyn.triage     one acknowledged key per line, "# comment" allowed.
                    Key format: detector_name|contract_path|line_no|anchor
                    Committed after human review.

Usage:
  python3 gate_aderyn.py aderyn.out.json                 # gate
  python3 gate_aderyn.py aderyn.out.json --print-keys    # list current keys
"""

import hashlib
import json
import pathlib
import sys

TRIAGE = pathlib.Path("aderyn.triage")

# Hex characters of the source-line digest kept in a key. Long enough that two
# different statements in one file do not collide, short enough to read.
ANCHOR_LEN = 12

# Stands in for an anchor that could not be computed — an unreadable path, or a
# line number outside the file. It pairs with nothing.
UNKNOWN_ANCHOR = "?"

# Low-severity detectors promoted to gating. Each entry is a repository rule,
# not a severity judgement by the tool.
GATED_LOW_DETECTORS = {
    # Every function that modifies state must emit an event describing the
    # change. One event may cover several variables written in the same call.
    "state-change-without-event",
    # An address parameter written to storage must be checked against zero.
    # Only covers addresses that reach storage — a parameter merely passed on
    # to a call is not flagged by either engine.
    "state-no-address-check",
}

_SOURCE: dict[str, list[str] | None] = {}


def normalize(text: str) -> str:
    """Source text with whitespace collapsed, so a reflow is not a change."""
    return " ".join(text.split())


def source_lines(path: str) -> list[str] | None:
    """The working-tree lines of `path`, read once per run."""
    if path not in _SOURCE:
        try:
            _SOURCE[path] = pathlib.Path(path).read_text().splitlines()
        except OSError:
            _SOURCE[path] = None
    return _SOURCE[path]


def anchor(path: str, line_no: object) -> str:
    """Digest of the normalized source line a finding sits on."""
    lines = source_lines(path)
    if lines is None or not isinstance(line_no, int):
        return UNKNOWN_ANCHOR
    if not 1 <= line_no <= len(lines):
        return UNKNOWN_ANCHOR
    text = normalize(lines[line_no - 1]).encode()
    return hashlib.sha256(text).hexdigest()[:ANCHOR_LEN]


def split_key(key: str) -> tuple[str, str, int, str] | None:
    """A key as (detector, path, line, anchor); anchor is "" when absent."""
    parts = key.split("|")
    if len(parts) == 3:
        parts.append("")
    if len(parts) != 4 or not parts[2].isdigit():
        return None
    return parts[0], parts[1], int(parts[2]), parts[3]


def instance_keys(report: dict) -> list[str]:
    """Every gated finding instance as a key: detector|path|line|anchor."""
    keys = []
    bands = (
        ("high_issues", None),
        ("low_issues", GATED_LOW_DETECTORS),
    )
    for band, allowed in bands:
        for issue in (report.get(band) or {}).get("issues", []):
            detector = issue.get("detector_name", "unknown-detector")
            if allowed is not None and detector not in allowed:
                continue
            for inst in issue.get("instances", []):
                path = inst.get("contract_path", "?")
                line = inst.get("line_no", "?")
                keys.append(f"{detector}|{path}|{line}|{anchor(path, line)}")
    return keys


def load_acknowledged() -> list[str]:
    if not TRIAGE.exists():
        return []
    out = []
    for raw in TRIAGE.read_text().splitlines():
        line = raw.strip()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def accepted_by(acknowledged: list[str]) -> tuple[set[str], set[tuple[str, str, int]]]:
    """Exact keys, and the (detector, path, line) triples of legacy entries."""
    exact = set(acknowledged)
    legacy = set()
    for key in acknowledged:
        parsed = split_key(key)
        if parsed and not parsed[3]:
            legacy.add(parsed[:3])
    return exact, legacy


def classify(key: str, acknowledged: list[str]) -> str:
    """Why an un-triaged instance is un-triaged: moved, changed, or new."""
    parsed = split_key(key)
    if not parsed:
        return "new"
    detector, path, line, anchored = parsed
    for other in acknowledged:
        prior = split_key(other)
        if not prior or prior[0] != detector or prior[1] != path:
            continue
        if anchored != UNKNOWN_ANCHOR and prior[3] == anchored and prior[2] != line:
            return "moved"
        if prior[2] == line and prior[3] and prior[3] != anchored:
            return "changed"
    return "new"


def main(argv: list[str]) -> int:
    path = argv[1]
    report = json.loads(pathlib.Path(path).read_text())
    current = instance_keys(report)

    if "--print-keys" in argv:
        for k in current:
            print(k)
        return 0

    acknowledged = load_acknowledged()
    exact, legacy = accepted_by(acknowledged)
    new = []
    for k in current:
        parsed = split_key(k)
        if k in exact or (parsed and parsed[:3] in legacy):
            continue
        new.append(k)

    print(
        f"aderyn: {len(current)} gated instance(s); "
        f"{len(acknowledged)} acknowledged; {len(new)} un-triaged."
    )
    if legacy:
        print(
            f"aderyn: {len(legacy)} acknowledged key(s) predate the anchor field "
            "and cannot be re-anchored; re-accept them from the keys above."
        )
    if not new:
        return 0

    verdicts = {k: classify(k, acknowledged) for k in new}
    print("WALL: gated finding(s) not in aderyn.triage:")
    for k in new:
        note = {
            "moved": "  (accepted finding, moved)",
            "changed": "  (accepted key, code at it changed)",
            "new": "",
        }[verdicts[k]]
        print(f"  - {k}{note}")

    moved = [k for k, v in verdicts.items() if v == "moved"]
    if moved:
        print(
            f"{len(moved)} of these only moved: `make retriage` re-anchors them "
            "without accepting anything new."
        )
    if len(moved) < len(new):
        print("For the rest, fix the code, or add the key to aderyn.triage after")
        print("review. The wall-triage skill covers deciding between the two.")
    return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: gate_aderyn.py <aderyn.out.json> [--print-keys]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv))
