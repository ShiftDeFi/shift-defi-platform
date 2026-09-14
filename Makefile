include wall/wall.mk

.PHONY: install tools test-hooks coverage coverage-lcov

# Coverage builds with the optimizer disabled, which overflows the stack on
# forge-std's cheatcode interface; --ir-minimum enables viaIR with minimal
# optimization, which compiles. Branch percentages are unreliable under viaIR —
# read lines, statements and functions.
COVERAGE_ARGS := --ir-minimum --no-match-coverage '^(test|script)/'

## install : fetch pinned submodule dependencies and the npm toolchain.
##           `npm ci` runs husky's prepare script, which installs the git hooks.
install:
	git submodule update --init --recursive
	npm ci

## test-hooks : exercise the agent hooks in .claude/hooks/. They decide what an
##              agent may write, so a regression in them is silent — the gate
##              keeps reporting green while it stops being enforced — and no
##              other lane reads them.
##
##              Outside `make verify` on purpose: the Stop hook runs verify on
##              every turn that touches Solidity, and this adds a couple of
##              seconds that say nothing about the contracts.
test-hooks:
	python3 wall/script/test_hooks.py

## coverage : coverage for contracts/ as a table, with the test and script trees
##            left out of the report. Outside the gate.
coverage:
	forge coverage $(COVERAGE_ARGS)

## coverage-lcov : the same run, written to lcov.info for editor gutters and
##                 external coverage tooling.
coverage-lcov:
	forge coverage $(COVERAGE_ARGS) --report lcov

## tools : report the local toolchain.
tools:
	@forge --version
	@printf 'slither '; slither --version
	@aderyn --version
	@python3 --version
	@printf 'node    '; node --version
