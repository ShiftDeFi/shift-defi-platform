# ============================================================================
#  wall.mk — the deterministic verification gate.
#
#  `make verify` runs every lane, and is the same target CI would run, so a
#  green pipeline and a green local run mean the same thing.
#
#  Recipes run from the repo root. References to files shipped alongside this
#  fragment are anchored to $(WALL_DIR); generated reports and triage files stay
#  relative to the repo root.
#
#  This is the same gate as shift-defi-cow-protocol-adapter's, with three
#  differences that come from the repository rather than from any one piece of
#  work: sources are under contracts/, formatting is prettier rather than
#  `forge fmt`, and two lanes check upgrade safety because these contracts sit
#  behind live proxies.
# ============================================================================

WALL_MK  := $(lastword $(MAKEFILE_LIST))
WALL_DIR := $(dir $(WALL_MK))

.DEFAULT_GOAL := verify

SRC_DIR       ?= contracts
INVARIANT_DIR ?= test/invariant
FORK_DIR      ?= test/fork

# Every lane compiles under one profile. A deploy profile pins Common and Codec
# to deployed addresses, which changes what is built and what the size baselines
# record. Exported, because foundry loads .env without overwriting a variable
# already in the environment; `?=`, so an explicit override on the command line
# or in the shell still wins.
export FOUNDRY_PROFILE ?= default

# ---------------------------------------------------------------------------
#  Staging
#
#  This repository predates the gate, so several lanes have a standing backlog
#  and cannot block a commit yet. A staged lane runs and reports; it does not
#  fail. The counts below are the backlog measured on 2026-09-14 — they are a
#  record of what enforcing the lane currently costs, not a threshold.
#
#  Flip a variable to 1 once its backlog is cleared or triaged. Doing that per
#  lane is the point: each becomes real on its own, and none of them is
#  enforced by accident.
# ---------------------------------------------------------------------------
WALL_REQUIRE_LINT      ?= 0
WALL_REQUIRE_SLITHER   ?= 0
WALL_REQUIRE_ADERYN    ?= 0
WALL_REQUIRE_TESTS     ?= 0
WALL_REQUIRE_INVARIANT ?= 0

# `|| $(call staged,NAME)` — a staged lane reports its failure and passes.
staged = if [ "$(WALL_REQUIRE_$(1))" = "1" ]; then exit 1; fi; \
         echo "WALL: the $(1) lane is staged off — set WALL_REQUIRE_$(1)=1 to enforce it."

# --fail-medium => non-zero exit on any finding >= medium severity. Findings
# acknowledged into slither.db.json (via `make triage`) are suppressed.
SLITHER_ARGS := --config-file $(WALL_DIR)slither.config.json --fail-medium

.PHONY: verify fmt build storage sizes sizes-deploy lint test slither aderyn \
        invariant triage retriage help clean

## verify : the full gate. Prerequisites run left-to-right, cheapest first.
verify: fmt build storage sizes lint test slither aderyn invariant
	@echo ""
	@echo "  WALL PASSED — this change is mergeable."

## fmt : formatting is part of the gate. prettier-plugin-solidity, not
##       `forge fmt` — the settings are pinned in .prettierrc and lint-staged
##       applies the same formatter on commit.
fmt:
	npx prettier --check --plugin=prettier-plugin-solidity '$(SRC_DIR)/**/*.sol'

## build : contracts must compile. Deliberately without --sizes: that flag
##         makes forge exit non-zero when any contract is over EIP-170, which
##         ContainerAgent is in this profile — it only fits under --via-ir. The
##         `sizes` lane owns that judgement and knows the difference.
build:
	forge build

## storage : sequential storage layout must stay append-only. These contracts
##           are behind transparent proxies, so a moved slot corrupts deployed
##           state on upgrade. ERC-7201 namespaced storage is invisible here by
##           design — it occupies no sequential slot.
storage:
	python3 $(WALL_DIR)script/check_storage.py

## sizes : deployed bytecode must not regress. Fast profile; ContainerAgent is
##         pinned byte-for-byte because it has ~75 bytes of headroom under
##         --via-ir and any change reaching it risks its deployment.
sizes:
	python3 $(WALL_DIR)script/check_sizes.py

## sizes-deploy : the same check under --via-ir, which is how the containers are
##                compiled for deployment and the only profile whose absolute
##                margins are real. Minutes, not seconds — outside `verify`.
sizes-deploy:
	python3 $(WALL_DIR)script/check_sizes.py --via-ir

