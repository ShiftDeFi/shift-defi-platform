#!/usr/bin/env python3
"""Storage gate — the sequential layout must stay append-only.

The contracts named in wall/baseline/storage.json sit behind live transparent
proxies, so an existing variable that changes slot, offset or type corrupts
deployed state on upgrade. The baseline must be a prefix of the current layout:
entries may be appended at the tail, never inserted, reordered, removed or
retyped.

Inserting into a shared base is the case worth naming. Every derived contract's
own variables follow Container's, so one insertion there shifts all of them,
and `forge inspect` reports it as a change at the first moved entry rather than
at the insertion.

Blind spot: ERC-7201 namespaced storage is computed in assembly and does not
appear in `forge inspect storageLayout` at all. This gate cannot see it, and
cannot verify a namespace constant. That is what a derivation test is for.

Usage:
  python3 wall/script/check_storage.py            # gate
  python3 wall/script/check_storage.py --write    # re-baseline (see below)

Re-baseline only when a layout change is intended and the affected proxies are
not yet deployed, or are being redeployed. The baseline is a protected file:
rewriting it is how this lane is made green without fixing anything, so the
change is reported at the end of the turn like any other gate edit.
"""

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "wall" / "baseline" / "storage.json"

# Solidity embeds the declaration's AST id in struct and enum type identifiers
# (`t_struct(AddressSet)7482_storage`), and those renumber whenever anything
# earlier in the compilation moves — including adding an unrelated file. Strip
# them, or every edit reports a spurious type change at an unmoved slot.
#
# Array types are left alone: the digits in `t_array(t_uint256)50_storage` are
# the array's length, which is part of the layout.
AST_ID = re.compile(r"t_(struct|enum)\(([^)]*)\)\d+")


def normalize_type(type_: str) -> str:
    return AST_ID.sub(r"t_\1(\2)", type_)


def current_layout(contract: str) -> list[dict]:
    proc = subprocess.run(
        ["forge", "inspect", contract, "storageLayout", "--json"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"forge inspect {contract} failed:\n{proc.stderr.strip()}")
    report = json.loads(proc.stdout)
    types = report.get("types") or {}
    # astId is dropped for the same reason as the ids inside type strings.
    return [
        {
            "label": entry["label"],
            "slot": int(entry["slot"]),
            "offset": entry["offset"],
            "type": normalize_type(entry["type"]),
            "bytes": int((types.get(entry["type"]) or {}).get("numberOfBytes", 0)),
        }
        for entry in report["storage"]
    ]


def describe(entry: dict) -> str:
    return f"{entry['label']} @ slot {entry['slot']}+{entry['offset']} ({entry['type']})"


def compare(baseline: list[dict], current: list[dict]) -> tuple[dict | None, list[dict]]:
    """The baseline must be a prefix of the current layout.

    Only the first divergence is returned. One inserted variable shifts every
    entry after it, so reporting the rest buries the one that explains them.
    """
    keys = ("label", "slot", "offset", "type")

    for index, (was, now) in enumerate(zip(baseline, current)):
        if any(was[k] != now[k] for k in keys):
            return {"index": index, "was": was, "now": now, "trailing": len(baseline) - index - 1}, []

    if len(current) < len(baseline):
        index = len(current)
        return {"index": index, "was": baseline[index], "now": None, "trailing": len(baseline) - index - 1}, []

    return None, current[len(baseline) :]


def main(argv: list[str]) -> int:
    baselines = json.loads(BASELINE.read_text())
    contracts = list(baselines)

    if "--write" in argv:
        BASELINE.write_text(json.dumps({c: current_layout(c) for c in contracts}, indent=2) + "\n")
        print(f"storage: baseline rewritten for {', '.join(contracts)}")
        return 0

    failed = False

    for contract in contracts:
        diverged, added = compare(baselines[contract], current_layout(contract))

        if diverged:
            failed = True
            now = diverged["now"]
            trailing = diverged["trailing"]
            print(f"\nWALL: {contract} storage diverges at entry {diverged['index']}")
            print(f"    expected  {describe(diverged['was'])}")
            print(f"    found     {describe(now) if now else 'nothing — the layout is shorter than the baseline'}")
            if trailing > 0:
                print(f"    {trailing} further recorded {'entry' if trailing == 1 else 'entries'} shift with it")
            continue

        suffix = ""
        if added:
            suffix = f" (+{len(added)} appended: {', '.join(a['label'] for a in added)})"
        print(f"  {contract}: {len(baselines[contract])} entries unchanged{suffix}")

    if failed:
        print(
            "\nThese contracts are behind live proxies. A moved slot corrupts deployed state.\n"
            "Append new variables at the tail, or use ERC-7201 namespaced storage, which\n"
            "occupies no sequential slot and is invisible to this gate by design."
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
