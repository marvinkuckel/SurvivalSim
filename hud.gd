@tool
class_name Hud
extends CanvasLayer
# Game-style overlay: agent (top left), storage (top right), day + score (top
# center), message toast and a dock with one button per action (bottom).
# The UI is built once in code and only updated afterwards.

signal action_pressed(action: String)

const Tile = GameConfig.Tile

# Dock columns: [title, actions]
const GROUPS := [
	["RESOURCES", ["collect_water", "collect_stick", "collect_wood", "collect_stone", "fell_tree", "mine_stone"]],
	["FARMING", ["digout_plant", "plant_crop_here", "plant_crop_near_water", "water_crop", "farm_crop"]],
	["SURVIVAL", ["eat", "drink", "deposit_inventory", "rest"]],
	["CRAFTING", ["craft_hoe", "craft_axe", "craft_pickaxe", "craft_wheelbarrow"]],
	["BUILDING", ["build_hut", "build_workbench", "build_well"]],
]

const PANEL_BG := Color(0.06, 0.08, 0.10, 0.82)
const TEXT := Color("#eef2f6")
const MUTED := Color("#8d99a6")
const DIM := Color("#5b6670")
const GOOD := Color("#7ccf4a")
const WARN := Color("#f0a030")
const BAD := Color("#e5534b")
const STAT_COLORS := {"Energy": Color("#f5b82e"), "Food": Color("#7ccf4a"), "Water": Color("#3fa7f5")}
const STAT_MAX := {"Energy": GameConfig.MAX_ENERGY, "Food": GameConfig.MAX_STAT, "Water": GameConfig.MAX_STAT}
const ITEM_COLORS := {"WATER": Color("#3fa7f5"), "FOOD": Color("#7ccf4a"), "WOOD": Color("#b98a5a"), "STONE": Color("#a0a7ae"), "PLANT": Color("#a6e22e")}
const ITEM_NAMES := {"WATER": "Water", "FOOD": "Food", "WOOD": "Wood", "STONE": "Stone", "PLANT": "Plant"}
const STORAGE_ITEMS := ["WATER", "FOOD", "WOOD", "STONE"]
const TOOL_NAMES := {"HOE": "Hoe", "AXE": "Axe", "PICKAXE": "Pickaxe", "WHEELBARROW": "Wheelbarrow"}

var _core: SimulationCore
var _plans: Dictionary = {}
var _message := ""
var _respawning := false

var _bold: FontVariation
var _status: Label
var _pos_label: Label
var _bars: Dictionary = {}           # stat name -> ProgressBar
var _stat_values: Dictionary = {}    # stat name -> Label
var _tool_labels: Dictionary = {}    # tool -> Label
var _inventory_title: Label
var _slots: Array[PanelContainer] = []
var _slot_labels: Array[Label] = []
var _huts: Label
var _capacity: Label
var _storage_values: Dictionary = {} # resource -> Label
var _day_label: Label
var _score_label: Label
var _buttons: Dictionary = {}        # action -> Button
var _costs: Dictionary = {}          # action -> Label (energy cost inside the button)
var _toast: PanelContainer
var _tutorial: Tutorial
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
	_build_day_panel(root)
	_build_toast(root)
	_build_dock(root)
	if not Engine.is_editor_hint():
		_tutorial = Tutorial.new()  # opens automatically, toggled with H or the Help button
		_tutorial.bold_font = _bold
		_tutorial.groups = GROUPS
		root.add_child(_tutorial)
	_update()


# Redraws the overlay. `plans` comes from SimulationCore.get_plans().
func refresh(core: SimulationCore, plans: Dictionary, message := "", respawning := false) -> void:
	_core = core
	_plans = plans
	_message = message
	_respawning = respawning
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
	header.add_child(_spacer())
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
		bar.max_value = STAT_MAX[stat]
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
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	box.add_child(tools)
	for tool_key: String in TOOL_NAMES:
		_tool_labels[tool_key] = _label(TOOL_NAMES[tool_key], 12, DIM, true)
		tools.add_child(_tool_labels[tool_key])

	_inventory_title = _label("", 13, MUTED)
	box.add_child(_inventory_title)
	var slots := GridContainer.new()
	slots.columns = 3
	slots.add_theme_constant_override("h_separation", 8)
	slots.add_theme_constant_override("v_separation", 8)
	box.add_child(slots)
	for i in GameConfig.WHEELBARROW_SLOTS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(80, 32)
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
	header.add_child(_spacer())
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
	for key: String in STORAGE_ITEMS:
		var name_label := _label(ITEM_NAMES[key], 14, ITEM_COLORS[key])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		var value := _label("", 14)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_storage_values[key] = value


func _build_day_panel(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.offset_top = 16
	panel.offset_bottom = 16
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 12, Color(1, 1, 1, 0.10), 10, 10))
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	panel.add_child(row)
	_day_label = _label("", 18, TEXT, true)
	_score_label = _label("", 18, GOOD, true)
	row.add_child(_day_label)
	row.add_child(_score_label)
	var help := Button.new()
	help.text = "? Help (H)"
	help.focus_mode = Control.FOCUS_NONE
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0.06), 8, Color(1, 1, 1, 0.15), 6))
	help.add_theme_stylebox_override("hover", _box(Color(1, 1, 1, 0.14), 8, Color(1, 1, 1, 0.25), 6))
	help.add_theme_stylebox_override("pressed", _box(Color(1, 1, 1, 0.22), 8, Color(1, 1, 1, 0.25), 6))
	help.pressed.connect(func() -> void:
		if _tutorial != null: _tutorial.toggle())
	row.add_child(help)


