extends RefCounted
class_name SandboxDomainLanguage

## Canonical vocabulary boundary for sandbox architecture.
## This dictionary is intentionally additive so runtime surfaces can expose
## preferred terms while still keeping legacy aliases during migration.

const DOMAIN_LANGUAGE_VERSION: int = 1

const PREFERRED_TERMS := {
	"structure": "structure_record",
	"placeable": "placeable_structure",
	"buildable": "buildable_item",
	"canonical_intent": "intent_record",
	"task": "task_plan",
	"projection": "derived_projection",
	"snapshot": "canonical_snapshot",
	"runtime_only": "runtime_derived",
	"legacy_hint": "compat_legacy_hint",
	"migration_path": "migration_steps",
}

const DEPRECATED_TERMS := {
	"structure_counts": "structure_record_counts",
	"legacy_driven": "compat_legacy_hint_used",
	"legacy_input_used": "compat_legacy_hint_consumed",
	"world_snapshot_state": "canonical_snapshot",
}


static func get_snapshot() -> Dictionary:
	return {
		"domain_language_version": DOMAIN_LANGUAGE_VERSION,
		"preferred_terms": PREFERRED_TERMS.duplicate(true),
		"deprecated_terms": DEPRECATED_TERMS.duplicate(true),
	}
