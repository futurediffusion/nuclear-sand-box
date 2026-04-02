#!/usr/bin/env python3
from __future__ import annotations

from datetime import date, datetime
from pathlib import Path
import re
import sys

WORLD_FILE = Path("scripts/world/world.gd")
RESET_EXCEPTIONS_FILE = Path("docs/world-gd-reset-exceptions.md")
BUSINESS_RULE_EXCEPTIONS_FILE = Path("docs/world-gd-business-rule-exceptions.md")


def _load_line_exceptions(file_path: Path) -> dict[int, tuple[str, date]]:
    exceptions: dict[int, tuple[str, date]] = {}
    if not file_path.exists():
        return exceptions

    for line in file_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("scripts/world/world.gd:"):
            continue

        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 3:
            continue

        line_ref, justification, retirement_date_raw = parts
        _, line_number_str = line_ref.split(":", maxsplit=1)
        if not line_number_str.isdigit() or not justification:
            continue

        try:
            retirement_date = datetime.strptime(retirement_date_raw, "%Y-%m-%d").date()
        except ValueError:
            continue

        exceptions[int(line_number_str)] = (justification, retirement_date)

    return exceptions


def _load_pattern_exceptions(file_path: Path) -> dict[str, tuple[str, date]]:
    exceptions: dict[str, tuple[str, date]] = {}
    if not file_path.exists():
        return exceptions

    for line in file_path.read_text(encoding="utf-8").splitlines():
        if not line.startswith("PATTERN:"):
            continue

        parts = [part.strip() for part in line.split("|")]
        if len(parts) != 4:
            continue

        marker, pattern_id, justification, retirement_date_raw = parts
        if marker != "PATTERN:" or not pattern_id or not justification:
            continue

        try:
            retirement_date = datetime.strptime(retirement_date_raw, "%Y-%m-%d").date()
        except ValueError:
            continue

        exceptions[pattern_id] = (justification, retirement_date)

    return exceptions


def _check_expired_exceptions(exceptions: dict, label: str) -> list[str]:
    today = date.today()
    expired = []
    for key, (_, retirement_date) in exceptions.items():
        if retirement_date < today:
            expired.append(f" - {label} {key} expired on {retirement_date.isoformat()}")
    return expired


def main() -> int:
    if not WORLD_FILE.exists():
        print(f"World boundary guard failed. Missing file: {WORLD_FILE}")
        return 1

    text = WORLD_FILE.read_text(encoding="utf-8")
    lines = text.splitlines()

    business_rule_patterns = {
        "social_sanction_constants": r"\bLocalCivilAuthorityConstants\b",
        "incident_factory_usage": r"\bLocalCivilIncidentFactory\.create\s*\(",
        "defense_posture_compute": r"\bTavernDefensePosture\.compute\s*\(",
        "direct_sanction_decision": r"\bsanction\s*=",
        "offense_classification": r"\boffen[sc]e\b",
        "targeting_heuristic_scoring": r"\b(target|raid)_score\b",
    }

    pattern_exceptions = _load_pattern_exceptions(BUSINESS_RULE_EXCEPTIONS_FILE)
    reset_line_exceptions = _load_line_exceptions(RESET_EXCEPTIONS_FILE)

    expired_entries = []
    expired_entries.extend(_check_expired_exceptions(pattern_exceptions, "pattern exception"))
    expired_entries.extend(_check_expired_exceptions(reset_line_exceptions, "reset exception line"))
    if expired_entries:
        print("World boundary guard failed. Found expired temporary exceptions:")
        print("\n".join(expired_entries))
        return 1

    pattern_violations = []
    for pattern_id, pattern in business_rule_patterns.items():
        if pattern_id in pattern_exceptions:
            continue
        if re.search(pattern, text):
            pattern_violations.append((pattern_id, pattern))

    if pattern_violations:
        print("World boundary guard failed. Forbidden business-rule markers in scripts/world/world.gd:")
        for pattern_id, pattern in pattern_violations:
            print(f" - {pattern_id}: /{pattern}/")
        print("To approve a temporary pattern exception add:")
        print("  PATTERN:|<pattern_id>|<justification>|<YYYY-MM-DD>")
        print(f"in {BUSINESS_RULE_EXCEPTIONS_FILE}")
        return 1

    reset_allowlist_markers = [
        "orchestration_ports.reset(",
    ]
    reset_pattern = re.compile(r"(?P<expr>[A-Za-z_][A-Za-z0-9_\.]*)\.reset\s*\(")

    reset_violations = []
    for index, line in enumerate(lines, start=1):
        if ".reset" not in line:
            continue
        if any(marker in line for marker in reset_allowlist_markers):
            continue
        if not reset_pattern.search(line):
            continue
        if index in reset_line_exceptions:
            continue
        reset_violations.append((index, line.strip()))

    if reset_violations:
        print("World boundary guard failed. Direct *.reset() call forbidden in scripts/world/world.gd.")
        print("Allowed only through explicit orchestration ports or approved temporary exceptions.")
        print("To approve temporary reset exceptions add:")
        print("  scripts/world/world.gd:<line>|<justification>|<YYYY-MM-DD>")
        print(f"in {RESET_EXCEPTIONS_FILE}")
        for line_number, code_line in reset_violations:
            print(f" - L{line_number}: {code_line}")
        return 1

    print("World boundary guard passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
