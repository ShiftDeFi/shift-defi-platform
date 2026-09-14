# CLAUDE.md

## Project

`shift-defi-platform` (`@shift-defi/core`) — the vault, container and routing
contracts. Foundry, Solidity 0.8.28, OpenZeppelin 5.x upgradeable.

## The gate

`make verify` is the gate. It is the same gate as
`shift-defi-cow-protocol-adapter`'s, vendored under `wall/`: `wall/wall.mk`
defines the lanes, `wall/script/` holds the gate scripts, and each documents its
own mechanics and blind spots. Every lane also runs standalone (`make storage`,
`make lint`, …), which is the fast way to iterate on one failure. `make help`
lists them.

Four lanes are **staged off** while their backlog is worked, measured
2026-09-14: `lint` (57 forge lint findings, plus 7 upward-traversing imports),
`slither` (77 findings at or above medium), `aderyn` (17 gated instances),
`tests` (150 tests off the naming grammar, no invariant tree). A staged lane
runs and reports but does not fail. Flip its `WALL_REQUIRE_*` in `wall/wall.mk`
once its backlog is cleared or triaged — one lane at a time, so each becomes
real deliberately rather than by accident.

Suppress a lint rule in `foundry.toml` under `[lint]` — `exclude_lints` or
`mixed_case_exceptions` — after review, rather than in a triage file.

**Adding a triage entry is a human review decision. Propose entries with
reasoning; do not add them unilaterally** — the hooks refuse the write in any
case.

## Live proxies

`ContainerLocal`, `ContainerPrincipal` and `ContainerAgent` sit behind
transparent proxies. Sequential storage is append-only: a new variable goes at
the tail of the contract that declares it, or into ERC-7201 namespaced storage.
Never insert into a shared base — every derived contract's own variables follow
`Container`'s, so one insertion shifts all of them.

The `storage` lane diffs the layout against `wall/baseline/storage.json` and
fails on anything but an append. It cannot see namespaced storage, which is the
point — that storage occupies no sequential slot. It also cannot verify a
namespace constant; derive those in a test.

## Code size

`ContainerAgent` has **75 bytes** of runtime headroom under `--via-ir`. Anything
added to `Container`, `CrossChainContainer` or `StrategyContainer` reaches it and
risks its deployment. Code shared by fewer than all three containers belongs in a
mixin those containers inherit, not in a common base.

The `sizes` lane is the fast regression check and pins `ContainerAgent`
byte-for-byte in both directions. Absolute margins only mean something under
`--via-ir` — `make sizes-deploy`, about four and a half minutes. Note that
inheritance is flattened at compile time, so a mixin costs each deriving
contract exactly what duplicating the code would; it is a source-organisation
choice, not a size one.

## Agent hooks

`.claude/settings.json` wires the gate into Claude Code sessions, so Solidity is
checked as it is written rather than only at commit time. The gate's own files
cannot be written, whatever route the write takes — propose the change instead;
reading them is always allowed. A turn cannot end on a red gate, nor on a gate
file this turn changed. `wall/baseline/*.json` is protected for the same reason
a triage file is: rewriting a baseline is how the storage or size lane is made
green without fixing anything.

`wall/script/test_hooks.py` (`make test-hooks`) exercises them; nothing else
does, and a regression in them is silent.

`WALL_GUARD=0` in the session environment lifts the guard, and is how to work on
the gate itself; leave it unset otherwise. Changes under `.claude/` and `wall/`
are executable configuration and warrant the same review as `contracts/`.

## Shell output

Shell output is the largest consumer of an agent's context window, and read-only
exploration is half of it.

Delegate to a subagent when exploring will take five or more read-only commands,
or when a single command dumps more than ten thousand characters, and only the
answer is needed rather than the source itself. Never delegate reading a file
that is about to be edited — an edit needs the exact text, and a subagent returns
excerpts and conclusions.

Cap output everywhere else. Pipe through `head`, count with `wc -l` before
printing a file, and use `grep -c` before `grep -n`.

## Conventions

Formatting is prettier with `prettier-plugin-solidity` — 120 columns, 4-space,
no bracket spacing, pinned in `.prettierrc`. The gate owns it: the `fmt` lane
checks it, the post-edit hook applies it, and the command is named once in
`.claude/hooks/wall_config.py`. Nothing else formats Solidity — `lint-staged` no
longer does, and `.vscode/settings.json` turns off format-on-save for `.sol`,
because an editor extension bundles its own prettier and a version skew silently
produces a file the gate then rejects.

`forge fmt` is deliberately not used here, unlike in the adapter. The two
formatters disagree structurally — prettier breaks arguments one per line where
forge packs them — and switching would reformat 86 of 148 Solidity files. This
code is audited; a formatting-only rewrite of that size would need the diff
audited again. Revisit if that ever stops being true.

NatSpec lives in the interface as `/** */` blocks with named parameters;
implementations carry `/// @inheritdoc <Interface>`. Shared errors go in
`libraries/Errors.sol`, contract-specific ones in that contract's interface, and
both are raised as `require(cond, Errors.X())`. Upgradeable contracts end with
`uint256[50] private __gap`. A function needing more than a few memory locals
groups them into a `<FunctionName>LocalVars` struct declared in its interface.

Where any of this disagrees with the file being edited, match the file.

## Commits

commitlint enforces conventional commits — types
`feat|fix|docs|chore|style|refactor|test|wip`, header and body lines at most 72
characters, body required. `pre-commit` runs `make verify` when a commit touches
Solidity.

Never add a `Co-Authored-By` trailer, and never attribute a commit to the tooling
used to write it.

## CoW Protocol integration

`docs/cow-integration.md` carries the design — where the adapter attaches, the
gate points on each container's state machine, and the decisions behind them.
