#!/usr/bin/env python3
"""Re-anchor accepted aderyn keys that only moved.

`aderyn.triage` keys a finding as detector|path|line|anchor, so inserting a line
above a reviewed finding renumbers its key. The key stops matching, the gate
fails, and the fix is to retype a number — a mechanical edit that is
indistinguishable from accepting a finding, and so costs a human review step on
almost every commit that grows a file.

This re-anchors those keys, and only those. A stale accepted key is paired with
a current finding when the detector, the path and the anchor are all identical —
the code did not change, its line number did.

The anchor travels in the key, so the comparison needs no baseline outside the
file. That is what makes a chain of edits work: an earlier run has already moved
the key away from the committed line numbers, and there is no committed text to
compare against any more. Reading the old text from HEAD, as this did before,
re-anchored correctly once per commit and then paired nothing.

What it will not do:

  - Add a key. A current finding with no stale counterpart is a new finding,
    and accepting one is a human review decision. It is reported and the exit
    status is non-zero.
  - Remove a key. A stale key that pairs with nothing may mean the finding was
    fixed, or that the anchored code changed and deserves re-reading. Both are
    review decisions, so it is reported and left in place.
  - Pair ambiguously. Where several accepted findings in one file share the same
    anchor — the same statement written twice — they are paired in line order,
    and only when as many are stale as are current. Any other count means one of
    them is new, and the group is left alone.
  - Re-anchor a key written before the anchor field. There is no recorded text
    to pair on, so it is reported for review.

Comments, blank lines and entry order in aderyn.triage are preserved: only the
line numbers on re-anchored keys change.

Usage:
  python3 script/retriage_aderyn.py aderyn.out.json           # re-anchor
  python3 script/retriage_aderyn.py aderyn.out.json --check   # report only
"""

import json
import pathlib
import sys

from gate_aderyn import TRIAGE, UNKNOWN_ANCHOR, instance_keys, split_key


def by_line(key: str) -> int:
    parsed = split_key(key)
    return parsed[2] if parsed else 0


def pair(stale: list[str], new: list[str]) -> dict[str, str]:
    """Map stale keys to the current keys carrying the same anchor."""
    groups: dict[tuple[str, str, str], tuple[list[str], list[str]]] = {}
    for key in stale:
        parsed = split_key(key)
        if parsed and parsed[3] and parsed[3] != UNKNOWN_ANCHOR:
            groups.setdefault((parsed[0], parsed[1], parsed[3]), ([], []))[0].append(key)
    for key in new:
        parsed = split_key(key)
        if parsed and parsed[3] and parsed[3] != UNKNOWN_ANCHOR:
            group = groups.get((parsed[0], parsed[1], parsed[3]))
            if group is not None:
                group[1].append(key)

    remap: dict[str, str] = {}
    for stale_keys, new_keys in groups.values():
        if not new_keys or len(stale_keys) != len(new_keys):
            continue
        for old, fresh in zip(sorted(stale_keys, key=by_line), sorted(new_keys, key=by_line)):
            remap[old] = fresh
    return remap


def main(argv: list[str]) -> int:
    report = json.loads(pathlib.Path(argv[1]).read_text())
    check_only = "--check" in argv

    current = instance_keys(report)
    raw = TRIAGE.read_text().splitlines() if TRIAGE.exists() else []
    accepted = [line.strip() for line in raw if line.strip() and not line.strip().startswith("#")]

    stale = [k for k in accepted if k not in current]
    new = [k for k in current if k not in accepted]
    remap = pair(stale, new)

    legacy = [k for k in stale if (split_key(k) or ("", "", 0, "x"))[3] == ""]

    for old, fresh in sorted(remap.items()):
        print(f"  re-anchor    {old}  ->  {split_key(fresh)[2]}")
    for key in sorted(k for k in stale if k not in remap and k not in legacy):
        print(f"  stale        {key}  (finding gone, or its code changed — review)")
    for key in sorted(legacy):
        print(f"  legacy       {key}  (no anchor to pair on — re-accept it)")
    for key in sorted(k for k in new if k not in remap.values()):
        print(f"  NEW FINDING  {key}  (not accepted — review required)")

    unresolved = [k for k in new if k not in remap.values()]
    left_stale = [k for k in stale if k not in remap]
    print(
        f"retriage: {len(remap)} re-anchored, {len(left_stale)} stale, "
        f"{len(unresolved)} new finding(s) needing review."
    )

    if remap and not check_only:
        out = []
        for line in raw:
            key = line.strip()
            out.append(remap[key] if key in remap else line)
        TRIAGE.write_text("\n".join(out) + "\n")
        print(f"retriage: rewrote {TRIAGE}.")
    elif remap and check_only:
        print("retriage: --check, nothing written.")

    if unresolved:
        print("Fix the code, or add the key to aderyn.triage after review.")
        return 1
    if check_only and remap:
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: retriage_aderyn.py <aderyn.out.json> [--check]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv))
