@tool
extends Node3D

#region export attributes
@export_category("0. GENERATION MODE")
@export var live_update: bool = true
@export var generate_world_now: bool = false:
	set(v): generate_world()

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
@export var world_seed: int = 42:
	set(v): world_seed = v; _on_setting_changed()

@export_category("3. Agent Area (Survival Guarantee)")
@export_range(0, 100, 1.0) var percent_map_empty: float = 50.0:
	set(v): percent_map_empty = v; _on_setting_changed()

@export_category("4. Resource Ratio (Weights)")
@export_range(0, 10, 1.0) var weight_water: float = 2.0:
	set(v): weight_water = v; _on_setting_changed()
@export_range(0, 10, 1.0) var weight_plants: float = 1.0:
	set(v): weight_plants = v; _on_setting_changed()
@export_range(0, 10, 1.0) var weight_trees: float = 1.0:
	set(v): weight_trees = v; _on_setting_changed()
@export_range(0, 10, 1.0) var weight_small_rocks: float = 1.0:
	set(v): weight_small_rocks = v; _on_setting_changed()
@export_range(0, 10, 1.0) var weight_big_rocks: float = 1.0:
	set(v): weight_big_rocks = v; _on_setting_changed()

@export_category("5. Natural Scattering (Noise)")
@export_range(0.001, 0.5) var forest_shaping: float = 0.08:
	set(v): forest_shaping = v; _on_setting_changed()
@export_range(0.001, 0.5) var water_shaping: float = 0.05:
	set(v): water_shaping = v; _on_setting_changed()
@export_range(0.001, 0.5) var mountain_shaping: float = 0.1:
	set(v): mountain_shaping = v; _on_setting_changed()
#endregion

# Central Dashboard Colors synced perfectly with 3D Torus Rings
const COLORS = {
	"WATER": Color(0.0, 0.297, 0.513),
	"PLANT": Color(0.0, 1.0, 0.0),
	"TREE": Color(0.236, 0.118, 0.003, 1.0),
	"SMALL_ROCK": Color(0.4, 0.4, 0.4),
	"BIG_ROCK": Color(0.2, 0.2, 0.2),
	"HUT": Color(1.0, 0.8, 0.5),
	"REST": Color(1.0, 1.0, 1.0)
}

var sim_core: SimulationCore
var last_occupied_cells: Dictionary = {}
var active_highlight_key: String = ""
var is_resetting: bool = false

func _on_setting_changed():
	if live_update: generate_world()

func _ready():
	generate_world()

func _unhandled_key_input(event: InputEvent):
	if Engine.is_editor_hint() or is_resetting: return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo(): return
	var log_msg: String = ""
	match event.keycode:
		KEY_1: log_msg = sim_core.collect_water(); flash_hud_element("1")
		KEY_2: log_msg = sim_core.harvest_plant(); flash_hud_element("2")
		KEY_3: log_msg = sim_core.store_inventory_in_hut(); flash_hud_element("3")
		KEY_4: log_msg = sim_core.wait_and_rest(); flash_hud_element("4")
	if log_msg == "DEAD" or log_msg == "DIED": trigger_death_reset()
	elif not log_msg.is_empty():
		update_feedback_text(log_msg, false)
		sync_3d_world_with_logic()

func flash_hud_element(key: String):
	active_highlight_key = key
	update_ui_display()
	await Engine.get_main_loop().create_timer(0.12).timeout
	active_highlight_key = ""
	update_ui_display()

func update_feedback_text(msg: String, is_error: bool):
	var feedback_label = get_node_or_null("CanvasLayer/UI/PanelContainer/VBoxContainer/StorageStatsLabel") as RichTextLabel
	if feedback_label:
		# Will be appended securely dynamically inside UI text builder
		pass
	# Fallback console printing
	print("[Simulation Event]: ", msg)

func trigger_death_reset():
	is_resetting = true
	sim_core.is_alive = false
	update_ui_display()
	await Engine.get_main_loop().create_timer(1.5).timeout
	sim_core.reset_agent()
	is_resetting = false
	sync_3d_world_with_logic()

