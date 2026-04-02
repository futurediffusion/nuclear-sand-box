#!/usr/bin/env python3
from pathlib import Path
import re
import sys

world = Path('scripts/world/world.gd')
text = world.read_text(encoding='utf-8')

forbidden_markers = [
    'LocalCivilAuthorityConstants',
    'LocalCivilIncidentFactory.create(',
    'TavernDefensePosture.compute(',
]

violations = [m for m in forbidden_markers if m in text]
if violations:
    print('World boundary guard failed. Forbidden decision markers in scripts/world/world.gd:')
    for v in violations:
        print(f' - {v}')
    sys.exit(1)

reset_allowlist_markers = [
    'orchestration_ports.reset(',
]

reset_pattern = re.compile(r'(?P<expr>[A-Za-z_][A-Za-z0-9_\.]*)\.reset\s*\(')
approved_exceptions_file = Path('docs/world-gd-reset-exceptions.md')
approved_exceptions = {}

if approved_exceptions_file.exists():
    for line in approved_exceptions_file.read_text(encoding='utf-8').splitlines():
        # Format: scripts/world/world.gd:<line>|justification|YYYY-MM-DD
        if not line.startswith('scripts/world/world.gd:'):
            continue
        parts = [part.strip() for part in line.split('|')]
        if len(parts) != 3:
            continue
        line_ref, justification, retirement_date = parts
        _, line_number_str = line_ref.split(':', maxsplit=1)
        if not line_number_str.isdigit():
            continue
        if not justification:
            continue
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', retirement_date):
            continue
        approved_exceptions[int(line_number_str)] = (justification, retirement_date)

reset_violations = []
for index, line in enumerate(text.splitlines(), start=1):
    if '.reset' not in line:
        continue
    if any(marker in line for marker in reset_allowlist_markers):
        continue
    if not reset_pattern.search(line):
        continue
    if index in approved_exceptions:
        continue
    reset_violations.append((index, line.strip()))

if reset_violations:
    print('World boundary guard failed. Direct *.reset() call forbidden in scripts/world/world.gd.')
    print('Allowed only through explicit orchestration ports or approved exceptions.')
    print('To approve temporary exceptions add:')
    print('  scripts/world/world.gd:<line>|<justification>|<YYYY-MM-DD>')
    print('in docs/world-gd-reset-exceptions.md')
    for line_number, code_line in reset_violations:
        print(f' - L{line_number}: {code_line}')
    sys.exit(1)

print('World boundary guard passed.')
