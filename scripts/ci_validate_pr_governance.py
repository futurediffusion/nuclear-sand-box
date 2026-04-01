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
    return value.lower() not in {"", "-", "n/a", "na", "pendiente", "_pendiente_"}


def get_field_value(label: str) -> str:
    pattern = re.compile(rf"{re.escape(label)}\s*(.+)", re.IGNORECASE)
    match = pattern.search(BODY)
    if not match:
        return ""
    return match.group(1).strip()


required_labels = [
    "Respuesta timer local injustificado:",
    "Respuesta lógica nueva en autoload:",
    "Respuesta duplicación de heurística crítica:",
    "Respuesta decisión duplicada (assault/combat/hostility):",
    "Respuesta debug mutando estado:",
    "Owner de decisión tocada (obligatorio):",
    "Categoría de verdad para datos/campos nuevos:",
    "Justificación explícita si NO se usa Cadence en gameplay:",
    "Registro de excepción temporal (si aplica):",
    "Fecha de retiro obligatoria (YYYY-MM-DD):",
    "Criterio de done Sprint 1 (patrones corregidos no reingresan):",
]

missing = [label for label in required_labels if not has_non_empty_field(label)]
if missing:
    fail("Faltan campos obligatorios o están vacíos: " + ", ".join(missing))

lower = BODY.lower()

blocker_by_violation = {
    "timer_local_injustificado": "respuesta timer local injustificado: sí",
    "logica_nueva_en_autoload": "respuesta lógica nueva en autoload: sí",
    "duplicacion_heuristica_critica": "respuesta duplicación de heurística crítica: sí",
    "decision_duplicada_assault_combat_hostility": "respuesta decisión duplicada (assault/combat/hostility): sí",
    "debug_mutando_estado": "respuesta debug mutando estado: sí",
}

triggered_blockers = [
    violation_type
    for violation_type, needle in blocker_by_violation.items()
    if needle in lower
]

if triggered_blockers:
    if not has_non_empty_field("Registro de excepción temporal (si aplica):"):
        fail(
            "Hay violaciones bloqueantes marcadas en Sí y no se declaró excepción temporal aprobada. "
            f"Tipos detectados: {', '.join(triggered_blockers)}"
        )

if not re.search(r"fecha de retiro obligatoria \(yyyy-mm-dd\):\s*\d{4}-\d{2}-\d{2}", lower):
    fail("Falta fecha de retiro obligatoria válida (YYYY-MM-DD).")

exception_value = get_field_value("Registro de excepción temporal (si aplica):").lower()
if exception_value not in {"", "-", "n/a", "na", "sin excepción"}:
    if not re.search(r"fecha de retiro obligatoria \(yyyy-mm-dd\):\s*\d{4}-\d{2}-\d{2}", lower):
        fail("Existe excepción/fallback temporal sin fecha de retiro obligatoria válida (YYYY-MM-DD).")

truth_category = get_field_value("Categoría de verdad para datos/campos nuevos:").lower()
allowed_truth_categories = {"runtime", "save", "derived", "cache", "no aplica"}
if truth_category not in allowed_truth_categories:
    fail(
        "Categoría de verdad inválida. Usa una única categoría: "
        "runtime | save | derived | cache | no aplica."
    )

if "criterio de done sprint 1 (patrones corregidos no reingresan): no" in lower:
    fail("Merge bloqueado: criterio de done Sprint 1 marcado como No.")

if "respuesta decisión duplicada (assault/combat/hostility): sí" in lower:
    fail("Merge bloqueado: segunda ruta de decisión para assault/combat/hostility declarada en Sí.")

if "respuesta lógica nueva en autoload: sí" in lower:
    fail("Merge bloqueado: se declaró lógica nueva en autoload.")

if "respuesta duplicación de heurística crítica: sí" in lower:
    fail("Merge bloqueado: se declaró duplicación de heurística crítica.")

print(f"[PR-GOVERNANCE][OK] Validación superada para PR: {TITLE}")
