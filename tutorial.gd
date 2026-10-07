class_name Tutorial
extends Control
# Full-screen help window that explains all rules. The texts are generated from
# GameConfig, so they stay correct after rebalancing. It opens automatically when
# the game starts and is toggled with H / Esc or the Help button of the HUD.

const Tile = GameConfig.Tile
const TEXT := Color("#eef2f6")
const MUTED := Color("#8d99a6")
const GOOD := Color("#7ccf4a")
const ACCENT := Color(0.30, 0.55, 0.95)

# One line per action for the actions page (craft/build lines are generated)
const ACTION_HELP := {
	"collect_water": "Take 1 water from a lake or a well.",
	"collect_stick": "Pick up a stick from a tile edge (gives 1 wood).",
	"collect_wood": "Take 1 wood from a felled log.",
	"collect_stone": "Take 1 stone from a loose rock or a stone pile.",
	"fell_tree": "Needs an axe. Turns a tree into a log.",
	"mine_stone": "Needs a pickaxe. Turns a big rock into a stone pile.",
	"digout_plant": "Dig up a wild plant. Gives a plant item.",
	"plant_crop_here": "Needs a plant. Creates a field on the nearest free tile.",
	"plant_crop_near_water": "Needs a plant. Creates a field on the nearest free tile next to water or a well.",
	"water_crop": "Needs 1 water in the inventory. Waters the nearest dry field.",
	"farm_crop": "Harvest the nearest ripe crop (gives 1 food). It grows back.",
	"eat": "Restore food, from the inventory first, otherwise from the storage.",
	"drink": "Restore water, from the inventory first, otherwise from the storage.",
	"deposit_inventory": "Walk to home or a hut and store everything storable.",
	"rest": "End the day. An idle day (no work) is free of hunger and thirst.",
}

var bold_font: Font   # set by the HUD before the node enters the tree
var groups: Array = []  # action groups of the HUD dock: [title, [actions]]

var _texts: Array[String] = []
var _nav: Array[Button] = []
var _body: RichTextLabel
var _next: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks on the game while open

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 500)
	panel.add_theme_stylebox_override("panel", _box(Color(0.06, 0.08, 0.10, 0.97), 14, Color(1, 1, 1, 0.12), 18))
	center.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	# Header
	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(_label("HOW THE SIMULATION WORKS", 20, TEXT, true))
	header.add_child(_spacer())
	var close := _button("Close (H)")
	close.pressed.connect(hide)
	header.add_child(close)
	root.add_child(HSeparator.new())

	# Body: page list on the left, text on the right
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var nav := VBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	nav.custom_minimum_size.x = 190
	body.add_child(nav)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_color_override("default_color", TEXT)
	if bold_font != null:
		_body.add_theme_font_override("bold_font", bold_font)
	body.add_child(_body)

	# Footer
	var footer := HBoxContainer.new()
	root.add_child(footer)
	footer.add_child(_label("H or Esc opens and closes this window", 13, MUTED))
	footer.add_child(_spacer())
	_next = _button("Next")
	_next.pressed.connect(_on_next)
	footer.add_child(_next)

	var pages := [
		["Introduction / Quick Start", _page_goal()], ["World", _page_world()], ["Agent & Day", _page_agent()],
		["Inventory & Storage", _page_storage()], ["Actions", _page_actions()],
		["Tools & Buildings", _page_tools()], ["Tips", _page_tips()],
	]
	for i in pages.size():
		_texts.append(pages[i][1])
		var button := _button("%d   %s" % [i + 1, pages[i][0]])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_show_page.bind(i))
		nav.add_child(button)
		_nav.append(button)
	_show_page(0)


func toggle() -> void:
	visible = not visible


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo: return
	if key.keycode == KEY_H or (key.keycode == KEY_ESCAPE and visible):
		toggle()


func _show_page(index: int) -> void:
	_body.text = _texts[index]
	_body.scroll_to_line(0)
	for i in _nav.size():
		_style(_nav[i], i == index)
	_next.text = "Next" if index < _texts.size() - 1 else "Start playing"
	_next.set_meta("page", index)


