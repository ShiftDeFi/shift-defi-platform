#!/usr/bin/env python3
"""Test gate — presence and naming.

Two checks run against the same `forge test --list --json` listing, so the
lane pays for only one compile.

PRESENCE
--------
`forge test` exits 0 when it finds no tests at all:

    $ forge test --no-match-path "test/invariant/*"
    Nothing to compile
    $ echo $?
    0

On a repo with contracts but no test files, every test lane would pass without
executing anything. This gate counts tests before they run and fails when a
required category is empty.

Invariant tests are required by default, since static analysis does not catch
accounting or authorization errors that are only wrong relative to the rest of
the contract. To stage adoption:

    WALL_REQUIRE_INVARIANT=0 make verify

NAMING
------
Accepted forms, where each segment is PascalCase:

    test_Subject                        a behaviour that should succeed
    test_Subject_Detail                 ... narrowed to one aspect of it
    test_RevertIf_Subject_Reason        a behaviour that should revert
    testFuzz_Subject                    fuzzed variants of the above
    testFuzz_RevertIf_Subject_Reason
    invariant_Property                  invariant/property tests

A reverting test must name the reason, so `test_RevertIf_Subject` alone is
rejected: the reason segment is what distinguishes one revert path of a
function from another, and a test that reverts for the wrong reason still
passes. `testFail_` is rejected outright — it passes on *any* revert, which
makes it indistinguishable from a test that fails for an unrelated cause.

Nothing in Foundry enforces this, and the `lint` lane is scoped to src/, so
this is the only place naming is checked.

Limit: the listing only contains functions Foundry already recognises as
tests. A misspelled prefix (`tets_Foo`) is not a test to Foundry, so it is
invisible here and is silently never run.

Counts come from `forge test --list --json`, which emits a
{path: {contract: [test, ...]}} map. A tree with nothing to compile emits
non-JSON output instead, which is counted as zero tests.
"""

import json
import os
import re
import subprocess
import sys

INVARIANT_PREFIX = os.environ.get("INVARIANT_DIR", "test/invariant") + "/"

_PASCAL = r"[A-Z][A-Za-z0-9]*"

# The negative lookahead matters: without it `test_RevertIf_Subject` — a
# reverting test with no reason — would match the positive form, reading
# "RevertIf" as the subject and "Subject" as the detail.
_ACCEPTED = tuple(
    re.compile(p)
    for p in (
        rf"^test_(?!RevertIf_){_PASCAL}(?:_{_PASCAL})*$",
        rf"^test_RevertIf_{_PASCAL}(?:_{_PASCAL})+$",
        rf"^testFuzz_(?!RevertIf_){_PASCAL}(?:_{_PASCAL})*$",
        rf"^testFuzz_RevertIf_{_PASCAL}(?:_{_PASCAL})+$",
        rf"^invariant_{_PASCAL}(?:_{_PASCAL})*$",
    )
)

_ACCEPTED_FORMS = (
    "test_Subject",
    "test_Subject_Detail",
    "test_RevertIf_Subject_Reason",
    "testFuzz_Subject",
    "testFuzz_RevertIf_Subject_Reason",
    "invariant_Property",
)


def list_tests() -> dict:
    """Parse `forge test --list --json`. Returns {} when nothing compiles."""
    proc = subprocess.run(
        ["forge", "test", "--list", "--json"],
        capture_output=True,
        text=True,
    )
    # forge may print build logs before the JSON payload, so scan for the first
    # line that parses as an object.
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
    return {}


def count(listing: dict) -> tuple[int, int]:
    """(unit, invariant) test counts, split by path prefix."""
    unit = invariant = 0
    for path, contracts in listing.items():
        n = sum(len(tests) for tests in contracts.values())
        if path.startswith(INVARIANT_PREFIX):
            invariant += n
        else:
            unit += n
    return unit, invariant


def misnamed(listing: dict) -> list[str]:
    """Every test whose name matches none of the accepted forms."""
    out = []
    for path, contracts in listing.items():
        for contract, tests in contracts.items():
            for test in tests:
                # Some forge versions list a full signature rather than a name.
                name = test.split("(", 1)[0].strip()
                if not any(p.match(name) for p in _ACCEPTED):
                    out.append(f"{path}:{contract}.{name}")
    return sorted(out)


def main() -> int:
    listing = list_tests()
    unit, invariant = count(listing)
    require_invariant = os.environ.get("WALL_REQUIRE_INVARIANT", "1") != "0"

    print(f"gate_tests: {unit} unit test(s), {invariant} invariant test(s).")

    failed = False

    failures = []
    if unit == 0:
        failures.append(
            "no unit tests found — `forge test` would exit 0 having run nothing"
        )
    if invariant == 0 and require_invariant:
        failures.append(
            f"no invariant tests found under {INVARIANT_PREFIX} "
            "(set WALL_REQUIRE_INVARIANT=0 to stage adoption)"
        )

    if failures:
        print("WALL: refusing to pass an untested tree:")
        for f in failures:
            print(f"  - {f}")
        failed = True

    # Naming is checked independently of presence. An empty category is not a
    # reason to stop looking at the tests that do exist — returning early here
    # would let a misnamed test through unreported for as long as some other
    # category stays empty.
    bad = misnamed(listing)
    if bad:
        print(f"WALL: {len(bad)} test(s) do not follow the naming convention:")
        for b in bad:
            print(f"  - {b}")
        print("Accepted forms (each segment PascalCase):")
        for form in _ACCEPTED_FORMS:
            print(f"  - {form}")
        failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
