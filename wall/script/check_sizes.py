#!/usr/bin/env python3
"""Size gate — deployed bytecode for the contracts in wall/baseline/sizes.json.

Two profiles, because they answer different questions:

  default (fast, ~0.2s warm / ~25s after editing a widely-inherited file)
    The regression signal while editing, and what `make verify` runs.
    ContainerAgent is legitimately over EIP-170 here — it only fits under
    --via-ir — so absolute margins in this profile mean nothing on their own.

  --via-ir (~4m30s, `make sizes-deploy`)
    Matches how the containers are actually compiled for deployment, and is the
    only profile whose margins are real. Libraries are not linked in the
    measurement, so the deployed figure is smaller still.

ContainerAgent is pinned to its baseline byte-for-byte in both profiles. It has
roughly 75 bytes of via-ir headroom, so anything that reaches it — most likely
a change to a shared base such as Container — breaks its deployment. The pin
rejects a shrink as well as a growth: a shrink means something reached it too,
and the next change might not shrink.

Usage:
  python3 wall/script/check_sizes.py [--via-ir]            # gate
  python3 wall/script/check_sizes.py [--via-ir] --write    # re-baseline

Re-baseline only once a size change is understood and intended. The baseline is
a protected file, for the same reason the storage one is.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "wall" / "baseline" / "sizes.json"
PINNED = "ContainerAgent"


def measure(via_ir: bool) -> dict:
    args = ["forge", "build", "--sizes", "--json"]
    if via_ir:
        args.append("--via-ir")
    # Exits non-zero when any contract is over EIP-170, which is the normal
    # state of the default profile. Read stdout regardless.
    proc = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
    if not proc.stdout:
        raise SystemExit(f"forge build produced no output:\n{proc.stderr.strip()}")
    return json.loads(proc.stdout)


def main(argv: list[str]) -> int:
    via_ir = "--via-ir" in argv
    profile = "viaIr" if via_ir else "default"

    baseline = json.loads(BASELINE.read_text())
    limit = baseline["limit"]
    recorded = baseline[profile]

    sizes = measure(via_ir)
    contracts = list(recorded)

    if "--write" in argv:
        for contract in contracts:
            recorded[contract] = sizes[contract]["runtime_size"]
        BASELINE.write_text(json.dumps(baseline, indent=2) + "\n")
        print(f"sizes: {profile} baseline rewritten for {', '.join(contracts)}")
        return 0

    failed = False
    note = "" if via_ir else "  (absolute margins are not meaningful here)"
    print(f"  profile: {profile}{note}")

    for contract in contracts:
        was = recorded[contract]
        now = sizes[contract]["runtime_size"]
        delta = now - was
        sign = "—" if delta == 0 else f"{delta:+d}"
        row = f"  {contract:<20} {now:>6}  {sign:>6}  margin {limit - now:>7}"

        if contract == PINNED and delta != 0:
            failed = True
            print(f"{row}   WALL: pinned, must not change")
            continue

        # Only meaningful for a contract that was inside the limit to begin with.
        if was <= limit < now:
            failed = True
            print(f"{row}   WALL: over EIP-170")
            continue

        print(row)

    if failed:
        if not via_ir:
            print("\nRe-run `make sizes-deploy` for the figures that decide deployability.")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