func _on_next() -> void:
	var page: int = _next.get_meta("page")
	if page < _texts.size() - 1:
		_show_page(page + 1)
	else:
		hide()


# ==============================================================================
# PAGES (all numbers come from GameConfig)
# ==============================================================================

func _page_goal() -> String:
	var t := _head("Introduction")
	t += "You are a settler on a small, randomly generated island. Feed yourself, farm the land and build [b]huts[/b] for your offspring - then keep them alive.\n\n"
	t += "[b]Score[/b]: at the end of every day each living hut earns %s. Every hut needs %d food and %d water from the central storage per day. If one of them is missing, the hut dies for good and never scores again.\n\n" % [
			_col("[b]+1 point[/b]", GOOD), GameConfig.HUT_FOOD_PER_DAY, GameConfig.HUT_WATER_PER_DAY]
	t += "[b]The run[/b] ends when you die or after %d days. The highscore is the total number of points. Offspring never act on their own: you have to supply them, and all work costs energy.\n\n" % GameConfig.MAX_DAYS
	t += "[b]Quick start[/b]\n"
	t += "1. %s a wild plant, then %s it. Next to water a crop stays wet on its own.\n" % [_act("digout_plant"), _act("plant_crop_near_water")]
	t += "2. %s to end the day. Crops grow only while wet and ripen after %d wet days.\n" % [_act("rest"), GameConfig.CROP_RIPE_DAYS]
	t += "3. %s the ripe crop and %s your harvest in the storage.\n" % [_act("farm_crop"), _act("deposit_inventory")]
	t += "4. Collect sticks and stones, deposit them, then %s and finally %s.\n" % [_act("build_workbench"), _act("build_hut")]
	t += "5. %s again: every supplied hut scores a point." % _act("rest")
	return t


func _page_world() -> String:
	var t := _head("The World")
	t += "[b]Blocking[/b] (you walk around them): water, trees, big rocks, logs, stone piles and all buildings. [b]Walkable[/b]: free ground, wild plants, fields and loose rocks. You always stand next to the thing you work on.\n\n"
	t += _tile(Tile.WATER, "Water", "lakes. Collect water here. Fields next to water stay wet.")
	t += _tile(Tile.TREE, "Tree", "needs an axe to be felled. Over the days trees drop sticks.")
	t += "• %s - lie on the edge between two tiles, at most one per edge. A stick gives 1 wood.\n" % _col("[b]Stick[/b]", WorldView.STICK_COLOR.lightened(0.3))
	t += _tile(Tile.LOG, "Log", "a felled tree. Holds %d wood." % GameConfig.LOG_YIELD)
	t += _tile(Tile.SMALL_ROCK, "Loose rock", "gives %d stone and disappears." % GameConfig.SMALL_ROCK_YIELD)
	t += _tile(Tile.BIG_ROCK, "Big rock", "needs a pickaxe. Becomes a stone pile.")
	t += _tile(Tile.STONE_PILE, "Stone pile", "a mined rock. Holds %d stone." % GameConfig.STONE_PILE_YIELD)
	t += _tile(Tile.PLANT, "Wild plant", "dig it out to get a plant for farming.")
	t += _tile(Tile.FIELD, "Field", "soil with a crop. It grows while wet. Harvesting gives food and the crop grows back.")
	t += _tile(Tile.HOME, "Home", "your start building. Storage, but no score.")
	t += _tile(Tile.HUT, "Hut", "offspring. +1 score per supplied day, adds storage while alive.")
	t += _tile(Tile.HUT_DEAD, "Dead hut", "a hut that starved. It stays as a ruin.")
	t += _tile(Tile.WORKBENCH, "Workbench", "needed to craft tools.")
	t += _tile(Tile.WELL, "Well", "an extra water source.")
	t += "\n[b]Rings[/b]: colored rings in the world mark the target of every action you can do right now. The color matches the action's button. Buttons of impossible actions are gray with a red frame (hover to see why). Clicking them changes nothing."
	return t


