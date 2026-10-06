@tool
extends Node3D
# Entry point. Holds the editor settings, generates the world and routes
# input between the simulation core, the 3D view and the HUD.

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $HUD

@export_category("0. Generation Mode")
@export var live_update: bool = true
@export var generate_world_now: bool = false:  # acts as a "generate" button
	set(_v): generate_world()

@export_category("1. Distance Monitor (Live)")
@export var dist_to_closest_water: float = 0.0
@export var dist_to_closest_plant: float = 0.0
@export var dist_to_closest_tree: float = 0.0
@export var dist_to_closest_small_rock: float = 0.0
@export var dist_to_closest_big_rock: float = 0.0

@export_category("2. World Base")
@export var map_width: int = 16:
	set(v): map_width = v; _on_setting_changed()
@export var map_height: int = 16:
	set(v): map_height = v; _on_setting_changed()
@export var world_seed: int = 0:
	set(v): world_seed = v; _on_setting_changed()

@export_category("3. Free Space")
@export_range(0.0, 100.0, 1.0) var percent_map_empty: float = 40.0:
	set(v): percent_map_empty = v; _on_setting_changed()

@export_category("4. Object Weights")
@export var weight_water: float = 1.0:
	set(v): weight_water = v; _on_setting_changed()
@export var weight_plants: float = 1.0:
	set(v): weight_plants = v; _on_setting_changed()
@export var weight_trees: float = 1.0:
	set(v): weight_trees = v; _on_setting_changed()
@export var weight_small_rocks: float = 1.0:
	set(v): weight_small_rocks = v; _on_setting_changed()
@export var weight_big_rocks: float = 1.0:
	set(v): weight_big_rocks = v; _on_setting_changed()

@export_category("5. Terrain Shaping (Noise Frequency)")
@export_range(0.01, 0.2, 0.001) var forest_shaping: float = 0.05:
	set(v): forest_shaping = v; _on_setting_changed()
@export_range(0.01, 0.2, 0.001) var water_shaping: float = 0.05:
	set(v): water_shaping = v; _on_setting_changed()
@export_range(0.01, 0.2, 0.001) var mountain_shaping: float = 0.05:
	set(v): mountain_shaping = v; _on_setting_changed()

var sim_core: SimulationCore
var cells: Dictionary = {}  # generated world: Vector2i -> tile type
var is_resetting := false   # true while the death/respawn pause is running


func _ready() -> void:
	generate_world()


func _on_setting_changed() -> void:
	if live_update:
		generate_world()


# Generates a fresh world and starts a new simulation on it.
func generate_world() -> void:
	if not is_node_ready(): return  # exported setters also fire while the scene loads

	cells = WorldGenerator.generate({
		"width": map_width,
		"height": map_height,
		"seed": world_seed,
		"percent_empty": percent_map_empty,
		"weights": {
			"WATER": weight_water, "PLANT": weight_plants, "TREE": weight_trees,
			"SMALL_ROCK": weight_small_rocks, "BIG_ROCK": weight_big_rocks,
		},
		"shaping": {"water": water_shaping, "forest": forest_shaping, "mountain": mountain_shaping},
	})
	var start := WorldGenerator.find_start_cell(cells, map_width, map_height)
	sim_core = SimulationCore.new(cells, start)
	view.build(cells, start)
	_sync()


# Pushes the current simulation state to the view, the monitor and the HUD.
func _sync(message := "") -> void:
	view.sync_with(sim_core)
	dist_to_closest_water = sim_core.get_closest_interaction("WATER")["distance"]
	dist_to_closest_plant = sim_core.get_closest_interaction("PLANT")["distance"]
	dist_to_closest_tree = sim_core.get_closest_interaction("TREE")["distance"]
	dist_to_closest_small_rock = sim_core.get_closest_interaction("SMALL_ROCK")["distance"]
	dist_to_closest_big_rock = sim_core.get_closest_interaction("BIG_ROCK")["distance"]
	hud.refresh(sim_core, message)


# Keys 1-4 trigger the agent actions (disabled in the editor).
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if Engine.is_editor_hint() or is_resetting or key == null or not key.pressed or key.echo:
		return

	var message := ""
	match key.keycode:
		KEY_1: message = sim_core.collect_water()
		KEY_2: message = sim_core.harvest_plant()
		KEY_3: message = sim_core.store_inventory_in_hut()
		KEY_4: message = sim_core.wait_and_rest()
		_: return

	hud.flash(key.keycode - KEY_1)
	if message == "DEAD" or message == "DIED":
		_respawn()
	else:
		print("[Simulation Event]: ", message)
		_sync(message)


# Short pause after death, then the whole simulation (agent and world) restarts.
func _respawn() -> void:
	is_resetting = true
	hud.refresh(sim_core, "The agent died.", true)
	await get_tree().create_timer(1.5).timeout
	sim_core.reset()
	view.build(cells, sim_core.spawn_point)
	is_resetting = false
	_sync("Respawned.")