func _build_toast(root: Control) -> void:
	_toast = PanelContainer.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 76
	_toast.offset_bottom = 76
	_toast.add_theme_stylebox_override("panel", _box(PANEL_BG, 10, Color(1, 1, 1, 0.10), 10, 10))
	_toast_label = _label("", 15)
	_toast.add_child(_toast_label)
	root.add_child(_toast)


func _build_dock(root: Control) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_top = -16
	panel.offset_bottom = -16
	panel.add_theme_stylebox_override("panel", _box(PANEL_BG, 12, Color(1, 1, 1, 0.10), 12, 10))
	root.add_child(panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	panel.add_child(columns)

	for group: Array in GROUPS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		column.custom_minimum_size.x = 176
		column.add_child(_label(group[0], 12, MUTED, true))
		for action: String in group[1]:
			var button := Button.new()
			button.text = action.capitalize()
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(0, 28)
			button.add_theme_font_size_override("font_size", 13)
			button.pressed.connect(func() -> void: action_pressed.emit(action))
			# Energy cost, right-aligned inside the button
			var cost := _label("", 12, MUTED)
			cost.set_anchors_preset(Control.PRESET_FULL_RECT)
			cost.offset_right = -8
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(cost)
			column.add_child(button)
			_buttons[action] = button
			_costs[action] = cost
		columns.add_child(column)


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

	# Day and score
	_day_label.text = "DAY %d / %d" % [_core.day, GameConfig.MAX_DAYS]
	_score_label.text = "SCORE %d" % _core.score

	# Stat bars
	var stats := {"Energy": _core.agent_energy, "Food": _core.agent_food, "Water": _core.agent_water}
	for stat: String in stats:
		var value := maxf(stats[stat], 0.0)
		_bars[stat].value = value
		_stat_values[stat].text = "%d / %d" % [roundi(value), int(STAT_MAX[stat])]

	# Tools (lit up once crafted)
	for tool_key: String in _tool_labels:
		_tool_labels[tool_key].add_theme_color_override("font_color", GOOD if _core.tools[tool_key] else DIM)

	# Inventory slots (6 with the wheelbarrow, otherwise 3)
	var slot_count := _core.inventory_slots()
	_inventory_title.text = "INVENTORY   %d / %d" % [_core.inventory.size(), slot_count]
	for i in _slots.size():
		_slots[i].visible = i < slot_count
		var item: String = _core.inventory[i] if i < _core.inventory.size() else ""
		var filled := item != ""
		var item_color: Color = ITEM_COLORS.get(item, Color.WHITE)
		_slots[i].add_theme_stylebox_override("panel", _box(
				Color(item_color, 0.22 if filled else 0.05), 8,
				Color(item_color, 0.80 if filled else 0.15), 6))
		_slot_labels[i].text = ITEM_NAMES.get(item, "-")

	# Storage and huts
	var capacity := _core.get_max_storage_capacity()
	var lost := _core.count_tiles(Tile.HUT_DEAD)
	_huts.text = "Huts: %d%s" % [_core.count_tiles(Tile.HUT), " (+%d lost)" % lost if lost > 0 else ""]
	_capacity.text = "Storage (cap. %d each)" % capacity
	for key: String in _storage_values:
		_storage_values[key].text = "%d / %d" % [_core.storage[key], capacity]

	_update_dock()

	# Toast: warnings (messages ending with "!") in orange, run end in red
	_toast.visible = _message != ""
	_toast_label.text = _message
	var toast_color := TEXT
	if _respawning:
		toast_color = BAD
	elif _message.ends_with("!"):
		toast_color = WARN
	_toast_label.add_theme_color_override("font_color", toast_color)


# Possible actions glow in their ring color, impossible ones are gray with a red frame.
func _update_dock() -> void:
	for action: String in _buttons:
		var plan: Dictionary = _plans.get(action, {"ok": false, "msg": "", "cost": 0.0})
		var ok: bool = plan["ok"]
		var color: Color = WorldView.ACTION_COLORS[action]
		var text_color := color.lightened(0.2) if ok else DIM
		var border := Color(color, 0.9) if ok else Color(BAD, 0.45)
		var bg := Color(color, 0.14) if ok else Color(1, 1, 1, 0.03)

		var button: Button = _buttons[action]
		button.add_theme_stylebox_override("normal", _box(bg, 6, border, 6))
		button.add_theme_stylebox_override("hover", _box(Color(bg, bg.a + 0.15), 6, border, 6))
		button.add_theme_stylebox_override("pressed", _box(Color(color, 0.40), 6, border, 6))
		for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, text_color)
		button.tooltip_text = "Cost: %d energy" % ceili(plan["cost"]) if ok else plan["msg"]
		if action == "rest" and ok:
			button.tooltip_text = "Idle day: no food/water drain, %.1fx energy tomorrow" % GameConfig.IDLE_REST_FACTOR \
					if _core.energy_spent_today <= 0.0 else "End the day: food and water drain"

		var cost_label: Label = _costs[action]
		cost_label.text = "-%d" % ceili(plan["cost"]) if ok and plan["cost"] > 0.0 else ""
		cost_label.add_theme_color_override("font_color", text_color)


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


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


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