func _page_agent() -> String:
	var t := _head("Agent & Day")
	t += "[b]Energy[/b] (max %d) pays for every action: its base cost plus %d per tile you walk. If you cannot afford an action, nothing happens.\n\n" % [int(GameConfig.MAX_ENERGY), int(GameConfig.STEP_COST)]
	t += "[b]Food[/b] and [b]Water[/b] (max %d each) both drop by %d when a day ends. If either reaches 0 you die. %s restores %d food, %s restores %d water.\n\n" % [
			int(GameConfig.MAX_STAT), int(GameConfig.DAILY_DRAIN), _act("eat"), int(GameConfig.EAT_GAIN), _act("drink"), int(GameConfig.DRINK_GAIN)]
	t += "[b]A day[/b] ends when you %s. In this order: (1) every hut eats and drinks from the storage and scores or dies, (2) wet crops grow, (3) trees may drop a stick, (4) your food and water drop and tomorrow's energy equals your food level.\n\n" % _act("rest")
	t += "[b]Idle day[/b]: if you did no work today, resting costs no food and no water, and tomorrow's energy is %.1fx your food level (up to %d). Only work counts. Eating, drinking and depositing items do not. Your huts still need supplies, so doing nothing earns nothing." % [
			GameConfig.IDLE_REST_FACTOR, int(GameConfig.MAX_ENERGY)]
	return t


func _page_storage() -> String:
	var t := _head("Inventory & Storage")
	t += "[b]Inventory[/b]: %d slots (%d with a wheelbarrow). Every item takes one slot: water, food, plant, wood, stone. You carry what you collect until you deposit it.\n\n" % [
			GameConfig.INVENTORY_SLOTS, GameConfig.WHEELBARROW_SLOTS]
	t += "[b]Central storage[/b] sits in your home and in every living hut. It holds water, food, wood and stone (plants stay in the inventory). Capacity per resource: %d for the home plus %d for each living hut. %s moves everything storable there.\n\n" % [
			GameConfig.HUT_CAPACITY, GameConfig.HUT_CAPACITY, _act("deposit_inventory")]
	t += "[b]Eating and drinking[/b] use the inventory first. If it holds no food or water, you walk to the storage and take it from there.\n\n"
	t += "[b]Materials[/b] for crafting and building come from the storage, you do not have to carry them. The huts eat from there too, so keep it stocked."
	return t


func _page_actions() -> String:
	var t := _head("Actions")
	t += "Costs are base energy, plus %d per tile walked. With a hoe, digging, planting and harvesting cost x%.1f. An impossible action does nothing and costs nothing.\n" % [
			int(GameConfig.STEP_COST), GameConfig.HOE_DISCOUNT]
	for group: Array in groups:
		t += "\n[b]%s[/b]\n" % group[0]
		for action: String in group[1]:
			t += "• %s [color=#8d99a6](%d)[/color] - %s\n" % [_act(action), int(GameConfig.COST[action]), _action_help(action)]
	return t


func _page_tools() -> String:
	var t := _head("Tools & Buildings")
	t += "[b]Tools[/b] are crafted at a workbench (materials from the storage) and stay with you.\n"
	t += "• %s - digging, planting and harvesting cost x%.1f. (%s)\n" % [_named("Hoe", "craft_hoe"), GameConfig.HOE_DISCOUNT, _recipe("craft_hoe")]
	t += "• %s - needed to fell trees. (%s)\n" % [_named("Axe", "craft_axe"), _recipe("craft_axe")]
	t += "• %s - needed to mine big rocks. (%s)\n" % [_named("Pickaxe", "craft_pickaxe"), _recipe("craft_pickaxe")]
	t += "• %s - inventory grows from %d to %d slots. (%s)\n\n" % [_named("Wheelbarrow", "craft_wheelbarrow"),
			GameConfig.INVENTORY_SLOTS, GameConfig.WHEELBARROW_SLOTS, _recipe("craft_wheelbarrow")]
	t += "[b]Buildings[/b] are built on the nearest free tile (never on the tile you stand on). Materials come from the storage.\n"
	t += "• %s - up to %d. Needed to craft tools. (%s)\n" % [_named("Workbench", "build_workbench"), GameConfig.MAX_COUNT[Tile.WORKBENCH], _recipe("build_workbench")]
	t += "• %s - up to %d living huts. Each supplied hut scores +1 per day and adds %d storage per resource. (%s)\n" % [
			_named("Hut", "build_hut"), GameConfig.MAX_COUNT[Tile.HUT], GameConfig.HUT_CAPACITY, _recipe("build_hut")]
	t += "• %s - up to %d. A water source: collect water there, and fields next to it stay wet. (%s)" % [
			_named("Well", "build_well"), GameConfig.MAX_COUNT[Tile.WELL], _recipe("build_well")]
	return t


