#!/usr/bin/env python3
import os
import re
import sys
from datetime import date, datetime

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
    "Respuesta lógica global oculta:",
    "Respuesta duplicación de heurística crítica:",
    "Respuesta decisión duplicada (assault/combat/hostility):",
    "Respuesta debug mutando estado:",
    "Respuesta telemetry/debug fuera de canal controlado mutando estado:",
    "Respuesta cambio de estado nuevo en el PR:",
    "Owner de decisión tocada (obligatorio):",
    "Categoría de verdad para datos/campos nuevos:",
    "Owner de escritura para cambio de estado nuevo:",
    "Categoría de verdad del cambio de estado nuevo:",
    "Justificación explícita si NO se usa Cadence en gameplay:",
    "Registro de excepción temporal (si aplica):",
    "Fecha de retiro obligatoria (YYYY-MM-DD):",
    "Criterio de done Sprint 1 (patrones corregidos no reingresan):",
    "Criterio de done anti-reversión (no volver al estado anterior por flujo normal de PR):",
]

missing = [label for label in required_labels if not has_non_empty_field(label)]
if missing:
    fail("Faltan campos obligatorios o están vacíos: " + ", ".join(missing))

lower = BODY.lower()

blocker_by_violation = {
    "timer_local_injustificado": "respuesta timer local injustificado: sí",
    "logica_nueva_en_autoload": "respuesta lógica nueva en autoload: sí",
    "logica_global_oculta": "respuesta lógica global oculta: sí",
    "duplicacion_heuristica_critica": "respuesta duplicación de heurística crítica: sí",
    "decision_duplicada_assault_combat_hostility": "respuesta decisión duplicada (assault/combat/hostility): sí",
    "debug_mutando_estado": "respuesta debug mutando estado: sí",
    "telemetry_debug_fuera_de_canal_controlado": "respuesta telemetry/debug fuera de canal controlado mutando estado: sí",
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
retirement_raw = get_field_value("Fecha de retiro obligatoria (YYYY-MM-DD):")
try:
    retirement_date = datetime.strptime(retirement_raw, "%Y-%m-%d").date()
except ValueError:
    fail("La fecha de retiro obligatoria debe usar formato YYYY-MM-DD.")

if exception_value not in {"", "-", "n/a", "na", "sin excepción"}:
    if retirement_date <= date.today():
        fail("La fecha de retiro obligatoria debe ser futura para excepciones/fallbacks temporales.")
    if (retirement_date - date.today()).days > 180:
        fail("La fecha de retiro obligatoria de excepciones/fallbacks no puede superar 180 días.")

truth_category = get_field_value("Categoría de verdad para datos/campos nuevos:").lower()
allowed_truth_categories = {"runtime", "save", "derived", "cache", "no aplica"}
if truth_category not in allowed_truth_categories:
    fail(
        "Categoría de verdad inválida. Usa una única categoría: "
        "runtime | save | derived | cache | no aplica."
    )

state_change_answer = get_field_value("Respuesta cambio de estado nuevo en el PR:").lower()
if state_change_answer not in {"sí", "si", "no"}:
    fail("Respuesta cambio de estado nuevo en el PR debe ser Sí o No.")

state_owner = get_field_value("Owner de escritura para cambio de estado nuevo:").lower()
state_truth_category = get_field_value("Categoría de verdad del cambio de estado nuevo:").lower()
if state_change_answer in {"sí", "si"}:
    if state_owner in {"", "-", "n/a", "na", "no aplica"}:
        fail("Todo cambio de estado nuevo debe declarar owner de escritura explícito.")
    if state_truth_category not in {"runtime", "save", "derived", "cache"}:
        fail("Todo cambio de estado nuevo debe declarar categoría de verdad única: runtime | save | derived | cache.")
else:
    if state_truth_category not in allowed_truth_categories:
        fail("Categoría de verdad del cambio de estado nuevo inválida.")

if "criterio de done sprint 1 (patrones corregidos no reingresan): no" in lower:
    fail("Merge bloqueado: criterio de done Sprint 1 marcado como No.")

if "criterio de done anti-reversión (no volver al estado anterior por flujo normal de pr): no" in lower:
    fail("Merge bloqueado: criterio de done anti-reversión marcado como No.")

if "respuesta decisión duplicada (assault/combat/hostility): sí" in lower:
    fail("Merge bloqueado: segunda ruta de decisión para assault/combat/hostility declarada en Sí.")

if "respuesta lógica nueva en autoload: sí" in lower:
    fail("Merge bloqueado: se declaró lógica nueva en autoload.")

if "respuesta lógica global oculta: sí" in lower:
    fail("Merge bloqueado: se declaró lógica global oculta.")

if "respuesta duplicación de heurística crítica: sí" in lower:
    fail("Merge bloqueado: se declaró duplicación de heurística crítica.")

if "respuesta telemetry/debug fuera de canal controlado mutando estado: sí" in lower:
    fail("Merge bloqueado: se declaró mutación real desde debug/telemetry fuera de canal controlado.")

print(f"[PR-GOVERNANCE][OK] Validación superada para PR: {TITLE}")