func generate_world():
	if not is_inside_tree(): return 
	for child in get_children():
		if child is MeshInstance3D: child.queue_free()
	var params = {
		"width": map_width, "height": map_height, "seed": world_seed, "percent_empty": percent_map_empty,
		"weights": {"water": weight_water, "plants": weight_plants, "trees": weight_trees, "small_rocks": weight_small_rocks, "big_rocks": weight_big_rocks},
		"shaping": {"water": water_shaping, "forest": forest_shaping, "mountain": mountain_shaping}
	}
	var occupied_cells = WorldGenerator.generate(params)
	last_occupied_cells = occupied_cells
	var start_pos = WorldGenerator.find_start_cell(occupied_cells, map_width, map_height)
	sim_core = SimulationCore.new(occupied_cells, start_pos)
	for pos in occupied_cells: spawn_3d_block(pos, occupied_cells[pos])
	spawn_hut_visual(start_pos)
	create_agent_3d()
	sync_3d_world_with_logic()

func spawn_3d_block(pos: Vector2i, type: String):
	var box = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var mat = StandardMaterial3D.new()
	match type:
		"WATER": mat.albedo_color = COLORS["WATER"]; box.position = Vector3(pos.x, -0.2, pos.y); box.scale = Vector3(1.0, 0.1, 1.0)
		"PLANT": mat.albedo_color = COLORS["PLANT"]; box.position = Vector3(pos.x, 0.05, pos.y); box.scale = Vector3(0.1, 0.5, 0.1)
		"TREE": mat.albedo_color = COLORS["TREE"]; box.position = Vector3(pos.x, 0.6, pos.y); box.scale = Vector3(0.3, 1.2, 0.3)
		"SMALL_ROCK": mat.albedo_color = COLORS["SMALL_ROCK"]; box.position = Vector3(pos.x, 0.1, pos.y); box.scale = Vector3(0.4, 0.2, 0.4)
		"BIG_ROCK": mat.albedo_color = COLORS["BIG_ROCK"]; box.position = Vector3(pos.x, 0.4, pos.y); box.scale = Vector3(0.8, 0.8, 0.8)
	box.material_override = mat
	box.name = "Block_" + str(pos.x) + "_" + str(pos.y)
	add_child(box)

func spawn_hut_visual(pos: Vector2i):
	var hut = MeshInstance3D.new()
	hut.name = "Hut_" + str(pos.x) + "_" + str(pos.y)
	hut.mesh = BoxMesh.new()
	hut.scale = Vector3(0.9, 0.7, 0.9)
	hut.position = Vector3(pos.x, 0.35, pos.y)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.3, 0.1)
	hut.material_override = mat
	add_child(hut)

func create_agent_3d():
	var agent_node = MeshInstance3D.new()
	agent_node.name = "Agent3D"
	agent_node.mesh = SphereMesh.new()
	agent_node.mesh.radius = 0.25
	agent_node.mesh.height = 0.5
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.84, 0.0)
	agent_node.material_override = mat
	add_child(agent_node)

func sync_3d_world_with_logic():
	if not sim_core: return
	var agent_node = get_node_or_null("Agent3D")
	if agent_node: agent_node.position = Vector3(sim_core.agent_pos.x, 0.6, sim_core.agent_pos.y)
	for child in get_children():
		if child.name.begins_with("Block_"):
			var parts = child.name.split("_")
			var pos = Vector2i(int(parts[1]), int(parts[2]))
			if last_occupied_cells.get(pos) == "PLANT" and not sim_core.object_locations["PLANT"].has(pos):
				remove_child(child); child.queue_free()
	for child in get_children():
		if child.name.begins_with("Ring_"): remove_child(child); child.queue_free()
	for type in COLORS:
		if type == "REST": 
			continue
		var target_info = sim_core.get_closest_interaction(type)
		var target_pos = target_info["pos"]
		if target_pos == Vector2i(-1, -1) or target_pos == sim_core.agent_pos: 
			continue
		var ring = MeshInstance3D.new()
		ring.name = "Ring_" + type
		ring.mesh = TorusMesh.new()
		ring.mesh.inner_radius = 0.45; ring.mesh.outer_radius = 0.52; ring.scale = Vector3(1.0, 0.01, 1.0); ring.position = Vector3(target_pos.x, 0.02, target_pos.y)
		var mat = StandardMaterial3D.new()
		ring.material_override = mat; mat.albedo_color = COLORS[type]["color"]; mat.unshaded = true
		add_child(ring)
	dist_to_closest_water = sim_core.get_closest_interaction("WATER")["distance"]
	dist_to_closest_plant = sim_core.get_closest_interaction("PLANT")["distance"]
	dist_to_closest_tree = sim_core.get_closest_interaction("TREE")["distance"]
	dist_to_closest_small_rock = sim_core.get_closest_interaction("SMALL_ROCK")["distance"]
	dist_to_closest_big_rock = sim_core.get_closest_interaction("BIG_ROCK")["distance"]
	update_ui_display()

