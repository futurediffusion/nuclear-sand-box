extends Node

## Autoload que registra todas las recetas del juego.
## Agregar aquí nuevas recetas. En el futuro puede cargar desde data/recipes/*.tres.

var _recipes: Array[CraftingRecipe] = []
var _by_id: Dictionary = {}


func _ready() -> void:
	_register_all()
	Debug.log("crafting", "CraftingDB listo con %d recetas" % _recipes.size())


# ── Consultas ─────────────────────────────────────────────────────────────────

func get_recipe(recipe_id: String) -> CraftingRecipe:
	return _by_id.get(recipe_id, null) as CraftingRecipe


func get_recipes_for_category(category: String) -> Array[CraftingRecipe]:
	var result: Array[CraftingRecipe] = []
	for r in _recipes:
		if r.category == category:
			result.append(r)
	return result


func get_all_recipes() -> Array[CraftingRecipe]:
	return _recipes.duplicate()


# ── Registro interno ─────────────────────────────────────────────────────────

func _add(recipe_id: String, result_id: String, result_count: int,
		category: String, tier: int,
		ids: Array[String], amounts: Array[int]) -> void:
	var r := CraftingRecipe.new()
	r.recipe_id             = recipe_id
	r.result_item_id        = result_id
	r.result_count          = result_count
	r.category              = category
	r.station_id            = "workbench"
	r.station_tier_required = tier
	r.ingredient_ids        = ids
	r.ingredient_amounts    = amounts
	_recipes.append(r)
	_by_id[recipe_id] = r


func _register_all() -> void:
	# ── Survival ──────────────────────────────────────────────────────────────
	_add("sword_wood",    "sword_wood",    1, "survival", 1, ["wood",   "fiber", "stick"], [3, 2, 2])
	_add("sword_stone",   "sword_stone",   1, "survival", 1, ["stone",  "fiber", "stick"], [4, 2, 3])
	_add("sword_copper",  "sword_copper",  1, "survival", 1, ["copper", "fiber", "stick"], [5, 5, 4])
	_add("bow",           "bow",           1, "survival", 1, ["stick",  "fiber"],           [8, 10])
	_add("ironpipe",      "ironpipe",      1, "survival", 1, ["copper", "stick"],           [3, 4])
	_add("arrow",         "arrow",         4, "survival", 1, ["stick",  "stone"],           [4, 2])
	_add("chest",         "chest",         1, "survival", 1, ["wood"],                      [10])

	# ── Tools ─────────────────────────────────────────────────────────────────
	_add("axe_wood",       "axe_wood",       1, "tools", 1, ["wood",   "fiber", "stick"], [3, 2, 2])
	_add("axe_stone",      "axe_stone",      1, "tools", 1, ["stone",  "fiber", "stick"], [4, 2, 3])
	_add("axe_copper",     "axe_copper",     1, "tools", 1, ["copper", "fiber", "stick"], [5, 5, 4])
	_add("pickaxe_wood",   "pickaxe_wood",   1, "tools", 1, ["wood",   "fiber", "stick"], [3, 2, 2])
	_add("pickaxe_stone",  "pickaxe_stone",  1, "tools", 1, ["stone",  "fiber", "stick"], [4, 2, 3])
	_add("pickaxe_copper", "pickaxe_copper", 1, "tools", 1, ["copper", "fiber", "stick"], [5, 5, 4])

	# ── Stations ──────────────────────────────────────────────────────────────
	_add("workbench", "workbench", 1, "stations", 1, ["wood", "stone"], [4, 4])
	_add("wallwood", "wallwood", 1, "tinkering", 1, ["wood"], [1])
	_add("doorwood", "doorwood", 1, "tinkering", 1, ["wood"], [8])
	_add("floorwood", "floorwood", 1, "tinkering", 1, ["wood"], [4])
	_add("table", "table", 1, "tinkering", 1, ["wood", "stick"], [6, 4])
