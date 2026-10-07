class_name WorldGenerator
extends RefCounted
# Deterministic world generation (same seed + settings = same world).
# Each tile type claims the free cells with the highest noise value, which
# forms natural clusters (lakes, forests, mountains).

const Tile = GameConfig.Tile

# tile type -> [shaping key, seed offset]
# Types sharing a layer use the same noise field. Dictionary order = placement
# order, so water gets the first pick and plants the last.
const LAYERS := {
	Tile.WATER: ["water", 0],
	Tile.BIG_ROCK: ["mountain", 2],
	Tile.SMALL_ROCK: ["mountain", 2],
	Tile.TREE: ["forest", 1],
	Tile.PLANT: ["forest", 1],
}


# params: width, height, seed, percent_empty,
#         weights (tile type -> weight), shaping (water/forest/mountain -> noise frequency)
# Returns one tile type per cell (index = y * width + x).
static func generate(params: Dictionary) -> PackedInt32Array:
	var width: int = params["width"]
	var height: int = params["height"]
	var weights: Dictionary = params["weights"]
	var tiles := PackedInt32Array()
	tiles.resize(width * height)  # zero-filled = Tile.EMPTY

	# Number of cells that may hold objects, split by weight ratio
	var total_cells := width * height
	var object_cells: int = total_cells - roundi(params["percent_empty"] / 100.0 * total_cells)
	var total_weight := 0.0
	for type: int in weights:
		total_weight += weights[type]
	if total_weight <= 0.0 or object_cells <= 0:
		return tiles

	for type: int in LAYERS:
		var noise := FastNoiseLite.new()
		noise.seed = params["seed"] + LAYERS[type][1]
		noise.frequency = params["shaping"][LAYERS[type][0]]
		var count := roundi(weights[type] / total_weight * object_cells)
		var ranked := _rank_free_cells(noise, tiles, width)
		for i in mini(count, ranked.size()):
			tiles[ranked[i]] = type
	return tiles


# Free cell closest to the map center (home and agent spawn).
@warning_ignore("integer_division")
static func find_start_cell(tiles: PackedInt32Array, width: int, height: int) -> Vector2i:
	var center := Vector2i(width / 2, height / 2)
	var best := center
	var best_dist := INF
	for i in tiles.size():
		if tiles[i] != Tile.EMPTY: continue
		var pos := Vector2i(i % width, i / width)
		var dist := (pos - center).length_squared()
		if dist < best_dist:
			best = pos
			best_dist = dist
	return best


# Indices of all free cells, sorted by noise value (highest first).
@warning_ignore("integer_division")
static func _rank_free_cells(noise: FastNoiseLite, tiles: PackedInt32Array, width: int) -> Array[int]:
	var scored: Array[Vector2] = []  # (noise value, cell index)
	for i in tiles.size():
		if tiles[i] == Tile.EMPTY:
			scored.append(Vector2(noise.get_noise_2d(i % width, i / width), i))
	scored.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)

	var ranked: Array[int] = []
	for s in scored:
		ranked.append(int(s.y))
	return ranked
