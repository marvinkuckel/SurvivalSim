class_name SimulationCore
extends RefCounted
# Pure game logic without any Godot nodes (easy to port to Python / NumPy).
# The world lives in flat arrays (index = y * width + x). Every action is looked
# up by name in GameConfig; perform(action) is the single entry point for players
# and AI agents. An action that cannot be performed changes nothing.

const Tile = GameConfig.Tile
const NO_TILE := Vector2i(-1, -1)

# World state (one entry per cell)
var width: int
var height: int
var tiles: PackedInt32Array     # tile type
var amount: PackedInt32Array    # remaining yield of logs, stone piles and small rocks
var crop_age: PackedInt32Array  # growth days of the crop on a FIELD
var watered: PackedByteArray    # 1 = field was hand-watered (once is enough, see REWATER_AFTER_HARVEST)
# One flag per cell edge: first all vertical edges (y * (width + 1) + x), then all
# horizontal edges (v_edge_count + y * width + x). A flag means "a stick lies here".
var sticks: PackedByteArray
var v_edge_count: int

# Agent state
var agent_pos: Vector2i
var spawn_point: Vector2i
var agent_energy: float
var agent_food: float
var agent_water: float
var is_alive: bool
var inventory: Array = []
var tools: Dictionary = {}
var storage: Dictionary = {}    # central storage: resource -> amount
var day: int
var score: int
var energy_spent_today: float   # energy spent on work today (0 = idle day so far, rest then gives the bonus)

var _initial_tiles: PackedInt32Array  # generated world, kept for reset()
var _seed: int
var _rng := RandomNumberGenerator.new()


func _init(initial_tiles: PackedInt32Array, map_width: int, map_height: int, start_cell: Vector2i, world_seed: int) -> void:
	_initial_tiles = initial_tiles
	width = map_width
	height = map_height
	spawn_point = start_cell
	_seed = world_seed
	v_edge_count = (width + 1) * height
	reset()


# Restores the complete initial state (world, agent, storage, tools).
func reset() -> void:
	var cells := width * height
	tiles = _initial_tiles.duplicate()
	amount.resize(cells)
	amount.fill(0)
	crop_age.resize(cells)
	crop_age.fill(0)
	watered.resize(cells)
	watered.fill(0)
	sticks.resize(v_edge_count + width * (height + 1))
	sticks.fill(0)
	for i in cells:
		if tiles[i] == Tile.SMALL_ROCK:
			amount[i] = GameConfig.SMALL_ROCK_YIELD

	# The home hut stands on the start cell, the agent next to it
	tiles[idx_of(spawn_point)] = Tile.HOME
	agent_pos = spawn_point
	for n in _neighbors(idx_of(spawn_point)):
		if _walkable(n):
			agent_pos = pos_of(n)
			break

	agent_energy = GameConfig.MAX_STAT
	agent_food = GameConfig.MAX_STAT
	agent_water = GameConfig.MAX_STAT
	is_alive = true
	inventory.clear()
	tools = {"HOE": false, "AXE": false, "PICKAXE": false, "WHEELBARROW": false}
	storage = {"WATER": 0, "FOOD": 0, "WOOD": 0, "STONE": 0}
	day = 0
	score = 0
	energy_spent_today = 0.0
	_rng.seed = _seed


# ==============================================================================
# PUBLIC API
# ==============================================================================

# Performs an action and returns a status message. Special messages that end a run:
# "DIED" (agent died), "FINISHED" (day limit reached), "DEAD" (agent already dead).
func perform(action: String) -> String:
	if not GameConfig.COST.has(action): return "Unknown action!"
	var plan := _plan(action, _distances())
	if not plan["ok"]: return plan["msg"]

	agent_pos = plan["stop"]
	agent_energy -= plan["cost"]
	if action not in GameConfig.NON_WORK_ACTIONS:
		energy_spent_today += plan["cost"]
	var message := _apply(action, plan)
	if message == "DIED" or message == "FINISHED" or plan["cost"] <= 0.0:
		return message
	return "%s (-%d energy)" % [message, ceili(plan["cost"])]


# Plans of all actions at once: {"ok", "msg", "cost", "stop", "target", "has_target", "target_idx"}
# Used by the UI to show which actions are possible and where their targets are.
func get_plans() -> Dictionary:
	var plans := {}
	var dist := _distances()
	for action: String in GameConfig.COST:
		plans[action] = _plan(action, dist)
	return plans


func inventory_slots() -> int:
	return GameConfig.WHEELBARROW_SLOTS if tools["WHEELBARROW"] else GameConfig.INVENTORY_SLOTS


# Home and every living hut add storage space.
func get_max_storage_capacity() -> int:
	return (1 + count_tiles(Tile.HUT)) * GameConfig.HUT_CAPACITY


