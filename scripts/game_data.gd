extends Node

enum UnitType { ALPHA, BRAVO, CHARLIE }
enum GamePhase { PLAYING, GAME_OVER, WIN }
enum Team { RED, BLUE }
enum Lane { NORTH, EAST, SOUTH, WEST }
enum VictoryCondition { NONE, SURVIVE_ROUNDS, DESTROY_RED_BASES, SURVIVE_TIME, GENERATE_MARINES }

signal phase_changed(new_phase: GamePhase)
signal unit_stats_changed(team: Team, unit_type: UnitType)
signal zones_changed
signal base_destroyed(base_node: Node2D)
signal level_loaded

var game_phase: GamePhase = GamePhase.PLAYING:
	set(value):
		game_phase = value
		phase_changed.emit(game_phase)

var red_units: Array = []
var blue_units: Array = []

# Bases
var blue_base: Node2D = null
var red_bases: Array = []

# Victory condition
var victory_condition: VictoryCondition = VictoryCondition.NONE
var victory_param: float = 10.0
var rounds_survived: int = 0
var marines_generated: int = 0
var time_elapsed: float = 0.0
var victory_message: String = ""

# Level config
var current_level_name: String = ""
var base_config := {
	"blue_hp": 300.0,
	"blue_damage": 30.0,
	"blue_fire_rate": 1.5,
	"blue_can_attack": false,
	"red_bases_enabled": false,
	"red_base_hp": 200.0,
	"red_base_damage": 20.0,
	"red_base_fire_rate": 2.0,
	"red_can_attack": false,
}

# ponytail: ability config, editable via F4 menu
var ability_config := {
	"bomb_key": KEY_Q,
	"bomb_damage": 100.0,
	"bomb_radius": 80.0,
	"dash_key": KEY_W,
	"dash_damage": 60.0,
	"dash_distance": 150.0,
	"dash_cooldown": 5.0,
	"bomb_cooldown": 3.0,
	"medic_cooldown": 8.0,
	"medic_key": KEY_E,
	"medic_heal_amount": 10.0,
	"medic_heal_rate": 1.0,
	"medic_heal_range": 150.0,
	"medic_shield_amount": 200.0,
	"medic_shield_duration": 6.0,
}

# ponytail: wave spawning config
var wave_config := {
	"interval": 15.0,
	"auto": false,
	"alpha_count": 3,
	"bravo_count": 1,
	"charlie_count": 0,
}

const TILE_SIZE: float = 100.0
const BLUE_CELL_SIZE: float = 20.0

# Zone rects: each zone is [min_corner, max_corner], independently editable
var zone_rects := {
	"center": [Vector2(490, 210), Vector2(790, 510)],
	"north":  [Vector2(490, 100), Vector2(790, 200)],
	"south":  [Vector2(490, 520), Vector2(790, 620)],
	"west":   [Vector2(380, 210), Vector2(480, 510)],
	"east":   [Vector2(800, 210), Vector2(900, 510)],
}


func get_zone_center() -> Vector2:
	var r: Array = zone_rects["center"]
	return (r[0] + r[1]) / 2.0

# --- Unit stats per team (loaded from data/units.json) ---
var RED_UNITS := {}
var BLUE_UNITS := {}

const _TYPE_MAP := {"ALPHA": UnitType.ALPHA, "BRAVO": UnitType.BRAVO, "CHARLIE": UnitType.CHARLIE}

func _ready() -> void:
	_load_units_json()
	_load_zones_json()


func _load_units_json() -> void:
	# ponytail: retry up to 3 times — OneDrive can lock the file briefly
	var parsed = null
	for attempt in 3:
		var file := FileAccess.open("res://data/units.json", FileAccess.READ)
		if file:
			parsed = JSON.parse_string(file.get_as_text())
			if parsed != null:
				break
	if parsed == null:
		push_error("Cannot load data/units.json after 3 attempts, using fallback")
		_load_fallback()
		return
	RED_UNITS = _parse_team(parsed["red"])
	BLUE_UNITS = _parse_team(parsed["blue"])
	if parsed.has("abilities"):
		var loaded: Dictionary = parsed["abilities"]
		for key in loaded:
			if ability_config.has(key):
				ability_config[key] = loaded[key]
	if parsed.has("waves"):
		var loaded_w: Dictionary = parsed["waves"]
		for key in loaded_w:
			if wave_config.has(key):
				wave_config[key] = loaded_w[key]


