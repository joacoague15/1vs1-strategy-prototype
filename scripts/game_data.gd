extends Node

enum UnitType { ALPHA, BRAVO, CHARLIE }
enum GamePhase { PREPARATION, BATTLE, GAME_OVER, WIN }
enum Team { RED, BLUE }
enum Lane { NORTH, EAST, SOUTH, WEST }

signal red_gold_changed(new_amount: int)
signal blue_gold_changed(new_amount: int)
signal phase_changed(new_phase: GamePhase)
signal unit_stats_changed(team: Team, unit_type: UnitType)

var red_gold: int = 0:
	set(value):
		red_gold = value
		red_gold_changed.emit(red_gold)

var blue_gold: int = 0:
	set(value):
		blue_gold = value
		blue_gold_changed.emit(blue_gold)

var blue_factories: int = 0
var base_income: int = 50
var factory_income: int = 25
var current_wave: int = 0
var game_phase: GamePhase = GamePhase.PREPARATION:
	set(value):
		game_phase = value
		phase_changed.emit(game_phase)

var red_units: Array = []
var blue_units: Array = []

const FACTORY_COST: int = 10
const TILE_SIZE: float = 100.0

# --- Unit stats per team ---
# Keys: cost, hp, damage, attack_range (in tiles), fire_rate, move_speed, name, color
var RED_UNITS := {
	UnitType.ALPHA: {
		"name": "Zergling", "letter": "Z",
		"cost": 50, "hp": 35.0, "damage": 5.0,
		"attack_range": 0.3, "fire_rate": 0.4, "move_speed": 100.0,
		"color": Color(0.7, 0.9, 0.3),
		"armor_type": "light", "bonus_vs_light": 3.0,
	},
	UnitType.BRAVO: {
		"name": "Hydralisk", "letter": "H",
		"cost": 100, "hp": 80.0, "damage": 12.0,
		"attack_range": 2.0, "fire_rate": 0.6, "move_speed": 87.5,
		"color": Color(0.4, 0.75, 0.4),
		"armor_type": "light", "bonus_vs_light": 5.0,
	},
	UnitType.CHARLIE: {
		"name": "Roach", "letter": "R",
		"cost": 150, "hp": 140.0, "damage": 16.0,
		"attack_range": 1.6, "fire_rate": 1.5, "move_speed": 87.5,
		"color": Color(0.6, 0.5, 0.2),
		"armor_type": "heavy",
	},
}

var BLUE_UNITS := {
	UnitType.ALPHA: {
		"name": "Marine", "letter": "M",
		"cost": 50, "hp": 50.0, "damage": 6.0,
		"attack_range": 1.5, "fire_rate": 0.5, "move_speed": 75.0,
		"color": Color(0.3, 0.5, 0.9),
		"armor_type": "light",
	},
	UnitType.BRAVO: {
		"name": "Firebat", "letter": "F",
		"cost": 100, "hp": 100.0, "damage": 8.0,
		"attack_range": 2.0, "fire_rate": 1.8, "move_speed": 75.0,
		"color": Color(0.9, 0.5, 0.2),
		"flame_arc": 60.0,
		"armor_type": "heavy", "bonus_vs_light": 4.0,
	},
	UnitType.CHARLIE: {
		"name": "Tank", "letter": "T",
		"cost": 150, "hp": 200.0, "damage": 20.0,
		"attack_range": 2.8, "fire_rate": 1.0, "move_speed": 70.0,
		"color": Color(0.5, 0.5, 0.6),
		"armor_type": "heavy",
	},
}


func get_unit_data(team: Team, unit_type: UnitType) -> Dictionary:
	if team == Team.RED:
		return RED_UNITS[unit_type]
	return BLUE_UNITS[unit_type]


func get_unit_cost(team: Team, unit_type: UnitType) -> int:
	return get_unit_data(team, unit_type)["cost"]


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


func red_income() -> int:
	return base_income


func blue_income() -> int:
	return base_income + (blue_factories * factory_income)


func spend_gold(team: Team, amount: int) -> bool:
	if team == Team.RED:
		if red_gold >= amount:
			red_gold -= amount
			return true
	else:
		if blue_gold >= amount:
			blue_gold -= amount
			return true
	return false


func add_gold(team: Team, amount: int) -> void:
	if team == Team.RED:
		red_gold += amount
	else:
		blue_gold += amount


func start_preparation() -> void:
	current_wave += 1
	add_gold(Team.RED, red_income())
	add_gold(Team.BLUE, blue_income())
	game_phase = GamePhase.PREPARATION


func start_battle() -> void:
	game_phase = GamePhase.BATTLE


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


func reset_game() -> void:
	red_gold = 0
	blue_gold = 0
	blue_factories = 0
	current_wave = 0
	red_units.clear()
	blue_units.clear()
