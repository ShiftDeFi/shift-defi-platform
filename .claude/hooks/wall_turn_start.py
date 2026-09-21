#!/usr/bin/env python3
"""UserPromptSubmit hook: record the gate's state at the start of the turn.

wall_stop.py compares against this record, so what it reports is what changed
during the turn rather than what was already uncommitted when the session
began. Without the baseline, a branch carrying in-progress gate work — the
normal state while the gate itself is being changed — would fail every turn.

Writes nothing to stdout: a UserPromptSubmit hook's output is added to the
model's context, and this has nothing to say when it succeeds.
"""

import json
import sys

from wall_protected import STATE, snapshot


def main() -> int:
    try:
        STATE.write_text(json.dumps(snapshot()))
    except OSError:
        # No baseline means wall_stop.py establishes one and lets the turn
        # pass. Failing the turn over a state file would be worse.
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
