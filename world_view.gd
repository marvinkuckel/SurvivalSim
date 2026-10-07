@tool
class_name WorldView
extends Node3D
# Renders the simulation state as simple 3D primitives. Contains no game logic.
# Only cells whose look changed are rebuilt. All spawned nodes are children of
# this node and are never saved to the scene.

const Tile = GameConfig.Tile

# One color per action: used for the target ring in the world and for the UI button
const ACTION_COLORS := {
	"collect_water": Color(0.25, 0.65, 1.00), "collect_stick": Color(0.85, 0.65, 0.35),
	"collect_wood": Color(0.95, 0.55, 0.15), "collect_stone": Color(0.78, 0.80, 0.85),
	"fell_tree": Color(0.20, 0.85, 0.45), "mine_stone": Color(1.00, 0.40, 0.25),
	"digout_plant": Color(0.60, 0.90, 0.20), "plant_crop_here": Color(0.45, 0.95, 0.55),
	"plant_crop_near_water": Color(0.20, 0.90, 0.85), "water_crop": Color(0.45, 0.50, 1.00),
	"farm_crop": Color(1.00, 0.85, 0.20), "eat": Color(1.00, 0.55, 0.55),
	"drink": Color(0.55, 0.80, 1.00), "deposit_inventory": Color(1.00, 0.75, 0.20),
	"rest": Color(1.00, 1.00, 1.00),
	"craft_hoe": Color(0.75, 0.50, 1.00), "craft_axe": Color(0.85, 0.45, 0.95),
	"craft_pickaxe": Color(0.65, 0.55, 1.00), "craft_wheelbarrow": Color(0.90, 0.60, 1.00),
	"build_hut": Color(1.00, 0.50, 0.70), "build_workbench": Color(0.90, 0.60, 0.40),
	"build_well": Color(0.40, 0.70, 0.90),
}

# Tile look: list of parts [color, y position, scale] built from unit boxes.
# The ground surface is at y = 0.
const PARTS := {
	Tile.WATER: [[Color(0.10, 0.45, 0.85), 0.0, Vector3(1.0, 0.06, 1.0)]],
	Tile.TREE: [[Color(0.40, 0.26, 0.12), 0.3, Vector3(0.18, 0.6, 0.18)],
			[Color(0.10, 0.45, 0.12), 0.85, Vector3(0.55, 0.6, 0.55)]],
	Tile.SMALL_ROCK: [[Color(0.60, 0.60, 0.60), 0.1, Vector3(0.4, 0.2, 0.4)]],
	Tile.BIG_ROCK: [[Color(0.35, 0.35, 0.38), 0.4, Vector3(0.8, 0.8, 0.8)]],
	Tile.PLANT: [[Color(0.55, 0.85, 0.20), 0.1, Vector3(0.3, 0.2, 0.3)]],
	Tile.FIELD: [[Color(0.40, 0.26, 0.14), 0.02, Vector3(0.95, 0.06, 0.95)]],
	Tile.LOG: [[Color(0.45, 0.30, 0.15), 0.15, Vector3(0.9, 0.3, 0.3)]],
	Tile.STONE_PILE: [[Color(0.55, 0.55, 0.58), 0.12, Vector3(0.6, 0.25, 0.6)]],
	Tile.HOME: [[Color(0.55, 0.33, 0.12), 0.35, Vector3(0.9, 0.7, 0.9)],
			[Color(0.85, 0.65, 0.10), 0.85, Vector3(1.0, 0.3, 1.0)]],
	Tile.HUT: [[Color(0.55, 0.33, 0.12), 0.3, Vector3(0.7, 0.6, 0.7)],
			[Color(0.70, 0.25, 0.15), 0.72, Vector3(0.8, 0.2, 0.8)]],
	Tile.HUT_DEAD: [[Color(0.25, 0.22, 0.20), 0.25, Vector3(0.7, 0.5, 0.7)]],
	Tile.WORKBENCH: [[Color(0.40, 0.30, 0.15), 0.2, Vector3(0.7, 0.4, 0.4)],
			[Color(0.60, 0.45, 0.25), 0.45, Vector3(0.85, 0.1, 0.55)]],
	Tile.WELL: [[Color(0.50, 0.50, 0.52), 0.2, Vector3(0.7, 0.4, 0.7)],
			[Color(0.10, 0.45, 0.85), 0.42, Vector3(0.5, 0.02, 0.5)]],
}

# Crop on top of a field, one entry per growth stage (the last one is ripe)
const CROP_STAGES := [
	[Color(0.55, 0.85, 0.20), 0.09, Vector3(0.12, 0.10, 0.12)],
	[Color(0.45, 0.80, 0.20), 0.13, Vector3(0.20, 0.20, 0.20)],
	[Color(0.35, 0.75, 0.20), 0.18, Vector3(0.28, 0.30, 0.28)],
	[Color(1.00, 0.75, 0.10), 0.22, Vector3(0.40, 0.38, 0.40)],
]
const WET_SOIL := [Color(0.25, 0.16, 0.09), 0.02, Vector3(0.95, 0.06, 0.95)]
const STICK_COLOR := Color(0.55, 0.38, 0.18)