func count_tiles(type: int) -> int:
	var count := 0
	for t in tiles:
		if t == type:
			count += 1
	return count


# Walking distance from the agent to the closest tile of the given types (-1 = unreachable).
func steps_to(types: Array) -> int:
	var dist := _distances()
	var best := -1
	for i in tiles.size():
		if tiles[i] not in types: continue
		for n in _neighbors(i):
			if dist[n] >= 0 and (best < 0 or dist[n] < best):
				best = dist[n]
	return best


# A field is wet if it is next to water/well or was watered by hand.
func is_wet(i: int) -> bool:
	return watered[i] == 1 or _next_to_water(i)


@warning_ignore("integer_division")
func pos_of(i: int) -> Vector2i:
	return Vector2i(i % width, i / width)


func idx_of(pos: Vector2i) -> int:
	return pos.y * width + pos.x


# Center of a cell edge in cell coordinates (used to draw sticks).
@warning_ignore("integer_division")
func edge_center(e: int) -> Vector2:
	if e < v_edge_count:
		return Vector2(e % (width + 1) - 0.5, e / (width + 1))
	var k := e - v_edge_count
	return Vector2(k % width, k / width - 0.5)


# ==============================================================================
# PLANNING (checks an action without changing anything)
# ==============================================================================

func _plan(action: String, dist: PackedInt32Array) -> Dictionary:
	var plan := {"ok": false, "msg": "", "cost": 0.0, "stop": agent_pos,
			"target": Vector2.ZERO, "has_target": false, "target_idx": -1}
	if not is_alive:
		plan["msg"] = "DEAD"
		return plan
	var err := _precheck(action)
	if err != "":
		plan["msg"] = err
		return plan

	var cost: float = GameConfig.COST[action]
	if action in GameConfig.HOE_ACTIONS and tools["HOE"]:
		cost *= GameConfig.HOE_DISCOUNT

	# Most actions need the agent to walk next to a target
	if action != "rest" and not _uses_inventory_only(action):
		var found := _find_target(action, dist)
		if found.is_empty():
			plan["msg"] = "Nothing reachable for this action!"
			return plan
		plan["stop"] = found["stop"]
		plan["target"] = found["target"]
		plan["target_idx"] = found["index"]
		plan["has_target"] = true
		cost += found["steps"] * GameConfig.STEP_COST

	if agent_energy < cost:
		plan["msg"] = "Not enough energy!"
		return plan
	plan["cost"] = cost
	plan["ok"] = true
	return plan


# Conditions that do not depend on the position (tools, items, materials, limits).
func _precheck(action: String) -> String:
	var required: String = GameConfig.TOOL_REQUIRED.get(action, "")
	if required != "" and not tools[required]:
		return "Needs a %s!" % required.to_lower()

	match action:
		"collect_water", "collect_stick", "collect_wood", "collect_stone", "digout_plant", "farm_crop":
			if inventory.size() >= inventory_slots(): return "Inventory full!"
		"plant_crop_here", "plant_crop_near_water":
			if "PLANT" not in inventory: return "No plant in the inventory!"
		"water_crop":
			if "WATER" not in inventory: return "No water in the inventory!"
		"eat", "drink":
			var item := "FOOD" if action == "eat" else "WATER"
			var level := agent_food if action == "eat" else agent_water
			if level >= GameConfig.MAX_STAT: return "Already full!"
			if item not in inventory and storage[item] <= 0: return "Nothing available!"
		"deposit_inventory":
			var capacity := get_max_storage_capacity()
			if not inventory.any(func(item: String) -> bool: return storage.has(item) and storage[item] < capacity):
				return "Nothing to deposit!"
		"rest":
			pass
		_:
			if GameConfig.TOOLS.has(action):
				var recipe: Dictionary = GameConfig.TOOLS[action]
				if tools[recipe["tool"]]: return "Already crafted!"
				if count_tiles(Tile.WORKBENCH) == 0: return "Needs a workbench!"
				if not _can_afford(recipe["materials"]): return "Not enough materials!"
			elif GameConfig.BUILDINGS.has(action):
				var recipe: Dictionary = GameConfig.BUILDINGS[action]
				if count_tiles(recipe["tile"]) >= GameConfig.MAX_COUNT[recipe["tile"]]: return "Build limit reached!"
				if not _can_afford(recipe["materials"]): return "Not enough materials!"
	return ""


# Eating or drinking from the inventory needs no walking.
func _uses_inventory_only(action: String) -> bool:
	return (action == "eat" and "FOOD" in inventory) or (action == "drink" and "WATER" in inventory)


func _can_afford(materials: Dictionary) -> bool:
	for item: String in materials:
		if storage[item] < materials[item]:
			return false
	return true


