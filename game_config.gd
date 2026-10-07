class_name GameConfig
extends RefCounted
# Every tunable number and rule of the simulation in one place.
# To rebalance the game only this file needs to be touched.

enum Tile {
	EMPTY, WATER, TREE, SMALL_ROCK, BIG_ROCK, PLANT,
	FIELD, LOG, STONE_PILE, HOME, HUT, HUT_DEAD, WORKBENCH, WELL,
}

# Tiles the agent can walk over (everything else blocks the path)
const WALKABLE := [Tile.EMPTY, Tile.PLANT, Tile.FIELD, Tile.SMALL_ROCK]

# --- Time and survival -------------------------------------------------------
const MAX_DAYS := 100              # the run ends after this many days
const MAX_STAT := 100.0            # max food / water of the agent
const IDLE_REST_FACTOR := 1.5      # rest without spending energy: no drain, next day's energy = food * factor
const MAX_ENERGY := MAX_STAT * IDLE_REST_FACTOR
const DAILY_DRAIN := 15.0          # food and water lost per day
const EAT_GAIN := 25.0             # food restored by one meal
const DRINK_GAIN := 25.0           # water restored by one drink
const STEP_COST := 1.0             # energy per tile walked

# --- Inventory and storage ---------------------------------------------------
const INVENTORY_SLOTS := 3
const WHEELBARROW_SLOTS := 6       # inventory size once the wheelbarrow exists
const HUT_CAPACITY := 10           # storage per resource, for home and each living hut

# --- Offspring huts ----------------------------------------------------------
const HUT_FOOD_PER_DAY := 1        # taken from storage every day for each living hut
const HUT_WATER_PER_DAY := 1       # a supplied hut earns +1 score, otherwise it dies

# --- Farming and resources ---------------------------------------------------
const CROP_RIPE_DAYS := 3          # watered days a crop needs to ripen
const REWATER_AFTER_HARVEST := true  # true: a regrowing crop needs one new watering; false: watered forever
const HOE_DISCOUNT := 0.5          # cost factor for HOE_ACTIONS with a hoe
const STICK_DROP_CHANCE := 0.25    # per tree and day
const LOG_YIELD := 3               # wood from a felled tree
const STONE_PILE_YIELD := 3        # stone from a mined rock
const SMALL_ROCK_YIELD := 1

# --- Energy cost per action (the key order is the action order) --------------
const COST := {
	"collect_water": 2.0, "collect_stick": 3.0, "collect_wood": 10.0, "collect_stone": 5.0,
	"fell_tree": 50.0, "mine_stone": 50.0,
	"digout_plant": 5.0, "plant_crop_here": 5.0, "plant_crop_near_water": 5.0,
	"water_crop": 3.0, "farm_crop": 5.0,
	"eat": 1.0, "drink": 1.0, "deposit_inventory": 0.0, "rest": 0.0,
	"craft_hoe": 20.0, "craft_axe": 20.0, "craft_pickaxe": 20.0, "craft_wheelbarrow": 20.0,
	"build_hut": 50.0, "build_workbench": 20.0, "build_well": 50.0,
}

# Actions that do not count as work: they never prevent an idle day (see rest)
const NON_WORK_ACTIONS := ["eat", "drink", "deposit_inventory"]
const HOE_ACTIONS := ["digout_plant", "plant_crop_here", "plant_crop_near_water", "farm_crop"]
const TOOL_REQUIRED := {"fell_tree": "AXE", "mine_stone": "PICKAXE"}

# --- Recipes (materials are taken from the central storage) ------------------
const TOOLS := {
	"craft_hoe": {"tool": "HOE", "materials": {"WOOD": 1, "STONE": 1}},
	"craft_axe": {"tool": "AXE", "materials": {"WOOD": 2, "STONE": 2}},
	"craft_pickaxe": {"tool": "PICKAXE", "materials": {"WOOD": 2, "STONE": 2}},
	"craft_wheelbarrow": {"tool": "WHEELBARROW", "materials": {"WOOD": 4, "STONE": 2}},
}

const BUILDINGS := {
	"build_hut": {"tile": Tile.HUT, "materials": {"WOOD": 8, "STONE": 4}},
	"build_workbench": {"tile": Tile.WORKBENCH, "materials": {"WOOD": 3, "STONE": 2}},
	"build_well": {"tile": Tile.WELL, "materials": {"STONE": 6}},
}

# Maximum number of living buildings per type
const MAX_COUNT := {Tile.HUT: 10, Tile.WORKBENCH: 1, Tile.WELL: 3}