# Grass: two alternating tile colors and a darker meadow that shows through the gaps
const GRASS_A := Color(0.40, 0.66, 0.27)
const GRASS_B := Color(0.37, 0.62, 0.25)
const MEADOW := Color(0.27, 0.46, 0.19)

var _shown := PackedInt32Array()  # look key of every cell as currently displayed
var _nodes: Dictionary = {}       # cell index -> container node of the tile
var _sticks: Dictionary = {}      # edge index -> stick node
var _rings: Dictionary = {}       # action -> ring marker
var _agent: MeshInstance3D


# Clears the old world and creates ground, agent and rings. Tiles appear on the first sync.
func build(core: SimulationCore) -> void:
	for child in get_children():
		remove_child(child)  # remove immediately, so new nodes never clash with old names
		child.queue_free()
	_nodes.clear()
	_sticks.clear()
	_rings.clear()
	_shown.resize(core.tiles.size())
	_shown.fill(-1)
	_build_ground(core.width, core.height)

	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	_agent = _spawn(self, sphere, Vector3.ZERO, Color(1.0, 0.84, 0.0))

	# One ring per action, each slightly wider so rings on the same tile stay visible
	var ring_index := 0
	for action: String in ACTION_COLORS:
		if action == "rest": continue
		var torus := TorusMesh.new()
		torus.inner_radius = 0.28 + ring_index * 0.011
		torus.outer_radius = torus.inner_radius + 0.045
		_rings[action] = _spawn(self, torus, Vector3.ZERO, ACTION_COLORS[action], Vector3(1, 0.01, 1), true, false)
		ring_index += 1


# Updates changed tiles, sticks, the agent and the target rings of all possible actions.
func sync_with(core: SimulationCore, plans: Dictionary) -> void:
	for i in core.tiles.size():
		var key := core.tiles[i] * 32
		if core.tiles[i] == Tile.FIELD:
			key += core.crop_age[i] + (16 if core.is_wet(i) else 0)
		if key != _shown[i]:
			_shown[i] = key
			_set_tile(core, i)

	for e in core.sticks.size():
		var present := core.sticks[e] == 1
		if present and not _sticks.has(e):
			var c := core.edge_center(e)
			var size := Vector3(0.07, 0.07, 0.6) if e < core.v_edge_count else Vector3(0.6, 0.07, 0.07)
			_sticks[e] = _spawn(self, BoxMesh.new(), Vector3(c.x, 0.06, c.y), STICK_COLOR, size)
		elif not present and _sticks.has(e):
			_sticks[e].queue_free()
			_sticks.erase(e)

	_agent.position = Vector3(core.agent_pos.x, 0.6, core.agent_pos.y)

	for action: String in _rings:
		var plan: Dictionary = plans[action]
		var ring: MeshInstance3D = _rings[action]
		ring.visible = plan["ok"] and plan["has_target"]
		if ring.visible:
			ring.position = Vector3(plan["target"].x, 0.07, plan["target"].y)


# Replaces the visuals of one cell.
func _set_tile(core: SimulationCore, i: int) -> void:
	if _nodes.has(i):
		remove_child(_nodes[i])
		_nodes[i].queue_free()
		_nodes.erase(i)
	var type := core.tiles[i]
	if type == Tile.EMPTY: return

	var holder := Node3D.new()
	holder.position = Vector3(core.pos_of(i).x, 0.0, core.pos_of(i).y)
	add_child(holder)
	_nodes[i] = holder

	var parts: Array = PARTS[type].duplicate()
	if type == Tile.FIELD:
		if core.is_wet(i):
			parts[0] = WET_SOIL
		parts.append(CROP_STAGES[mini(core.crop_age[i], CROP_STAGES.size() - 1)])
	for part: Array in parts:
		_spawn(holder, BoxMesh.new(), Vector3(0, part[1], 0), part[0], part[2])


# Checkered grass tiles (one per cell) on top of a huge meadow plane.
func _build_ground(width: int, height: int) -> void:
	var meadow := PlaneMesh.new()
	meadow.size = Vector2(400, 400)
	_spawn(self, meadow, Vector3((width - 1) / 2.0, -0.11, (height - 1) / 2.0), MEADOW, Vector3.ONE, false, false)
	for x in width:
		for y in height:
			var color := GRASS_A if (x + y) % 2 == 0 else GRASS_B
			_spawn(self, BoxMesh.new(), Vector3(x, -0.05, y), color, Vector3(0.97, 0.1, 0.97), false, false)


func _spawn(parent: Node, mesh: Mesh, pos: Vector3, color: Color, mesh_scale := Vector3.ONE, unshaded := false, casts_shadow := true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.scale = mesh_scale
	if not casts_shadow:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
