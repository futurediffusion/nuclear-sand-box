extends SceneTree

const ThreatAssessmentSystemScript := preload("res://scripts/domain/factions/ThreatAssessmentSystem.gd")
const GroupIntentSystemScript := preload("res://scripts/domain/factions/GroupIntentSystem.gd")
const PlacementReactionSystemScript := preload("res://scripts/domain/factions/PlacementReactionSystem.gd")
const BuildingEventsScript := preload("res://scripts/domain/building/BuildingEvents.gd")


class FakeGroupMemory extends RefCounted:
	var lock_active_by_gid: Dictionary = {}
	var last_attempt_by_gid: Dictionary = {}
	var publish_calls: Array[Dictionary] = []
	var intent_by_gid: Dictionary = {}
	var last_interest_by_gid: Dictionary = {}

	func has_placement_react_lock(group_id: String) -> bool:
		return bool(lock_active_by_gid.get(group_id, false))

	func get_placement_react_attempt(group_id: String) -> Dictionary:
		return last_attempt_by_gid.get(group_id, {})

	func record_interest(group_id: String, world_pos: Vector2, kind: String) -> void:
		last_interest_by_gid[group_id] = {"pos": world_pos, "kind": kind}

	func set_placement_react_lock(group_id: String, _seconds: float) -> void:
		lock_active_by_gid[group_id] = true

	func set_placement_react_attempt(group_id: String, world_pos: Vector2, score: float, anchor_distance: float) -> void:
		last_attempt_by_gid[group_id] = {
			"world_pos": world_pos,
			"score": score,
			"anchor_distance": anchor_distance,
		}

	func update_intent(group_id: String, intent: String) -> void:
		intent_by_gid[group_id] = intent

	func publish_assault_target_intent(group_id: String, anchor_pos: Vector2, target_pos: Vector2,
			reason: String, ttl_seconds: float, source: String) -> bool:
		publish_calls.append({
			"group_id": group_id,
			"anchor_pos": anchor_pos,
			"target_pos": target_pos,
			"reason": reason,
			"ttl_seconds": ttl_seconds,
			"source": source,
		})
		return true


func _init() -> void:
	run()


func run() -> void:
	print("[PLACEMENT_PHASE3] Running placement reaction phase 3 regression harness...")
	_test_building_event_ingestion()
	_test_threat_assessment_generation()
	_test_canonical_intent_publication()
	_test_duplicate_reaction_prevention()
	print("[PLACEMENT_PHASE3] PASS: phase 3 placement reaction pipeline regressions are stable")
	quit(0)