# ==============================================================================
# TARGET SEARCH (breadth-first walking distances + nearest target)
# ==============================================================================

# Walking distance in steps from the agent to every cell (-1 = unreachable).
func _distances() -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var start := idx_of(agent_pos)
	dist[start] = 0
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		for n in _neighbors(cur):
			if dist[n] == -1 and _walkable(n):
				dist[n] = dist[cur] + 1
				queue.append(n)
	return dist


# Cheapest target of an action. The agent has to stand on a reachable cell next to it.
# Returns {} or {"index", "target" (cell coords), "stop" (cell), "steps"}.
func _find_target(action: String, dist: PackedInt32Array) -> Dictionary:
	var best := {}
	var best_steps := 1 << 30
	if action == "collect_stick":
		for e in sticks.size():
			if sticks[e] == 0: continue
			for c in _edge_cells(e):
				if dist[c] >= 0 and dist[c] < best_steps:
					best_steps = dist[c]
					best = {"index": e, "target": edge_center(e), "stop": pos_of(c), "steps": dist[c]}
		return best
	for i in tiles.size():
		if not _is_target(action, i): continue
		for n in _neighbors(i):
			if dist[n] >= 0 and dist[n] < best_steps:
				best_steps = dist[n]
				best = {"index": i, "target": Vector2(pos_of(i)), "stop": pos_of(n), "steps": dist[n]}
	return best


# Which cells an action can work on.
func _is_target(action: String, i: int) -> bool:
	var t := tiles[i]
	match action:
		"collect_water": return t == Tile.WATER or t == Tile.WELL
		"collect_wood": return t == Tile.LOG
		"collect_stone": return t == Tile.SMALL_ROCK or t == Tile.STONE_PILE
		"fell_tree": return t == Tile.TREE
		"mine_stone": return t == Tile.BIG_ROCK
		"digout_plant": return t == Tile.PLANT
		"plant_crop_here": return _is_free(i)
		"plant_crop_near_water": return _is_free(i) and _next_to_water(i)
		"water_crop": return t == Tile.FIELD and not is_wet(i)
		"farm_crop": return t == Tile.FIELD and crop_age[i] >= GameConfig.CROP_RIPE_DAYS
		"eat", "drink", "deposit_inventory": return t == Tile.HOME or t == Tile.HUT
	if GameConfig.TOOLS.has(action):
		return t == Tile.WORKBENCH
	if GameConfig.BUILDINGS.has(action):
		return _is_free(i)
	return false


# Empty cell that is not occupied by the agent: the only place where things can be placed.
func _is_free(i: int) -> bool:
	return tiles[i] == Tile.EMPTY and i != idx_of(agent_pos)


func _next_to_water(i: int) -> bool:
	for n in _neighbors(i):
		if tiles[n] == Tile.WATER or tiles[n] == Tile.WELL:
			return true
	return false


func _walkable(i: int) -> bool:
	return tiles[i] in GameConfig.WALKABLE


func _neighbors(i: int) -> Array[int]:
	var result: Array[int] = []
	if i % width > 0: result.append(i - 1)
	if i % width < width - 1: result.append(i + 1)
	if i >= width: result.append(i - width)
	if i < tiles.size() - width: result.append(i + width)
	return result


# Edge index of a cell side (0 = left, 1 = right, 2 = top, 3 = bottom).
@warning_ignore("integer_division")
func _edge_of(i: int, side: int) -> int:
	var x := i % width
	var y := i / width
	match side:
		0: return y * (width + 1) + x
		1: return y * (width + 1) + x + 1
		2: return v_edge_count + y * width + x
	return v_edge_count + (y + 1) * width + x


# The one or two cells that touch an edge.
@warning_ignore("integer_division")
func _edge_cells(e: int) -> Array[int]:
	var cells: Array[int] = []
	if e < v_edge_count:
		var x := e % (width + 1)
		var y := e / (width + 1)
		if x > 0: cells.append(y * width + x - 1)
		if x < width: cells.append(y * width + x)
	else:
		var k := e - v_edge_count
		var x := k % width
		var y := k / width
		if y > 0: cells.append((y - 1) * width + x)
		if y < height: cells.append(y * width + x)
	return cells


# ==============================================================================
# EFFECTS (the agent has already walked to the stop cell and paid the energy)
# ==============================================================================

