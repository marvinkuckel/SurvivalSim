class_name SimulationCore
extends RefCounted
# Pure game logic without any Godot nodes (easy to port to Python later).
# Every action teleports the agent to the closest matching tile, pays the
# energy cost and returns a short status message for the UI.

const MAX_STAT := 100.0
const INVENTORY_LIMIT := 3
const HUT_CAPACITY := 10           # storage space per resource and hut
const NO_TILE := Vector2i(-1, -1)  # marker for "nothing found"

# Agent state
var agent_energy: float
var agent_food: float
var agent_water: float
var agent_pos: Vector2i
var spawn_point: Vector2i
var is_alive: bool
var inventory: Array = []

# World state
var storage: Dictionary = {}           # central storage: resource -> amount
var buildings: Dictionary = {}         # building type -> count
var object_locations: Dictionary = {}  # tile type -> Array[Vector2i]

var _cells: Dictionary                 # generated world, kept for reset()
var _last_cost: float = 0.0            # energy paid by the latest travel


func _init(cells: Dictionary, start_pos: Vector2i) -> void:
	_cells = cells
	spawn_point = start_pos
	reset()


# Restores the complete initial state (agent, storage, plants, huts).
func reset() -> void:
	agent_energy = MAX_STAT
	agent_food = MAX_STAT
	agent_water = MAX_STAT
	agent_pos = spawn_point
	is_alive = true
	inventory.clear()
	storage = {"WATER": 0, "FOOD": 0, "WOOD": 0, "STONE": 0}
	buildings = {"HUT": 1}
	object_locations = {
		"WATER": [], "PLANT": [], "TREE": [], "SMALL_ROCK": [], "BIG_ROCK": [],
		"HUT": [spawn_point],
	}
	for pos: Vector2i in _cells:
		object_locations[_cells[pos]].append(pos)


func get_max_storage_capacity() -> int:
	return buildings["HUT"] * HUT_CAPACITY


# Returns {"pos": closest tile of this type (or NO_TILE), "distance": euclidean distance}.
func get_closest_interaction(type: String) -> Dictionary:
	var best: Vector2i = NO_TILE
	var best_dist := INF
	for pos: Vector2i in object_locations[type]:
		var dist: float = (agent_pos - pos).length()
		if dist < best_dist:
			best = pos
			best_dist = dist
	return {"pos": best, "distance": 0.0 if best == NO_TILE else best_dist}


# Moves the agent to the closest tile of `type` and pays base cost + 0.5 per tile.
# Returns an error message, or "" on success.
func _travel_to(type: String, base_cost: float) -> String:
	var info := get_closest_interaction(type)
	if info["pos"] == NO_TILE:
		return "No %s found!" % type.to_lower()
	var cost: float = base_cost + info["distance"] * 0.5
	if agent_energy < cost:
		return "Not enough energy!"
	agent_pos = info["pos"]
	agent_energy -= cost
	_last_cost = cost
	return ""


# ==============================================================================
# ACTIONS (1:1 ready for reinforcement learning)
# ==============================================================================

func collect_water() -> String:
	if not is_alive: return "DEAD"
	if inventory.size() >= INVENTORY_LIMIT: return "Inventory full!"
	var err := _travel_to("WATER", 5.0)
	if err != "": return err
	inventory.append("WATER")
	return "Collected Water (-%.1f Energy)" % _last_cost


func harvest_plant() -> String:
	if not is_alive: return "DEAD"
	if inventory.size() >= INVENTORY_LIMIT: return "Inventory full!"
	var err := _travel_to("PLANT", 6.0)
	if err != "": return err
	inventory.append("FOOD")
	object_locations["PLANT"].erase(agent_pos)  # agent now stands on the plant
	return "Harvested Plant (-%.1f Energy)" % _last_cost


func store_inventory_in_hut() -> String:
	if not is_alive: return "DEAD"
	if inventory.is_empty(): return "Inventory empty!"
	var err := _travel_to("HUT", 2.0)
	if err != "": return err
	var capacity := get_max_storage_capacity()
	var stored := 0
	var remaining: Array = []
	for item: String in inventory:
		if storage.has(item) and storage[item] < capacity:
			storage[item] += 1
			stored += 1
		else:
			remaining.append(item)  # storage full, item stays in the inventory
	inventory = remaining
	return "Deposited %d items into Central Storage." % stored


# Resting restores energy but costs food and water (less water inside a hut).
func wait_and_rest() -> String:
	if not is_alive: return "DEAD"
	agent_energy = minf(MAX_STAT, agent_energy + 15.0)
	agent_food -= 8.0
	agent_water -= 6.0 if agent_pos in object_locations["HUT"] else 12.0
	if agent_food <= 0.0 or agent_water <= 0.0:
		is_alive = false
		return "DIED"
	return "Rested. Energy restored, food and water consumed."
