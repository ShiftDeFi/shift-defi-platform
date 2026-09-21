---
name: wall-triage
description: Diagnose a red `make verify` lane and choose between fixing the code and proposing a triage entry. Use when slither, aderyn, lint or the test guard fails, or before adding a key to aderyn.triage.
---

# Wall triage

Every finding is one of two things: a claim about the code, or a claim whose
premise does not hold in this code. Establishing which is the whole task. The
default answer is that it is the first, and the code gets fixed.

## Procedure

1. **Reproduce the lane alone** — `make aderyn`, `make slither`, `make lint`,
   `make test`. The full gate stops at the first failure and buries the rest.

2. **Rule out a non-finding.** An aderyn key carries a line number, so inserting
   a line above a reviewed finding renumbers it; the anchor in the key — a digest
   of the source line — is what still identifies the finding. The gate labels
   every un-triaged instance with which of the three cases it is:

   - `(accepted finding, moved)` — the anchor matches an accepted key at another
     line. Nothing was reviewed; `make retriage` settles it.
   - `(accepted key, code at it changed)` — the line is still accepted, but the
     statement on it was edited. The reasoning above the key was written about
     different code, so the finding is read again from step 3 and the comment
     rewritten with it.
   - unlabelled — a finding with no accepted counterpart. Continue.

   `make retriage RETRIAGE_ARGS=--check` draws the same distinction without
   writing: a `re-anchor` line is the first case, and a `stale` line paired with
   a `NEW FINDING` on the same line is the second.
   Pass `--check` bare and make swallows it as an abbreviation of its own
   `--check-symlink-times`, leaving the recipe to re-anchor for real.

   A finding that appears locally but not in CI is usually a version mismatch —
   `make tools` against the pins in `.github/workflows/wall.yml`.

3. **Read what the detector claims, not what it is called.** Aderyn instances
   carry a `hint` naming the specific statements involved; `--print-keys` lists
   keys without them, so read `aderyn.out.json` for the hint. Detector names
   generalise over patterns and mislead on the specific case.

4. **Test the premise.** A detector fires on a pattern and assumes a context.
   Name the concrete fact that makes the assumption false here, or conclude it
   holds. "This is fine because it is owner-only" is not that fact; "the owner
   is immutable and set at construction, so it cannot change hands" is.

5. **Decide.** Premise holds → fix the code. Premise fails → propose an entry,
   with the fact from step 4 as the reasoning. For an instance whose code
   changed, the verdict may well be the one already in the file; the entry is
   still a proposal, because the comment now has to describe the new code.

## Inputs for step 4

Properties of this codebase that findings are commonly wrong about. Each is
worth re-verifying before it is cited — they are true of the code as it stands,
not guarantees.

| Property | How to check it still holds |
|---|---|
| A constructor cannot be re-entered: no deployed code exists yet, and what it writes is `immutable`, living in bytecode rather than storage | the declarations are `immutable`, and the writes are in the constructor |
| The owner cannot change: fixed at construction, no transfer or renounce path | `grep -n 'OWNER' contracts/OwnerImmutable.sol` |
| No ETH reaches this code | no `receive`, `fallback`, `payable` or value-bearing call in `contracts/` |

The accepted `reentrancy-state-change` keys in `aderyn.triage` rest on the
first; its comment is the worked example of what step 4 produces.

## When the premise holds

Two detectors are promoted to gating in `gate_aderyn.py` because this repository
treats them as binding, so a finding from either is a code fix and never an
entry:

- `state-change-without-event` — add the event, carrying the new values, so a
  consumer can reconstruct the change from logs alone.
- `state-no-address-check` — add the zero-check. Validation here is uniform: do
  not judge whether the invalid value would have failed anyway.

## Handing over a proposal

Writing `aderyn.triage` or `slither.db.json` is refused by the `PreToolUse`
guard, because accepting a finding is a human review decision. Provide:

1. The key, verbatim as the gate printed it — all four fields, anchor included.
   `make aderyn` prints the un-triaged ones. A key retyped without its anchor
   still gates, but no longer re-anchors: `make retriage` has nothing to pair
   on, and the next inserted line above it costs another review.
2. What the detector claims, in one sentence.
3. The fact from step 4, grounded in the code.
4. What would bring the entry back under review — the change that would make
   the premise hold again.

The fourth is the one usually skipped, and the reason that file is comments
above keys rather than keys alone.

Slither acknowledgements go through `make triage`, which is interactive and
needs a person at the terminal.