func update_ui_display():
	if sim_core == null: return
	
	var stats_node = get_node_or_null("CanvasLayer/UI/PanelContainer/VBoxContainer/AgentStatsLabel") as RichTextLabel
	var storage_node = get_node_or_null("CanvasLayer/UI/PanelContainer/VBoxContainer/StorageStatsLabel") as RichTextLabel
	var actions_node = get_node_or_null("CanvasLayer/UI/PanelContainer/VBoxContainer/ActionMenuLabel") as RichTextLabel
	var panel = get_node_or_null("CanvasLayer/UI/PanelContainer") as PanelContainer
	
	# Zwingt das HUD, groß genug zu bleiben
	if panel: panel.custom_minimum_size = Vector2(340, 420)
	if stats_node == null or storage_node == null or actions_node: return
	
	stats_node.bbcode_enabled = true
	storage_node.bbcode_enabled = true
	
	# 1. AGENT STATUS TEXT
	var alive_str = "[color=green]ALIVE[/color]" if sim_core.is_alive else "[color=red]DEAD[/color]"
	if is_resetting: alive_str = "[color=orange]RESPAWNING...[/color]"
	
	stats_node.text = "=== AGENT STATUS (" + alive_str + ") ===\n" + \
		"Position: (" + str(sim_core.agent_pos.x) + ", " + str(sim_core.agent_pos.y) + ")\n" + \
		"Energy: " + str(snapped(sim_core.agent_energy, 0.1)) + " / 100\n" + \
		"Satiety (Food): " + str(snapped(sim_core.agent_food, 0.1)) + " / 100\n" + \
		"Hydration (Water): " + str(snapped(sim_core.agent_water, 0.1)) + " / 100\n" + \
		"Inventory: " + str(sim_core.inventory) + " (Max: " + str(sim_core.INVENTORY_LIMIT) + ")"
		
	# 2. STORAGE TEXT
	var cap_str = str(sim_core.get_max_storage_capacity())
	var storage_text = "\n=== CENTRAL STORAGE (Cap: " + cap_str + ") ===\n" + \
		"Water: " + str(sim_core.storage["WATER"]) + " | Food: " + str(sim_core.storage["FOOD"]) + "\n" + \
		"Wood: " + str(sim_core.storage["WOOD"]) + " | Stone: " + str(sim_core.storage["STONE"]) + "\n\n" + \
		"=== STRUCTURES ===\n" + \
		"Huts built: " + str(sim_core.buildings["HUT"]) + "\n\n"
		
	# 3. INTERAKTIVE HOTKEY LISTE (Zentral gesteuerte Synchro-Farben)
	var dot1 = "  "; var dot2 = "  "; var dot3 = "  "; var dot4 = "  "
	if active_highlight_key == "1": dot1 = "[color=lime]● [/color]"
	if active_highlight_key == "2": dot2 = "[color=lime]● [/color]"
	if active_highlight_key == "3": dot3 = "[color=lime]● [/color]"
	if active_highlight_key == "4": dot4 = "[color=lime]● [/color]"
	
	var line1 = dot1 + "[color=" + COLORS["WATER"]["hex"] + "]1: Collect Water[/color]\n"
	var line2 = dot2 + "[color=" + COLORS["PLANT"]["hex"] + "]2: Harvest Plant[/color]\n"
	var line3 = dot3 + "[color=" + COLORS["HUT"]["hex"] + "]3: Deposit Items[/color]\n"
	var line4 = dot4 + "[color=" + COLORS["REST"]["hex"] + "]4: Rest / Wait[/color]"
	
	var menu_text = "=== AVAILABLE ACTIONS ===\n" + line1 + line2 + line3 + line4
	
	# 4. SYSTEM EVENT LOG (Sicher am Ende des Textes angehängt!)
	var feedback_text = ""
	var feedback_label = get_node_or_null("%FeedbackLabel") as Label
	if feedback_label:
		feedback_text = feedback_label.text
		
	# Wir klatschen alles in das verlässliche Storage-Label
	storage_node.text = storage_text + menu_text + "\n" + feedback_text
