#!/usr/bin/env python3
"""Per-repository configuration for the wall hooks.

Everything the hooks do is the same in every repository that carries this gate;
what differs is where the gate's files live, what formats Solidity, and which
foundry.toml settings are thresholds rather than preferences. Keeping those
three things here lets the hook scripts themselves stay identical across repos,
so the gate can be synced by copying them.

Nothing in this file is specific to any one piece of work. It describes the
repository, not the change being made in it.
"""

# Reviewed state, gate definitions, and the hooks and CI that run them. Any
# write to these is refused, and any change to them is reported at the end of
# the turn.
#
# The baselines are included deliberately: rewriting one is exactly how the
# storage or size lane is made green without fixing anything.
PROTECTED_PATHS = (
    "aderyn.triage",
    "slither.db.json",
    "wall/slither.config.json",
    "wall/wall.mk",
    "wall/script/*.py",
    "wall/baseline/*.json",
    "Makefile",
    ".claude/hooks/*.py",
    ".husky/*",
    ".github/workflows/*",
)

# Settings inside foundry.toml that decide what the gate rejects, as opposed to
# how it builds. Editing fuzz runs is ordinary work; relaxing exclude_lints is
# not.
PROTECTED_SETTINGS = (
    "exclude_lints",
    "mixed_case_exceptions",
    "lint_on_build",
    "deny_warnings",
    "fail_on_revert",
    "solc",
    "auto_detect_remappings",
)

# How a single Solidity file is formatted after an edit. prettier here rather
# than `forge fmt`: the settings are pinned in .prettierrc and lint-staged
# applies the same formatter on commit, so the two must not disagree.
FMT_CMD = ("npx", "prettier", "--write", "--log-level", "warn", "--plugin=prettier-plugin-solidity")

# The binary whose absence means the toolchain is not installed, in which case
# the compile and gate hooks step aside rather than blocking every turn.
REQUIRED_TOOL = "forge"

# Everything `make verify` shells out to. If any is missing the Stop hook steps
# aside with a notice rather than failing every turn on an uninstalled binary;
# CI is what enforces the gate in that case.
VERIFY_TOOLS = ("forge", "slither", "aderyn", "make", "python3", "npx")