func _page_tips() -> String:
	var t := _head("Tips & Notes")
	t += "• Hover an impossible button to see what is missing. Clicking it is harmless.\n"
	t += "• Food and water for your huts have to be in the storage at the end of the day. Plan ahead.\n"
	t += "• A field needs one watering (%s) when it is not next to water. After a harvest it needs one new watering: %s.\n" % [
			_act("water_crop"), "yes" if GameConfig.REWATER_AFTER_HARVEST else "no"]
	t += "• The same seed always creates the same world. Change it in the inspector of the WorldManager node.\n"
	t += "• After death or after %d days the run restarts on the same world.\n" % GameConfig.MAX_DAYS
	t += "• Every number in this text comes from game_config.gd and updates when you rebalance the game.\n\n"
	t += "[b]About this prototype[/b]\nThis simulation is the environment for an AI agent. The game logic does not depend on the graphics: an agent plays through one function, perform(action), with exactly the actions you see in the dock."
	return t


# ==============================================================================
# HELPERS
# ==============================================================================

func _action_help(action: String) -> String:
	if GameConfig.TOOLS.has(action) or GameConfig.BUILDINGS.has(action):
		var what := "Crafts at a workbench." if GameConfig.TOOLS.has(action) else "Builds on the nearest free tile."
		return "%s Needs %s." % [what, _recipe(action)]
	return ACTION_HELP[action]


# "8 wood + 4 stone" for a craft or build action
func _recipe(action: String) -> String:
	var recipe: Dictionary = GameConfig.TOOLS[action] if GameConfig.TOOLS.has(action) else GameConfig.BUILDINGS[action]
	var parts: Array[String] = []
	for item: String in recipe["materials"]:
		parts.append("%d %s" % [recipe["materials"][item], item.to_lower()])
	return " + ".join(parts)


func _head(title: String) -> String:
	return "[font_size=22][b]%s[/b][/font_size]\n\n" % title


func _col(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]


# Action name in the color of its button and ring
func _act(action: String) -> String:
	return _col("[b]%s[/b]" % action.capitalize(), WorldView.ACTION_COLORS[action])


func _named(label: String, action: String) -> String:
	return _col("[b]%s[/b]" % label, WorldView.ACTION_COLORS[action])


# Bullet line for a tile type, titled in the color of its block
func _tile(type: int, title: String, text: String) -> String:
	var color: Color = WorldView.PARTS[type][0][0]
	return "• %s - %s\n" % [_col("[b]%s[/b]" % title, color.lightened(0.4)), text]


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _label(text: String, size: int, color: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if bold and bold_font != null:
		label.add_theme_font_override("font", bold_font)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 14)
	_style(button, false)
	return button


func _style(button: Button, active: bool) -> void:
	var bg := Color(ACCENT, 0.30) if active else Color(1, 1, 1, 0.06)
	var border := Color(ACCENT, 0.90) if active else Color(1, 1, 1, 0.12)
	button.add_theme_stylebox_override("normal", _box(bg, 8, border, 8))
	button.add_theme_stylebox_override("hover", _box(Color(bg, bg.a + 0.15), 8, border, 8))
	button.add_theme_stylebox_override("pressed", _box(Color(bg, bg.a + 0.25), 8, border, 8))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, TEXT)


func _box(color: Color, radius: int, border: Color, pad: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.set_content_margin_all(pad)
	return style
