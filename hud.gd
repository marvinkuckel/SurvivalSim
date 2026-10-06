@tool
class_name Hud
extends CanvasLayer
# Text overlay: agent stats, storage, action menu and the latest event message.

# Action menu entries in key order (1-4): [label, tile type used for the color]
const MENU := [
	["Collect Water", "WATER"],
	["Harvest Plant", "PLANT"],
	["Deposit Items", "HUT"],
	["Rest / Wait", "REST"],
]

@onready var _label: RichTextLabel = $Panel/Text

var _core: SimulationCore
var _message := ""
var _respawning := false
var _flashed := -1  # menu index of the key that was just pressed


# Redraws the overlay with the current simulation state.
func refresh(core: SimulationCore, message := "", respawning := false) -> void:
	_core = core
	_message = message
	_respawning = respawning
	_render()


# Briefly highlights a menu entry to confirm a key press.
func flash(index: int) -> void:
	_flashed = index
	_render()
	await get_tree().create_timer(0.12).timeout
	_flashed = -1
	_render()


func _render() -> void:
	if _core == null: return

	var status := "[color=green]ALIVE[/color]"
	if _respawning:
		status = "[color=orange]RESPAWNING...[/color]"
	elif not _core.is_alive:
		status = "[color=red]DEAD[/color]"

	var text := "=== AGENT STATUS (%s) ===\n" % status
	text += "Position: (%d, %d)\n" % [_core.agent_pos.x, _core.agent_pos.y]
	text += "Energy: %.1f / %.0f\n" % [_core.agent_energy, SimulationCore.MAX_STAT]
	text += "Food: %.1f / %.0f\n" % [_core.agent_food, SimulationCore.MAX_STAT]
	text += "Water: %.1f / %.0f\n" % [_core.agent_water, SimulationCore.MAX_STAT]
	text += "Inventory: %s (Max: %d)\n\n" % [str(_core.inventory), SimulationCore.INVENTORY_LIMIT]

	var s := _core.storage
	text += "=== CENTRAL STORAGE (Cap: %d) ===\n" % _core.get_max_storage_capacity()
	text += "Water: %d | Food: %d\nWood: %d | Stone: %d\n\n" % [s["WATER"], s["FOOD"], s["WOOD"], s["STONE"]]
	text += "=== STRUCTURES ===\nHuts built: %d\n\n" % _core.buildings["HUT"]

	text += "=== AVAILABLE ACTIONS ===\n"
	for i in MENU.size():
		var color: Color = WorldView.TYPE_COLORS.get(MENU[i][1], Color.WHITE)
		var marker := "[color=lime]> [/color]" if i == _flashed else "   "
		text += "%s[color=#%s]%d: %s[/color]\n" % [marker, color.to_html(false), i + 1, MENU[i][0]]

	_label.text = text + "\n" + _message
