@tool
class_name Hud
extends CanvasLayer
# Game-style overlay: agent bars + inventory (top left), storage (top right),
# action bar (bottom) and a message toast. The UI is built once in code and
# only updated afterwards.

# Action bar entries in key order (1-4): [label, tile type used for the color]
const MENU := [
	["Collect Water", "WATER"],
	["Harvest Plant", "PLANT"],
	["Deposit Items", "HUT"],
	["Rest / Wait", "REST"],
]

const PANEL_BG := Color(0.06, 0.08, 0.10, 0.82)
const TEXT := Color("#eef2f6")
const MUTED := Color("#8d99a6")
const GOOD := Color("#7ccf4a")
const WARN := Color("#f0a030")
const BAD := Color("#e5534b")
const STAT_COLORS := {"Energy": Color("#f5b82e"), "Food": Color("#7ccf4a"), "Water": Color("#3fa7f5")}
const ITEM_COLORS := {"WATER": Color("#3fa7f5"), "FOOD": Color("#7ccf4a"), "WOOD": Color("#b98a5a"), "STONE": Color("#a0a7ae")}
const ITEM_NAMES := {"WATER": "Water", "FOOD": "Food", "WOOD": "Wood", "STONE": "Stone"}

var _core: SimulationCore
var _message := ""
var _respawning := false
var _flashed := -1  # action bar index of the key that was just pressed

var _bold: FontVariation
var _status: Label
var _pos_label: Label
var _bars: Dictionary = {}           # stat name -> ProgressBar
var _stat_values: Dictionary = {}    # stat name -> Label
var _inventory_title: Label
var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _huts: Label
var _capacity: Label
var _storage_values: Dictionary = {} # resource -> Label
var _keys: Array[Dictionary] = []    # action bar entries: {panel, normal, flash}
var _toast: PanelContainer
var _toast_label: Label


func _ready() -> void:
	for child in get_children():
		child.queue_free()  # drop leftovers after a script reload in the editor

	# One shared theme: system font with fallbacks, plus a bold variant for titles
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Inter", "Roboto", "Helvetica Neue", "Arial"])
	_bold = FontVariation.new()
	_bold.base_font = font
	_bold.variation_embolden = 0.5
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15

	var root := Control.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_agent_panel(root)
	_build_storage_panel(root)
	_build_action_bar(root)
	_build_toast(root)
	_update()


# Redraws the overlay with the current simulation state.
func refresh(core: SimulationCore, message := "", respawning := false) -> void:
	_core = core
	_message = message
	_respawning = respawning
	_update()


# Briefly highlights an action bar entry to confirm a key press.
func flash(index: int) -> void:
	_flashed = index
	_update()
	await get_tree().create_timer(0.12).timeout
	_flashed = -1
	_update()


# ==============================================================================
# UI CONSTRUCTION
# ==============================================================================

