class_name WorldGenerator
extends RefCounted
# Deterministic world generation (same seed + settings = same world).
# Each tile type claims the free cells with the highest noise value, which
# forms natural clusters (lakes, forests, mountains).

# tile type -> [shaping key, seed offset]
# Types sharing a layer use the same noise field. Dictionary order = placement
# order, so water gets the first pick and plants the last.
const LAYERS := {
	"WATER": ["water", 0],
	"BIG_ROCK": ["mountain", 2],
	"SMALL_ROCK": ["mountain", 2],
	"TREE": ["forest", 1],
	"PLANT": ["forest", 1],
}


# params: width, height, seed, percent_empty,
#         weights (tile type -> weight), shaping (water/forest/mountain -> noise frequency)
# Returns a Dictionary: Vector2i -> tile type. Missing cells are empty.
static func generate(params: Dictionary) -> Dictionary:
	var width: int = params["width"]
	var height: int = params["height"]
	var weights: Dictionary = params["weights"]
	var occupied := {}

	# Number of cells that may hold objects, split by weight ratio
	var total_cells := width * height
	var object_cells: int = total_cells - roundi(params["percent_empty"] / 100.0 * total_cells)
	var total_weight := 0.0
	for type: String in weights:
		total_weight += weights[type]
	if total_weight <= 0.0 or object_cells <= 0:
		return occupied

	for type: String in LAYERS:
		var noise := FastNoiseLite.new()
		noise.seed = params["seed"] + LAYERS[type][1]
		noise.frequency = params["shaping"][LAYERS[type][0]]
		var count := roundi(weights[type] / total_weight * object_cells)
		var ranked := _rank_free_cells(noise, occupied, width, height)
		for i in mini(count, ranked.size()):
			occupied[ranked[i]] = type
	return occupied


# Free cell closest to the map center (the agent's spawn and first hut).
@warning_ignore("integer_division")
static func find_start_cell(occupied: Dictionary, width: int, height: int) -> Vector2i:
	var center := Vector2i(width / 2, height / 2)
	var best := center
	var best_dist := INF
	for x in width:
		for y in height:
			var pos := Vector2i(x, y)
			if occupied.has(pos): continue
			var dist := (pos - center).length_squared()
			if dist < best_dist:
				best = pos
				best_dist = dist
	return best


# All free cells, sorted by noise value (highest first).
static func _rank_free_cells(noise: FastNoiseLite, occupied: Dictionary, width: int, height: int) -> Array[Vector2i]:
	var scored: Array[Vector3] = []  # (noise value, x, y)
	for x in width:
		for y in height:
			if not occupied.has(Vector2i(x, y)):
				scored.append(Vector3(noise.get_noise_2d(x, y), x, y))
	scored.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x > b.x)

	var cells: Array[Vector2i] = []
	for s in scored:
		cells.append(Vector2i(int(s.y), int(s.z)))
	return cells