func _test_building_event_ingestion() -> void:
	var reaction: PlacementReactionSystem = PlacementReactionSystemScript.new()
	reaction.setup({
		"tile_to_world": func(tile_pos: Vector2i) -> Vector2: return Vector2(tile_pos) * 32.0,
	})
	var source_event: Dictionary = BuildingEventsScript.structure_removed("wall-1", Vector2i(12, 7), "damage")
	source_event["item_id"] = "wallwood"
	var normalized: Dictionary = reaction._normalize_building_event(source_event)

	assert(String(normalized.get("event_type", "")) == ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_REMOVED,
		"building event ingestion must map structure_removed to threat event type")
	assert((normalized.get("target_position", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(384.0, 224.0)),
		"building event ingestion must resolve world_pos from tile_to_world callback")
	assert(String(normalized.get("item_id", "")) == "wallwood",
		"building event ingestion must preserve explicit item_id")


func _test_threat_assessment_generation() -> void:
	var threat: ThreatAssessmentSystem = ThreatAssessmentSystemScript.new()
	var assessment: Dictionary = threat.assess_building_event(
		{
			"type": ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_PLACED,
			"item_id": "wallwood",
			"target_position": Vector2(320.0, 160.0),
			"tile_pos": Vector2i(10, 5),
		},
		{
			"min_group_score": 0.40,
			"max_groups": 2,
			"group_candidates": [
				{
					"gid": "camp:a",
					"faction_id": "bandits",
					"anchor_kind": "leader",
					"dist_sq": 196.0,
					"score_pack": {"score": 0.82},
				},
				{
					"gid": "camp:b",
					"faction_id": "bandits",
					"anchor_kind": "home",
					"dist_sq": 625.0,
					"score_pack": {"score": 0.33},
				},
			],
		}
	)

	assert(bool(assessment.get("is_relevant", false)),
		"threat assessment should be relevant when an eligible group candidate exists")
	assert(String(assessment.get("priority", "none")) != ThreatAssessmentSystem.PRIORITY_NONE,
		"threat assessment should produce non-none priority for relevant events")
	var scope: Dictionary = assessment.get("candidate_group_scope", {}) as Dictionary
	var candidates: Array = scope.get("candidates", []) as Array
	assert(candidates.size() == 1,
		"threat assessment should filter candidates below min_group_score")
	assert(String((candidates[0] as Dictionary).get("group_id", "")) == "camp:a",
		"threat assessment should keep the highest eligible candidate")


func _test_canonical_intent_publication() -> void:
	var fake_memory := FakeGroupMemory.new()
	var intents: GroupIntentSystem = GroupIntentSystemScript.new()
	intents.setup({
		"group_memory": fake_memory,
		"now_provider": func() -> float: return 1234.0,
	})
	var assessment := {
		"priority": "high",
		"severity": 0.77,
		"target_position": Vector2(224.0, 96.0),
		"source_event": {
			"event_type": ThreatAssessmentSystem.EVENT_TYPE_STRUCTURE_PLACED,
			"item_id": "wallwood",
			"tile_pos": Vector2i(7, 3),
			"world_pos": Vector2(224.0, 96.0),
			"metadata": {"source": "test"},
		},
		"debug": {"trace": "phase3"},
	}
	var outcome: Dictionary = intents.publish_placement_reaction_intent(
		assessment,
		{
			"group_id": "camp:test",
			"score": 0.79,
			"anchor_distance": 48.0,
			"anchor_kind": "leader",
			"anchor_position": Vector2(200.0, 80.0),
		},
		{
			"squad_size": 4,
			"ttl_seconds": 90.0,
			"reason_source": "placed_structure",
		}
	)

	assert(bool(outcome.get("published", false)),
		"group intent publication must publish through canonical BanditGroupMemory path")
	var canonical_intent: Dictionary = outcome.get("intent", {}) as Dictionary
	assert(String(canonical_intent.get("kind", "")) == GroupIntentSystem.INTENT_KIND_PLACEMENT_REACTION,
		"published intent must use canonical placement reaction kind")
	var publication: Dictionary = canonical_intent.get("publication", {}) as Dictionary
	assert(String(publication.get("path", "")) == "BanditGroupMemory.publish_assault_target_intent",
		"published intent must declare canonical publication path for telemetry")
	assert(fake_memory.publish_calls.size() == 1,
		"group memory publish_assault_target_intent should be called exactly once")


func _test_duplicate_reaction_prevention() -> void:
	BanditGroupMemory.reset()
	var reaction: PlacementReactionSystem = PlacementReactionSystemScript.new()
	reaction.setup({
		"event_min_interval": 0.0,
		"event_dedupe_window": 5.0,
		"tile_to_world": func(tile_pos: Vector2i) -> Vector2: return Vector2(tile_pos) * 32.0,
	})
	var event_data := {
		"type": ThreatAssessmentSystem.EVENT_TYPE_PLACEMENT_COMPLETED,
		"item_id": "wallwood",
		"tile_pos": Vector2i(4, 4),
	}
	reaction.handle_building_event(event_data)
	reaction.handle_building_event(event_data)
	var snapshot: Dictionary = reaction.get_debug_snapshot()
	assert(int(snapshot.get("events_total", 0)) == 2,
		"duplicate prevention telemetry should still count attempted ingestions")
	assert(int(snapshot.get("skipped_duplicate_events_total", 0)) == 1,
		"duplicate placement reaction paths should be suppressed by dedupe window")
	BanditGroupMemory.reset()
