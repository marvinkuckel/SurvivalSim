@tool
extends Node3D
# Entry point. Holds the editor settings, generates the world and connects the
# simulation core, the 3D view and the HUD (the HUD buttons trigger the actions).

const Tile = GameConfig.Tile

@onready var view: WorldView = $WorldView
@onready var hud: Hud = $HUD

@export_category("0. Generation Mode")
@export var live_update: bool = true
@export var generate_world_now: bool = false:  # acts as a "generate" button
	set(_v): generate_world()

@export_category("1. Distance Monitor (Live, in steps, -1 = unreachable)")
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
var is_resetting := false  # true while the end-of-run pause is running


func _ready() -> void:
	if not hud.action_pressed.is_connected(_on_action_pressed):
		hud.action_pressed.connect(_on_action_pressed)
	generate_world()


func _on_setting_changed() -> void:
	if live_update:
		generate_world()


# Generates a fresh world and starts a new simulation on it.
func generate_world() -> void:
	if not is_node_ready(): return  # exported setters also fire while the scene loads

	var tiles := WorldGenerator.generate({
		"width": map_width,
		"height": map_height,
		"seed": world_seed,
		"percent_empty": percent_map_empty,
		"weights": {
			Tile.WATER: weight_water, Tile.PLANT: weight_plants, Tile.TREE: weight_trees,
			Tile.SMALL_ROCK: weight_small_rocks, Tile.BIG_ROCK: weight_big_rocks,
		},
		"shaping": {"water": water_shaping, "forest": forest_shaping, "mountain": mountain_shaping},
	})
	var start := WorldGenerator.find_start_cell(tiles, map_width, map_height)
	sim_core = SimulationCore.new(tiles, map_width, map_height, start, world_seed)
	view.build(sim_core)
	_sync()


# Pushes the current simulation state to the view, the monitor and the HUD.
func _sync(message := "") -> void:
	var plans := sim_core.get_plans()
	view.sync_with(sim_core, plans)
	dist_to_closest_water = sim_core.steps_to([Tile.WATER, Tile.WELL])
	dist_to_closest_plant = sim_core.steps_to([Tile.PLANT])
	dist_to_closest_tree = sim_core.steps_to([Tile.TREE])
	dist_to_closest_small_rock = sim_core.steps_to([Tile.SMALL_ROCK])
	dist_to_closest_big_rock = sim_core.steps_to([Tile.BIG_ROCK])
	hud.refresh(sim_core, plans, message)


# A dock button was pressed (disabled in the editor).
func _on_action_pressed(action: String) -> void:
	if Engine.is_editor_hint() or is_resetting: return

	var message := sim_core.perform(action)
	if message == "DIED" or message == "FINISHED" or message == "DEAD":
		_end_run(message)
	else:
		print("[Simulation Event]: ", message)
		_sync(message)


# Short pause after the run ended (death or day limit), then everything restarts.
func _end_run(reason: String) -> void:
	is_resetting = true
	var text := "Day limit reached!" if reason == "FINISHED" else "The agent died on day %d!" % sim_core.day
	hud.refresh(sim_core, sim_core.get_plans(), "%s Final score: %d" % [text, sim_core.score], true)
	await get_tree().create_timer(2.5).timeout
	sim_core.reset()
	view.build(sim_core)
	is_resetting = false
	_sync("New run started.")
