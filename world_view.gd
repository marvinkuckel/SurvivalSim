@tool
class_name WorldView
extends Node3D
# Renders the simulation state as simple 3D primitives. Contains no game logic.
# All spawned nodes are children of this node and are never saved to the scene.

# Ring/UI color per tile type (rings mark the closest target of each type)
const TYPE_COLORS := {
	"WATER": Color(0.0, 0.6, 1.0),
	"PLANT": Color(0.33, 1.0, 0.0),
	"TREE": Color(0.0, 1.0, 0.4),
	"SMALL_ROCK": Color(0.8, 0.8, 0.8),
	"BIG_ROCK": Color(1.0, 0.4, 0.0),
	"HUT": Color(1.0, 0.8, 0.0),
}

# Block look per tile type: [color, y position, scale]. The ground surface is at y = 0.
const BLOCKS := {
	"WATER": [Color(0.10, 0.45, 0.85), 0.0, Vector3(1.0, 0.06, 1.0)],
	"PLANT": [Color(0.55, 0.85, 0.20), 0.05, Vector3(0.3, 0.1, 0.3)],
	"TREE": [Color(0.10, 0.45, 0.12), 0.6, Vector3(0.3, 1.2, 0.3)],
	"SMALL_ROCK": [Color(0.6, 0.6, 0.6), 0.1, Vector3(0.4, 0.2, 0.4)],
	"BIG_ROCK": [Color(0.35, 0.35, 0.38), 0.4, Vector3(0.8, 0.8, 0.8)],
	"HUT": [Color(0.55, 0.33, 0.12), 0.35, Vector3(0.9, 0.7, 0.9)],
}

# Grass: two alternating tile colors and a darker meadow that shows through the gaps
const GRASS_A := Color(0.40, 0.66, 0.27)
const GRASS_B := Color(0.37, 0.62, 0.25)
const MEADOW := Color(0.27, 0.46, 0.19)

var _plants: Dictionary = {}  # Vector2i -> plant block (to remove it when harvested)
var _rings: Dictionary = {}   # tile type -> ring marker
var _agent: MeshInstance3D


# Clears the old world and spawns the ground, all blocks, the hut, the agent and the rings.
func build(cells: Dictionary, hut_pos: Vector2i, width: int, height: int) -> void:
	for child in get_children():
		remove_child(child)  # remove immediately, so new nodes never clash with old names
		child.queue_free()
	_plants.clear()
	_rings.clear()
	_build_ground(width, height)

	for pos: Vector2i in cells:
		var block := _spawn_block(cells[pos], pos)
		if cells[pos] == "PLANT":
			_plants[pos] = block
	_spawn_block("HUT", hut_pos)

	var sphere := SphereMesh.new()
	sphere.radius = 0.25
	sphere.height = 0.5
	_agent = _spawn(sphere, Vector3.ZERO, Color(1.0, 0.84, 0.0))

	for type: String in TYPE_COLORS:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.52
		_rings[type] = _spawn(torus, Vector3.ZERO, TYPE_COLORS[type], Vector3(1, 0.01, 1), true, false)


# Updates agent position, harvested plants and target rings.
func sync_with(core: SimulationCore) -> void:
	_agent.position = Vector3(core.agent_pos.x, 0.6, core.agent_pos.y)

	for pos: Vector2i in _plants.keys():
		if not core.object_locations["PLANT"].has(pos):
			_plants[pos].queue_free()
			_plants.erase(pos)

	for type: String in _rings:
		var target: Vector2i = core.get_closest_interaction(type)["pos"]
		var ring: MeshInstance3D = _rings[type]
		ring.visible = target != SimulationCore.NO_TILE and target != core.agent_pos
		ring.position = Vector3(target.x, 0.07, target.y)


# Checkered grass tiles (one per cell) on top of a huge meadow plane.
func _build_ground(width: int, height: int) -> void:
	var meadow := PlaneMesh.new()
	meadow.size = Vector2(400, 400)
	_spawn(meadow, Vector3((width - 1) / 2.0, -0.11, (height - 1) / 2.0), MEADOW, Vector3.ONE, false, false)
	for x in width:
		for y in height:
			var color := GRASS_A if (x + y) % 2 == 0 else GRASS_B
			_spawn(BoxMesh.new(), Vector3(x, -0.05, y), color, Vector3(0.97, 0.1, 0.97), false, false)


func _spawn_block(type: String, pos: Vector2i) -> MeshInstance3D:
	var spec: Array = BLOCKS[type]
	return _spawn(BoxMesh.new(), Vector3(pos.x, spec[1], pos.y), spec[0], spec[2])


func _spawn(mesh: Mesh, pos: Vector3, color: Color, mesh_scale := Vector3.ONE, unshaded := false, casts_shadow := true) -> MeshInstance3D:
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
	add_child(node)
	return node
