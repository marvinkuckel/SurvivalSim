class_name WorldGenerator
extends RefCounted

const WATER := "WATER"
const PLANT := "PLANT"
const TREE := "TREE"
const SMALL_ROCK := "SMALL_ROCK"
const BIG_ROCK := "BIG_ROCK"

static func generate(p: Dictionary) -> Dictionary:
	var width: int = p["width"]
	var height: int = p["height"]
	var world_seed: int = p["seed"]
	var percent_empty: float = p["percent_empty"]
	var weights: Dictionary = p["weights"]
	var shaping: Dictionary = p["shaping"]

	var total_cells := width * height
	var occupied: Dictionary = {}

	var empty_cells_count := roundi((percent_empty / 100.0) * total_cells)
	var available_object_cells := total_cells - empty_cells_count

	var total_weight: float = weights["water"] + weights["plants"] + weights["trees"] + weights["small_rocks"] + weights["big_rocks"]

	var count_water := 0
	var count_plants := 0
	var count_trees := 0
	var count_small_rocks := 0
	var count_big_rocks := 0

	if total_weight > 0 and available_object_cells > 0:
		count_water = roundi((weights["water"] / total_weight) * available_object_cells)
		count_plants = roundi((weights["plants"] / total_weight) * available_object_cells)
		count_trees = roundi((weights["trees"] / total_weight) * available_object_cells)
		count_small_rocks = roundi((weights["small_rocks"] / total_weight) * available_object_cells)
		count_big_rocks = roundi((weights["big_rocks"] / total_weight) * available_object_cells)

	var water_noise := FastNoiseLite.new()
	water_noise.seed = world_seed
	water_noise.frequency = shaping["water"]

	var tree_noise := FastNoiseLite.new()
	tree_noise.seed = world_seed + 1
	tree_noise.frequency = shaping["forest"]

	var rock_noise := FastNoiseLite.new()
	rock_noise.seed = world_seed + 2
	rock_noise.frequency = shaping["mountain"]

	_place(occupied, WATER, count_water, water_noise, width, height)
	_place(occupied, BIG_ROCK, count_big_rocks, rock_noise, width, height)
	_place(occupied, SMALL_ROCK, count_small_rocks, rock_noise, width, height)
	_place(occupied, TREE, count_trees, tree_noise, width, height)
	_place(occupied, PLANT, count_plants, tree_noise, width, height)

	return occupied

static func find_start_cell(occupied: Dictionary, width: int, height: int) -> Vector2i:
	var center := Vector2i(width / 2, height / 2)
	var best := center
	var best_sq := -1
	for x in range(width):
		for z in range(height):
			var pos := Vector2i(x, z)
			if occupied.has(pos): continue
			var dx := x - center.x
			var dz := z - center.y
			var sq := dx * dx + dz * dz
			if best_sq < 0 or sq < best_sq:
				best_sq = sq
				best = pos
	return best

static func _place(occupied: Dictionary, type: String, count: int, noise: FastNoiseLite, width: int, height: int) -> void:
	if count <= 0: return
	var locations := _best_locations(noise, occupied, width, height)
	for i in range(mini(count, locations.size())):
		occupied[locations[i]] = type

static func _best_locations(noise: FastNoiseLite, occupied: Dictionary, width: int, height: int) -> Array[Vector2i]:
	var candidates: Array[Vector3] = []
	for x in range(width):
		for z in range(height):
			if not occupied.has(Vector2i(x, z)):
				candidates.append(Vector3(noise.get_noise_2d(x, z), x, z))
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x > b.x)

	var result: Array[Vector2i] = []
	result.resize(candidates.size())
	for i in range(candidates.size()):
		result[i] = Vector2i(int(candidates[i].y), int(candidates[i].z))
	return result
