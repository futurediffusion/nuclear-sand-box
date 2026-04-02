#!/usr/bin/env python3
from pathlib import Path
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

print('World boundary guard passed.')
