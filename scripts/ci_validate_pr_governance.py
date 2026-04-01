#!/usr/bin/env python3
import os
import re
import sys

BODY = os.environ.get("PR_BODY", "")
TITLE = os.environ.get("PR_TITLE", "")


def fail(msg: str) -> None:
    print(f"[PR-GOVERNANCE][ERROR] {msg}")
    sys.exit(1)


def has_non_empty_field(label: str) -> bool:
    pattern = re.compile(rf"{re.escape(label)}\s*(.+)", re.IGNORECASE)
    match = pattern.search(BODY)
    if not match:
        return False
    value = match.group(1).strip()
    return value not in {"", "-", "n/a", "na", "pendiente", "_pendiente_"}


required_labels = [
    "Respuesta timer local injustificado:",
    "Respuesta decisión duplicada (assault/combat/hostility):",
    "Respuesta debug mutando estado:",
    "Justificación explícita si NO se usa Cadence en gameplay:",
    "Registro de excepción temporal (si aplica):",
    "Fecha de retiro obligatoria (YYYY-MM-DD):",
    "Criterio de done (sin nueva deuda del mismo tipo):",
]

missing = [label for label in required_labels if not has_non_empty_field(label)]
if missing:
    fail("Faltan campos obligatorios o están vacíos: " + ", ".join(missing))

lower = BODY.lower()
blockers = [
    "respuesta timer local injustificado: sí",
    "respuesta decisión duplicada (assault/combat/hostility): sí",
    "respuesta debug mutando estado: sí",
]

if any(item in lower for item in blockers):
    if "registro de excepción temporal (si aplica):" not in lower:
        fail("Hay bloqueos marcados en Sí y no se declaró excepción temporal.")
    if not re.search(r"fecha de retiro obligatoria \(yyyy-mm-dd\):\s*\d{4}-\d{2}-\d{2}", lower):
        fail("Hay bloqueos en Sí sin fecha de retiro obligatoria válida (YYYY-MM-DD).")

if "respuesta decisión duplicada (assault/combat/hostility): sí" in lower:
    fail("Merge bloqueado: segunda ruta de decisión para assault/combat/hostility declarada en Sí.")

if "criterio de done (sin nueva deuda del mismo tipo): no" in lower:
    fail("Merge bloqueado: criterio de done marcado como No.")

print(f"[PR-GOVERNANCE][OK] Validación superada para PR: {TITLE}")