func _load_fallback() -> void:
	# Minimal data so the game doesn't crash on startup
	RED_UNITS = {
		UnitType.ALPHA: {"name": "Alpha", "letter": "A", "cost": 50, "hp": 50.0,
			"damage": 10.0, "attack_range": 1.0, "fire_rate": 1.0, "move_speed": 56.0,
			"color": Color(0.7, 0.3, 0.3), "armor_type": "light"},
		UnitType.BRAVO: {"name": "Bravo", "letter": "B", "cost": 100, "hp": 80.0,
			"damage": 12.0, "attack_range": 2.0, "fire_rate": 0.6, "move_speed": 52.5,
			"color": Color(0.5, 0.7, 0.3), "armor_type": "light"},
		UnitType.CHARLIE: {"name": "Charlie", "letter": "C", "cost": 150, "hp": 140.0,
			"damage": 16.0, "attack_range": 1.5, "fire_rate": 1.5, "move_speed": 49.0,
			"color": Color(0.6, 0.5, 0.2), "armor_type": "heavy"},
	}
	BLUE_UNITS = RED_UNITS.duplicate(true)


func _parse_team(team_data: Dictionary) -> Dictionary:
	var result := {}
	for key in team_data:
		var unit: Dictionary = team_data[key].duplicate()
		# Convert color array [r, g, b] to Color
		var c: Array = unit["color"]
		unit["color"] = Color(c[0], c[1], c[2])
		result[_TYPE_MAP[key]] = unit
	return result


func get_unit_data(team: Team, unit_type: UnitType) -> Dictionary:
	if team == Team.RED:
		return RED_UNITS[unit_type]
	return BLUE_UNITS[unit_type]


func get_unit_name(team: Team, unit_type: UnitType) -> String:
	return get_unit_data(team, unit_type)["name"]


func get_unit_letter(team: Team, unit_type: UnitType) -> String:
	return get_unit_data(team, unit_type)["letter"]


func get_unit_color(team: Team, unit_type: UnitType) -> Color:
	return get_unit_data(team, unit_type)["color"]


func notify_stats_changed(team_val: Team, unit_type_val: UnitType) -> void:
	unit_stats_changed.emit(team_val, unit_type_val)
	var unit_list: Array = red_units if team_val == Team.RED else blue_units
	for unit in unit_list:
		if is_instance_valid(unit) and unit.unit_type == unit_type_val:
			unit.reload_stats()


# --- Spatial hash grid (collision avoidance / separation) ---
# ponytail: rebuilt once per frame by main.gd, queried by each unit so a unit
# only looks at near neighbors instead of every other unit (O(N) vs O(N^2)).
const SPATIAL_CELL_SIZE: float = 24.0
var _spatial_grid: Dictionary = {}


func rebuild_spatial_grid() -> void:
	_spatial_grid.clear()
	for u in red_units:
		if is_instance_valid(u):
			_grid_insert(u)
	for u in blue_units:
		if is_instance_valid(u):
			_grid_insert(u)


func _grid_insert(u: Node2D) -> void:
	var key := _cell_of(u.global_position)
	if not _spatial_grid.has(key):
		_spatial_grid[key] = []
	_spatial_grid[key].append(u)


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(pos.x / SPATIAL_CELL_SIZE)),
		int(floor(pos.y / SPATIAL_CELL_SIZE))
	)


# Returns units in cells overlapping the query box (centered on pos, +/- query_radius).
# May include a few units slightly outside query_radius — caller filters by distance.
func get_nearby_units(pos: Vector2, query_radius: float) -> Array:
	var result: Array = []
	var min_c := _cell_of(pos - Vector2(query_radius, query_radius))
	var max_c := _cell_of(pos + Vector2(query_radius, query_radius))
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			var key := Vector2i(cx, cy)
			if _spatial_grid.has(key):
				result.append_array(_spatial_grid[key])
	return result