func _apply(action: String, plan: Dictionary) -> String:
	var i: int = plan["target_idx"]
	match action:
		"collect_water":
			inventory.append("WATER")
			return "Collected water"
		"collect_stick":
			sticks[i] = 0
			inventory.append("WOOD")
			return "Picked up a stick"
		"collect_wood":
			_take_from_pile(i)
			inventory.append("WOOD")
			return "Collected wood"
		"collect_stone":
			_take_from_pile(i)
			inventory.append("STONE")
			return "Collected stone"
		"fell_tree":
			tiles[i] = Tile.LOG
			amount[i] = GameConfig.LOG_YIELD
			return "Felled a tree"
		"mine_stone":
			tiles[i] = Tile.STONE_PILE
			amount[i] = GameConfig.STONE_PILE_YIELD
			return "Mined a rock"
		"digout_plant":
			tiles[i] = Tile.EMPTY
			inventory.append("PLANT")
			return "Dug out a plant"
		"plant_crop_here", "plant_crop_near_water":
			inventory.erase("PLANT")
			tiles[i] = Tile.FIELD
			crop_age[i] = 0
			watered[i] = 0
			return "Planted a crop"
		"water_crop":
			inventory.erase("WATER")
			watered[i] = 1
			return "Watered a crop"
		"farm_crop":
			crop_age[i] = 0  # the crop grows back
			if GameConfig.REWATER_AFTER_HARVEST:
				watered[i] = 0
			inventory.append("FOOD")
			return "Harvested a crop"
		"eat", "drink":
			var item := "FOOD" if action == "eat" else "WATER"
			if item in inventory:
				inventory.erase(item)
			else:
				storage[item] -= 1
			if action == "eat":
				agent_food = minf(GameConfig.MAX_STAT, agent_food + GameConfig.EAT_GAIN)
				return "Ate something"
			agent_water = minf(GameConfig.MAX_STAT, agent_water + GameConfig.DRINK_GAIN)
			return "Drank something"
		"deposit_inventory":
			var capacity := get_max_storage_capacity()
			var remaining: Array = []
			var stored := 0
			for item: String in inventory:
				if storage.has(item) and storage[item] < capacity:
					storage[item] += 1
					stored += 1
				else:
					remaining.append(item)  # storage full or not storable: stays in the inventory
			inventory = remaining
			return "Deposited %d items" % stored
		"rest":
			return _end_day()
	if GameConfig.TOOLS.has(action):
		var recipe: Dictionary = GameConfig.TOOLS[action]
		_pay(recipe["materials"])
		tools[recipe["tool"]] = true
		return "Crafted a %s" % String(recipe["tool"]).to_lower()
	var building: Dictionary = GameConfig.BUILDINGS[action]
	_pay(building["materials"])
	tiles[i] = building["tile"]
	return "Built a %s" % action.trim_prefix("build_")


func _pay(materials: Dictionary) -> void:
	for item: String in materials:
		storage[item] -= materials[item]


# Takes one unit from a log / stone pile / small rock; the tile disappears when used up.
func _take_from_pile(i: int) -> void:
	amount[i] -= 1
	if amount[i] <= 0:
		tiles[i] = Tile.EMPTY


# Ends the day: offspring, crops, trees, then the agent's own needs.
func _end_day() -> String:
	# 1. Living huts eat and drink from the storage (+1 score) or die for good
	for i in tiles.size():
		if tiles[i] != Tile.HUT: continue
		if storage["FOOD"] >= GameConfig.HUT_FOOD_PER_DAY and storage["WATER"] >= GameConfig.HUT_WATER_PER_DAY:
			storage["FOOD"] -= GameConfig.HUT_FOOD_PER_DAY
			storage["WATER"] -= GameConfig.HUT_WATER_PER_DAY
			score += 1
		else:
			tiles[i] = Tile.HUT_DEAD

	# 2. Wet crops grow
	for i in tiles.size():
		if tiles[i] == Tile.FIELD and is_wet(i) and crop_age[i] < GameConfig.CROP_RIPE_DAYS:
			crop_age[i] += 1

	# 3. Trees may drop a stick on one of their four edges (one stick per edge at most)
	for i in tiles.size():
		if tiles[i] == Tile.TREE and _rng.randf() < GameConfig.STICK_DROP_CHANCE:
			sticks[_edge_of(i, _rng.randi() % 4)] = 1

	# 4. The agent. An idle day (no energy spent) costs no food or water and gives
	#    IDLE_REST_FACTOR x energy tomorrow; otherwise energy = food level.
	var idle := energy_spent_today <= 0.0
	energy_spent_today = 0.0
	day += 1
	if not idle:
		agent_food -= GameConfig.DAILY_DRAIN
		agent_water -= GameConfig.DAILY_DRAIN
		if agent_food <= 0.0 or agent_water <= 0.0:
			is_alive = false
			return "DIED"
	agent_energy = minf(GameConfig.MAX_ENERGY, agent_food * (GameConfig.IDLE_REST_FACTOR if idle else 1.0))
	if day >= GameConfig.MAX_DAYS:
		return "FINISHED"
	return "Day %d begins (score %d)%s" % [day, score, ", well rested" if idle else ""]
