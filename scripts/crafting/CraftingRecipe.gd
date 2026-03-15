extends Resource
class_name CraftingRecipe

## Receta de crafteo. Usada por CraftingDB (autoload) para registrar todas las recetas.
## Usa arrays paralelos (ingredient_ids / ingredient_amounts) para compatibilidad con .tres.

@export var recipe_id: String = ""
@export var result_item_id: String = ""
@export var result_count: int = 1
@export var ingredient_ids: Array[String] = []
@export var ingredient_amounts: Array[int] = []
@export var category: String = "survival"   # survival | tools | stations | tinkering
@export var station_id: String = "workbench"
@export var station_tier_required: int = 1


## Devuelve los ingredientes como Array de {item_id, amount}.
func get_ingredients() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in ingredient_ids.size():
		var amount := ingredient_amounts[i] if i < ingredient_amounts.size() else 1
		result.append({"item_id": ingredient_ids[i], "amount": amount})
	return result