func register_unit(unit: Node, team: Team) -> void:
	if team == Team.RED:
		if unit not in red_units:
			red_units.append(unit)
	else:
		if unit not in blue_units:
			blue_units.append(unit)


func unregister_unit(unit: Node, team: Team) -> void:
	if team == Team.RED:
		red_units.erase(unit)
	else:
		blue_units.erase(unit)


const _TYPE_NAME_MAP := {UnitType.ALPHA: "ALPHA", UnitType.BRAVO: "BRAVO", UnitType.CHARLIE: "CHARLIE"}

func save_units_json() -> void:
	var out := {"red": {}, "blue": {}, "abilities": ability_config.duplicate(), "waves": wave_config.duplicate()}
	for unit_type in _TYPE_NAME_MAP:
		var key: String = _TYPE_NAME_MAP[unit_type]
		for pair in [["red", RED_UNITS], ["blue", BLUE_UNITS]]:
			var team_key: String = pair[0]
			var units: Dictionary = pair[1]
			if not units.has(unit_type):
				continue
			var d: Dictionary = units[unit_type].duplicate()
			# Convert Color back to array
			var c: Color = d["color"]
			d["color"] = [snappedf(c.r, 0.01), snappedf(c.g, 0.01), snappedf(c.b, 0.01)]
			out[team_key][key] = d
	var file := FileAccess.open("res://data/units.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(out, "\t"))


func _load_zones_json() -> void:
	var parsed = null
	for attempt in 3:
		var file := FileAccess.open("res://data/terrain.json", FileAccess.READ)
		if file:
			parsed = JSON.parse_string(file.get_as_text())
			if parsed != null:
				break
	if parsed == null:
		return  # ponytail: keep hardcoded defaults if file missing
	for zone_name in zone_rects:
		if parsed.has(zone_name):
			var z: Dictionary = parsed[zone_name]
			zone_rects[zone_name] = [Vector2(z["min"][0], z["min"][1]), Vector2(z["max"][0], z["max"][1])]


func save_zones_json() -> void:
	var out := {}
	for zone_name in zone_rects:
		var r: Array = zone_rects[zone_name]
		out[zone_name] = {
			"min": [snappedf(r[0].x, 1), snappedf(r[0].y, 1)],
			"max": [snappedf(r[1].x, 1), snappedf(r[1].y, 1)],
		}
	var file := FileAccess.open("res://data/terrain.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(out, "\t"))


func reset_game() -> void:
	red_units.clear()
	blue_units.clear()
	_spatial_grid.clear()
	blue_base = null
	red_bases.clear()
	rounds_survived = 0
	marines_generated = 0
	time_elapsed = 0.0
	victory_message = ""


# --- Level save/load system ---

const LEVELS_DIR := "user://levels/"

func _ensure_levels_dir() -> void:
	if not DirAccess.dir_exists_absolute(LEVELS_DIR):
		DirAccess.make_dir_recursive_absolute(LEVELS_DIR)


func _serialize_units() -> Dictionary:
	var out := {"red": {}, "blue": {}}
	for unit_type in _TYPE_NAME_MAP:
		var key: String = _TYPE_NAME_MAP[unit_type]
		for pair in [["red", RED_UNITS], ["blue", BLUE_UNITS]]:
			var team_key: String = pair[0]
			var units: Dictionary = pair[1]
			if not units.has(unit_type):
				continue
			var d: Dictionary = units[unit_type].duplicate()
			var c: Color = d["color"]
			d["color"] = [snappedf(c.r, 0.01), snappedf(c.g, 0.01), snappedf(c.b, 0.01)]
			out[team_key][key] = d
	return out


func _serialize_terrain() -> Dictionary:
	var out := {}
	for zone_name in zone_rects:
		var r: Array = zone_rects[zone_name]
		out[zone_name] = {
			"min": [snappedf(r[0].x, 1), snappedf(r[0].y, 1)],
			"max": [snappedf(r[1].x, 1), snappedf(r[1].y, 1)],
		}
	return out


const _VICTORY_NAMES := {
	VictoryCondition.NONE: "NONE",
	VictoryCondition.SURVIVE_ROUNDS: "SURVIVE_ROUNDS",
	VictoryCondition.DESTROY_RED_BASES: "DESTROY_RED_BASES",
	VictoryCondition.SURVIVE_TIME: "SURVIVE_TIME",
	VictoryCondition.GENERATE_MARINES: "GENERATE_MARINES",
}

const _VICTORY_FROM_NAME := {
	"NONE": VictoryCondition.NONE,
	"SURVIVE_ROUNDS": VictoryCondition.SURVIVE_ROUNDS,
	"DESTROY_RED_BASES": VictoryCondition.DESTROY_RED_BASES,
	"SURVIVE_TIME": VictoryCondition.SURVIVE_TIME,
	"GENERATE_MARINES": VictoryCondition.GENERATE_MARINES,
}


func save_level(level_name: String) -> bool:
	_ensure_levels_dir()
	var data := {
		"name": level_name,
		"victory_condition": _VICTORY_NAMES[victory_condition],
		"victory_param": victory_param,
		"units": _serialize_units(),
		"terrain": _serialize_terrain(),
		"waves": wave_config.duplicate(),
		"abilities": ability_config.duplicate(),
		"base_config": base_config.duplicate(),
	}
	var safe_name := level_name.to_lower().replace(" ", "_").replace("/", "").replace("\\", "")
	var path := LEVELS_DIR + safe_name + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("Cannot save level to: " + path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_level(level_name: String) -> bool:
	_ensure_levels_dir()
	var safe_name := level_name.to_lower().replace(" ", "_").replace("/", "").replace("\\", "")
	var path := LEVELS_DIR + safe_name + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot load level: " + path)
		return false
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("Invalid JSON in level: " + path)
		return false
	return _apply_level_data(parsed)


func _apply_level_data(data: Dictionary) -> bool:
	current_level_name = data.get("name", "")

	# Victory condition
	var vc_name: String = data.get("victory_condition", "NONE")
	victory_condition = _VICTORY_FROM_NAME.get(vc_name, VictoryCondition.NONE)
	victory_param = data.get("victory_param", 10.0)

	# Units
	if data.has("units"):
		var units_data: Dictionary = data["units"]
		if units_data.has("red"):
			RED_UNITS = _parse_team(units_data["red"])
		if units_data.has("blue"):
			BLUE_UNITS = _parse_team(units_data["blue"])

	# Terrain
	if data.has("terrain"):
		var terrain: Dictionary = data["terrain"]
		for zone_name in zone_rects:
			if terrain.has(zone_name):
				var z: Dictionary = terrain[zone_name]
				zone_rects[zone_name] = [Vector2(z["min"][0], z["min"][1]), Vector2(z["max"][0], z["max"][1])]
		zones_changed.emit()

	# Waves
	if data.has("waves"):
		var loaded_w: Dictionary = data["waves"]
		for key in loaded_w:
			if wave_config.has(key):
				wave_config[key] = loaded_w[key]

	# Abilities
	if data.has("abilities"):
		var loaded_a: Dictionary = data["abilities"]
		for key in loaded_a:
			if ability_config.has(key):
				ability_config[key] = loaded_a[key]

	# Base config
	if data.has("base_config"):
		var loaded_b: Dictionary = data["base_config"]
		for key in loaded_b:
			if base_config.has(key):
				base_config[key] = loaded_b[key]

	level_loaded.emit()
	return true


func list_saved_levels() -> Array:
	_ensure_levels_dir()
	var levels: Array = []
	var dir := DirAccess.open(LEVELS_DIR)
	if not dir:
		return levels
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var f := FileAccess.open(LEVELS_DIR + file_name, FileAccess.READ)
			if f:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed and parsed.has("name"):
					levels.append({"file": file_name, "name": parsed["name"]})
				else:
					levels.append({"file": file_name, "name": file_name.get_basename()})
		file_name = dir.get_next()
	return levels


func delete_level(file_name: String) -> bool:
	_ensure_levels_dir()
	var path := LEVELS_DIR + file_name
	var dir := DirAccess.open(LEVELS_DIR)
	if dir:
		return dir.remove(file_name) == OK
	return false
