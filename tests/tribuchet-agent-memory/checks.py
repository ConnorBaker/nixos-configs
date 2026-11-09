# The agent-memory tests' verdicts (node.nix): every
# check is printed as it is judged (PREFIX-CHECK ok or FAILED, its name and
# its evidence), and finish() then fails the test on each that failed, so
# that one run shows every difference.
import json
from collections.abc import Callable
from typing import Any

CHECKS: dict[str, bool] = {}


def q(m: Any, c: str) -> str:
    return m.execute(c)[1].strip()


def checker(prefix: str) -> Callable[[str, Any, Any], None]:
    def check(name: str, ok: Any, detail: Any) -> None:
        CHECKS[name] = bool(ok)
        verdict = "ok" if ok else "FAILED"
        evidence = json.dumps(detail, default=str)[:3000]
        print(f"{prefix}-CHECK {verdict}: {name} {evidence}")

    return check


def finish() -> None:
    failed = [k for k, v in CHECKS.items() if not v]
    assert not failed, f"failed: {failed}"