func _build_agent_panel(root: Control) -> void:
	var box := _panel(root, 280)
	box.get_parent().position = Vector2(16, 16)

	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(_label("AGENT", 17, TEXT, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_status = _label("", 13, GOOD, true)
	header.add_child(_status)

	_pos_label = _label("", 13, MUTED)
	box.add_child(_pos_label)
	box.add_child(HSeparator.new())

	# Stat rows: name | bar | value
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for stat: String in STAT_COLORS:
		grid.add_child(_label(stat, 14, MUTED))
		var bar := ProgressBar.new()
		bar.max_value = SimulationCore.MAX_STAT
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(110, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.add_theme_stylebox_override("background", _box(Color(1, 1, 1, 0.08), 6, Color.TRANSPARENT, 0))
		bar.add_theme_stylebox_override("fill", _box(STAT_COLORS[stat], 6, Color.TRANSPARENT, 0))
		grid.add_child(bar)
		var value := _label("", 13)
		value.custom_minimum_size.x = 64
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_bars[stat] = bar
		_stat_values[stat] = value

	box.add_child(HSeparator.new())
	_inventory_title = _label("", 13, MUTED)
	box.add_child(_inventory_title)
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 8)
	box.add_child(slots)
	for i in SimulationCore.INVENTORY_LIMIT:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(80, 36)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var item_label := _label("", 13, TEXT, true)
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(item_label)
		slots.add_child(slot)
		_slots.append(slot)
		_slot_labels.append(item_label)


func _build_storage_panel(root: Control) -> void:
	var box := _panel(root, 220)
	var panel := box.get_parent() as Control
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -236
	panel.offset_right = -16
	panel.offset_top = 16

	var header := HBoxContainer.new()
	box.add_child(header)
	header.add_child(_label("BASE", 17, TEXT, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_huts = _label("", 13, WARN, true)
	header.add_child(_huts)

	box.add_child(HSeparator.new())
	_capacity = _label("", 13, MUTED)
	box.add_child(_capacity)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for key: String in ITEM_COLORS:
		var name_label := _label(ITEM_NAMES[key], 14, ITEM_COLORS[key])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var value := _label("", 14)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_storage_values[key] = value


func _build_action_bar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_top = -16
	bar.offset_bottom = -16
	root.add_child(bar)

	for i in MENU.size():
		var color: Color = WorldView.TYPE_COLORS.get(MENU[i][1], Color.WHITE)
		var normal := _box(PANEL_BG, 10, Color(color, 0.35), 8, 10)
		var flash_style := _box(Color(color, 0.40), 10, color, 8, 10)
		var entry := PanelContainer.new()
		entry.add_theme_stylebox_override("panel", normal)
		bar.add_child(entry)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		entry.add_child(row)

		# Key cap with the key number
		var cap := PanelContainer.new()
		cap.custom_minimum_size = Vector2(28, 28)
		cap.add_theme_stylebox_override("panel", _box(color, 6, Color.TRANSPARENT, 0))
		var number := _label(str(i + 1), 15, Color(0.05, 0.07, 0.09), true)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cap.add_child(number)
		row.add_child(cap)

		var caption := _label(MENU[i][0], 15)
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(caption)
		_keys.append({"panel": entry, "normal": normal, "flash": flash_style})


func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast.offset_top = -72
	_toast.offset_bottom = -72
	_toast.add_theme_stylebox_override("panel", _box(PANEL_BG, 10, Color(1, 1, 1, 0.10), 10, 10))
	_toast_label = _label("", 15)
	_toast.add_child(_toast_label)
	root.add_child(_toast)


# ==============================================================================
# UPDATE
# ==============================================================================

func _update() -> void:
	if _core == null or _status == null: return

	# Status badge and position
	var state := "ALIVE"
	var state_color := GOOD
	if _respawning:
		state = "RESPAWNING"
		state_color = WARN
	elif not _core.is_alive:
		state = "DEAD"
		state_color = BAD
	_status.text = state
	_status.add_theme_color_override("font_color", state_color)
	_pos_label.text = "Tile (%d, %d)" % [_core.agent_pos.x, _core.agent_pos.y]

	# Stat bars
	var stats := {"Energy": _core.agent_energy, "Food": _core.agent_food, "Water": _core.agent_water}
	for stat: String in stats:
		var value := maxf(stats[stat], 0.0)
		_bars[stat].value = value
		_stat_values[stat].text = "%d / %d" % [roundi(value), int(SimulationCore.MAX_STAT)]

	# Inventory slots
	_inventory_title.text = "INVENTORY   %d / %d" % [_core.inventory.size(), SimulationCore.INVENTORY_LIMIT]
	for i in _slots.size():
		var item: String = _core.inventory[i] if i < _core.inventory.size() else ""
		var filled := item != ""
		var item_color: Color = ITEM_COLORS.get(item, Color.WHITE)
		_slots[i].add_theme_stylebox_override("panel", _box(
				Color(item_color, 0.22 if filled else 0.05), 8,
				Color(item_color, 0.80 if filled else 0.15), 6))
		_slot_labels[i].text = ITEM_NAMES.get(item, "-")

	# Storage
	var capacity := _core.get_max_storage_capacity()
	_huts.text = "Huts: %d" % _core.buildings["HUT"]
	_capacity.text = "Storage (cap. %d each)" % capacity
	for key: String in _storage_values:
		_storage_values[key].text = "%d / %d" % [_core.storage[key], capacity]

	# Action bar highlight
	for i in _keys.size():
		_keys[i]["panel"].add_theme_stylebox_override("panel", _keys[i]["flash"] if i == _flashed else _keys[i]["normal"])

	# Toast: warnings (messages ending with "!") in orange, death in red
	_toast.visible = _message != ""
	_toast_label.text = _message
	var toast_color := TEXT
	if _respawning:
		toast_color = BAD
	elif _message.ends_with("!"):
		toast_color = WARN
	_toast_label.add_theme_color_override("font_color", toast_color)


# ==============================================================================
# HELPERS
# ==============================================================================

# Styled panel with a vertical layout inside. Returns the VBox (its parent is the panel).
func _panel(root: Control, width: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 12, Color(1, 1, 1, 0.10), 14, 10))
	root.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	return vbox


func _label(text: String, size := 15, color := TEXT, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold:
		label.add_theme_font_override("font", _bold)
	return label


func _box(color: Color, radius := 12, border := Color(1, 1, 1, 0.10), pad := 14, shadow := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.set_content_margin_all(pad)
	style.shadow_size = shadow
	style.shadow_color = Color(0, 0, 0, 0.4)
	return style
