#!/usr/bin/env python3
import argparse
import re
from collections import defaultdict

WORKER_EVENT_PREFIX = "[BANDIT_WORKER_EVENT]"
KV_RE = re.compile(r"(\w+)=([^=]+?)(?=\s\w+=|$)")
PERF_RE = re.compile(
    r"fps=(?P<fps>[0-9]+(?:\.[0-9]+)?)"
    r".*?drops count=(?P<item_drop_count>\d+)"
    r"\s+merged=(?P<merged_drop_events>\d+)"
    r"\s+compact=(?P<deposit_compact_path_hits>\d+)"
    r"\s+budget=(?P<drop_processing_budget_hits>\d+)"
)
CHUNK_ALERT_TOKEN = "[chunk_perf] ALERT"

STAGE_EVENTS = [
    ("detect", {"resource_acquired", "drop_detected"}),
    ("mine", {"resource_hit"}),
    ("pickup", {"drop_pickup_success"}),
    ("return", {"return_home_triggered"}),
    ("deposit", {"deposit_success", "deposit_closed", "deposit_closed_ack"}),
]


def parse_worker_event(line: str):
    if WORKER_EVENT_PREFIX not in line:
        return None
    payload = line.split(WORKER_EVENT_PREFIX, 1)[1].strip()
    kv = dict((k.strip(), v.strip()) for k, v in KV_RE.findall(payload))
    event_name = kv.get("event", "")
    npc_id = kv.get("npc_id", "")
    cycle_id = kv.get("work_cycle_id", "")
    if not event_name or not npc_id or not cycle_id:
        return None
    return npc_id, cycle_id, event_name


def score_cycle(events):
    idx = 0
    for evt in events:
        if idx >= len(STAGE_EVENTS):
            break
        _, allowed = STAGE_EVENTS[idx]
        if evt in allowed:
            idx += 1
    return idx == len(STAGE_EVENTS)


def summarize_workers(logfile: str):
    per_npc_cycle_events = defaultdict(list)
    with open(logfile, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            parsed = parse_worker_event(line)
            if parsed is None:
                continue
            npc_id, cycle_id, event_name = parsed
            per_npc_cycle_events[(npc_id, cycle_id)].append(event_name)

    complete_by_npc = defaultdict(int)
    for (npc_id, _cycle_id), events in per_npc_cycle_events.items():
        if score_cycle(events):
            complete_by_npc[npc_id] += 1
    return complete_by_npc


def summarize_perf(logfile: str):
    fps_samples = []
    item_drop_count_max = 0
    merged_drop_events_max = 0
    deposit_compact_path_hits_max = 0
    drop_processing_budget_hits_max = 0
    frame_spike_alerts = 0

    with open(logfile, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if CHUNK_ALERT_TOKEN in line:
                frame_spike_alerts += 1
            m = PERF_RE.search(line)
            if not m:
                continue
            fps_samples.append(float(m.group("fps")))
            item_drop_count_max = max(item_drop_count_max, int(m.group("item_drop_count")))
            merged_drop_events_max = max(merged_drop_events_max, int(m.group("merged_drop_events")))
            deposit_compact_path_hits_max = max(
                deposit_compact_path_hits_max, int(m.group("deposit_compact_path_hits"))
            )
            drop_processing_budget_hits_max = max(
                drop_processing_budget_hits_max, int(m.group("drop_processing_budget_hits"))
            )

    return {
        "fps_samples": fps_samples,
        "fps_min": min(fps_samples) if fps_samples else -1.0,
        "fps_avg": (sum(fps_samples) / len(fps_samples)) if fps_samples else -1.0,
        "frame_spike_alerts": frame_spike_alerts,
        "item_drop_count_max": item_drop_count_max,
        "merged_drop_events_max": merged_drop_events_max,
        "deposit_compact_path_hits_max": deposit_compact_path_hits_max,
        "drop_processing_budget_hits_max": drop_processing_budget_hits_max,
    }


def main():
    ap = argparse.ArgumentParser(
        description="Valida escenario de stress NPC+drops desde logs perf_telemetry + BANDIT_WORKER_EVENT."
    )
    ap.add_argument("logfile", help="Ruta de log capturado durante el escenario")
    ap.add_argument("--min-fps", type=float, default=28.0)
    ap.add_argument("--max-frame-spike-alerts", type=int, default=20)
    ap.add_argument("--max-item-drops", type=int, default=260)
    ap.add_argument("--max-budget-hits", type=int, default=120)
    ap.add_argument("--min-workers", type=int, default=4)
    ap.add_argument("--min-cycles-per-worker", type=int, default=1)
    args = ap.parse_args()

    perf = summarize_perf(args.logfile)
    complete_by_npc = summarize_workers(args.logfile)
    qualified_workers = [
        npc_id
        for npc_id, count in complete_by_npc.items()
        if count >= args.min_cycles_per_worker
    ]

    print("=== Stress validation report ===")
    print(f"FPS avg/min: {perf['fps_avg']:.2f} / {perf['fps_min']:.2f}")
    print(f"Frame spike alerts: {perf['frame_spike_alerts']}")
    print("Drop metrics (max observados):")
    print(f"  item_drop_count={perf['item_drop_count_max']}")
    print(f"  merged_drop_events={perf['merged_drop_events_max']}")
    print(f"  deposit_compact_path_hits={perf['deposit_compact_path_hits_max']}")
    print(f"  drop_processing_budget_hits={perf['drop_processing_budget_hits_max']}")
    print("Workers con ciclos completos:")
    for npc_id in sorted(complete_by_npc):
        print(f"  {npc_id}: {complete_by_npc[npc_id]}")

    failures = []
    if perf["fps_min"] < 0:
        failures.append("No se encontraron muestras perf_telemetry con fps+drops.")
    if perf["fps_min"] >= 0 and perf["fps_min"] < args.min_fps:
        failures.append(f"FPS mínimo {perf['fps_min']:.2f} < umbral {args.min_fps:.2f}")
    if perf["frame_spike_alerts"] > args.max_frame_spike_alerts:
        failures.append(
            f"Frame spike alerts {perf['frame_spike_alerts']} > umbral {args.max_frame_spike_alerts}"
        )
    if perf["item_drop_count_max"] > args.max_item_drops:
        failures.append(
            f"item_drop_count {perf['item_drop_count_max']} > umbral {args.max_item_drops}"
        )
    if perf["drop_processing_budget_hits_max"] > args.max_budget_hits:
        failures.append(
            f"drop_processing_budget_hits {perf['drop_processing_budget_hits_max']} > umbral {args.max_budget_hits}"
        )
    if len(qualified_workers) < args.min_workers:
        failures.append(
            f"Workers válidos {len(qualified_workers)} < umbral {args.min_workers} "
            f"(ciclos mín por worker={args.min_cycles_per_worker})"
        )

    if failures:
        print("\n[FAIL] Escenario NO cumple aceptación.")
        for fail in failures:
            print(f" - {fail}")
        raise SystemExit(1)

    print("\n[PASS] Escenario cumple criterios de aceptación configurados.")


if __name__ == "__main__":
    main()
