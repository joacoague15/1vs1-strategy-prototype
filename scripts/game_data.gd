extends Node

enum UnitType { ALPHA, BRAVO, CHARLIE }
enum GamePhase { PLAYING, GAME_OVER, WIN }
enum Team { RED, BLUE }
enum Lane { NORTH, EAST, SOUTH, WEST }

signal phase_changed(new_phase: GamePhase)
signal unit_stats_changed(team: Team, unit_type: UnitType)
signal zones_changed
signal base_destroyed(base_node: Node2D)

var game_phase: GamePhase = GamePhase.PLAYING:
	set(value):
		game_phase = value
		phase_changed.emit(game_phase)

var red_units: Array = []
var blue_units: Array = []

# Bases
var blue_base: Node2D = null

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
	var out := {"red": {}, "blue": {}}
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


func reset_game() -> void:
	red_units.clear()
	blue_units.clear()
	blue_base = null