## lint : naming and style rules that the formatter does not cover.
##        `forge lint` reports findings but exits 0, so the gate script is what
##        turns them into a failure. Suppress via [lint] in foundry.toml.
##        The import check is a text scan and covers contracts/, test/ and
##        script/.
lint:
	@python3 $(WALL_DIR)script/gate_lint.py $(SRC_DIR) || { $(call staged,LINT); }
	@if grep -rn --include='*.sol' --exclude-dir=lib --exclude-dir=out \
	    --exclude-dir=cache -E '(import|from)[^;]*"\.\./' . >/dev/null; then \
	  echo "WALL: imports must not traverse upwards with '../'."; \
	  echo "      Foundry resolves from the project root — write \"contracts/Foo.sol\"."; \
	  $(call staged,LINT); \
	fi

## test : unit tests only. Invariant and fuzz runs are split out below.
##        `forge test` exits 0 when it finds no tests, so the guard runs first
##        and rejects a tree that has contracts but no coverage. The same guard
##        checks test naming, which no Foundry tool covers.
##
##        Fork tests are excluded too: they need an RPC URL and a network round
##        trip, which would make the gate neither hermetic nor offline.
test:
	@python3 $(WALL_DIR)script/gate_tests.py || { $(call staged,TESTS); }
	forge test --no-match-path "{$(INVARIANT_DIR),$(FORK_DIR)}/*"

## slither : static analysis. Writes a structured report and exits non-zero on
##           any finding at or above the threshold.
slither:
	@# Slither will not overwrite an existing --json file: it logs "the overwrite
	@# is prevented" at INFO level and exits 0, leaving a stale report next to a
	@# freshly-failing tree. The exit code stays correct, but anything reading the
	@# JSON would see the previous run. Clear it first.
	rm -f slither.out.json
	@slither . $(SLITHER_ARGS) --json slither.out.json || { \
	  echo "WALL: slither failed — a finding at medium severity or above, or"; \
	  echo "      the compilation above. For a finding: fix the code, or"; \
	  echo "      acknowledge it with \`make triage\` after review. The"; \
	  echo "      wall-triage skill covers deciding between the two."; \
	  $(call staged,SLITHER); \
	}

## aderyn : second static analysis engine, for uncorrelated blind spots.
##          Structured report plus a per-finding triage gate on high severity,
##          and on the low-severity detectors promoted in gate_aderyn.py.
aderyn:
	aderyn . --src $(SRC_DIR) --output aderyn.out.json
	@python3 $(WALL_DIR)script/gate_aderyn.py aderyn.out.json || { $(call staged,ADERYN); }

## invariant : property, invariant and fuzz tests. Slowest, so it runs last.
invariant:
	@if [ -d "$(INVARIANT_DIR)" ]; then \
	  forge test --match-path "$(INVARIANT_DIR)/*"; \
	else \
	  echo "WALL: no $(INVARIANT_DIR)/ tree."; \
	  $(call staged,INVARIANT); \
	fi

## triage : interactively acknowledge a Slither finding into slither.db.json.
##          Requires human review; aderyn's equivalent is editing aderyn.triage.
triage:
	slither . --config-file $(WALL_DIR)slither.config.json --triage-mode

## retriage : re-anchor accepted aderyn keys whose finding only moved. A key
##            is keyed by line, so inserting a line above a reviewed finding
##            renumbers it; this pairs the stale key with the current finding
##            carrying the same anchor — the digest of the source line recorded
##            in the key itself, which holds across a chain of uncommitted
##            edits. It never accepts a new finding and never removes a key —
##            both stay human decisions. To report without writing, run
##            `make retriage RETRIAGE_ARGS=--check`; a bare --check on the make
##            command line is swallowed as an abbreviation of make's own
##            --check-symlink-times and never reaches the script.
retriage:
	aderyn . --src $(SRC_DIR) --output aderyn.out.json
	python3 $(WALL_DIR)script/retriage_aderyn.py aderyn.out.json $(RETRIAGE_ARGS)

## help : list available targets.
help:
	@grep -hE '^##' $(MAKEFILE_LIST) | sed -E 's/^## ?//'

clean:
	forge clean
	rm -f slither.out.json aderyn.out.json lcov.info
