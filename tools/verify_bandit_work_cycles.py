#!/usr/bin/env python3
import argparse
import re
from collections import defaultdict

EVENT_PREFIX = "[BANDIT_WORKER_EVENT]"
KV_RE = re.compile(r"(\w+)=([^=]+?)(?=\s\w+=|$)")

# Detect -> mine -> pickup -> return -> deposit -> resume
STAGE_EVENTS = [
    ("detect", {"resource_acquired", "drop_detected"}),
    ("mine", {"resource_hit"}),
    ("pickup", {"drop_pickup_success"}),
    ("return", {"return_home_triggered"}),
    ("deposit", {"deposit_success", "deposit_closed", "deposit_closed_ack"}),
    ("resume", {"work_cycle_resumed"}),
]


def parse_event(line: str):
    if EVENT_PREFIX not in line:
        return None
    payload = line.split(EVENT_PREFIX, 1)[1].strip()
    kv = dict((k.strip(), v.strip()) for k, v in KV_RE.findall(payload))
    event_name = kv.get("event", "")
    npc_id = kv.get("npc_id", "")
    cycle_id = kv.get("work_cycle_id", "")
    if not event_name or not npc_id or not cycle_id:
        return None
    return {"event": event_name, "npc_id": npc_id, "cycle_id": cycle_id, "raw": payload}


def score_cycle(events):
    idx = 0
    matched = []
    for evt in events:
        if idx >= len(STAGE_EVENTS):
            break
        stage_name, allowed = STAGE_EVENTS[idx]
        if evt in allowed:
            matched.append(stage_name)
            idx += 1
    return idx == len(STAGE_EVENTS), matched


def main():
    ap = argparse.ArgumentParser(description="Verifica ciclos completos de workers bandidos desde logs bandit_pipeline.")
    ap.add_argument("logfile", help="Ruta del archivo de log")
    ap.add_argument("--min-npcs", type=int, default=2, help="NPCs mínimos con ciclos completos")
    ap.add_argument("--min-cycles-per-npc", type=int, default=2, help="Ciclos completos mínimos por NPC")
    args = ap.parse_args()

    per_npc_cycle_events = defaultdict(list)
    with open(args.logfile, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parsed = parse_event(line)
            if parsed is None:
                continue
            key = (parsed["npc_id"], parsed["cycle_id"])
            per_npc_cycle_events[key].append(parsed["event"])

    complete_by_npc = defaultdict(int)
    incomplete = []
    for (npc_id, cycle_id), events in sorted(per_npc_cycle_events.items()):
        ok, matched = score_cycle(events)
        if ok:
            complete_by_npc[npc_id] += 1
        else:
            incomplete.append((npc_id, cycle_id, matched, events))

    print("=== Bandit worker cycle verification ===")
    print(f"NPCs con al menos un ciclo: {len(set(n for n, _ in per_npc_cycle_events.keys()))}")
    print("Ciclos completos por NPC:")
    for npc_id in sorted(complete_by_npc):
        print(f"  - {npc_id}: {complete_by_npc[npc_id]}")

    qualifying_npcs = [npc for npc, count in complete_by_npc.items() if count >= args.min_cycles_per_npc]
    if len(qualifying_npcs) < args.min_npcs:
        print("\n[FAIL] Evidencia insuficiente para criterio de done de fase.")
        print(f"Requerido: >= {args.min_npcs} NPCs con >= {args.min_cycles_per_npc} ciclos completos cada uno.")
        print(f"Actual: {len(qualifying_npcs)} NPCs califican.")
        if incomplete:
            print("\nMuestras de ciclos incompletos:")
            for npc_id, cycle_id, matched, events in incomplete[:10]:
                print(f"  - npc={npc_id} cycle={cycle_id} matched={matched} events={events}")
        raise SystemExit(1)

    print("\n[PASS] Criterio cumplido: múltiples NPCs con múltiples ciclos completos.")


if __name__ == "__main__":
    main()
