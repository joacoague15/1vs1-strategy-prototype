extends Node2D

const UNIT_SCENE := preload("res://scenes/unit.tscn")

# Red zone: single 300x300 square centered at (640, 360).
# Blue zones 100x100 each, 10px gap from red edges.

const RED_MIN := Vector2(490, 210)
const RED_MAX := Vector2(790, 510)
const RED_CENTER := Vector2(640, 360)

# Blue zones (match red edge length, 100px deep, 10px gap from red)
const NORTH_MIN := Vector2(490, 100)
const NORTH_MAX := Vector2(790, 200)
const SOUTH_MIN := Vector2(490, 520)
const SOUTH_MAX := Vector2(790, 620)
const WEST_MIN := Vector2(380, 210)
const WEST_MAX := Vector2(480, 510)
const EAST_MIN := Vector2(800, 210)
const EAST_MAX := Vector2(900, 510)

const UNIT_CLICK_RADIUS := 9.0
const UNIT_MIN_DISTANCE := 16.0

var placement_mode: bool = false
var placement_type: int = -1
var placement_team: int = GameData.Team.RED
var dragging_unit: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var drag_original_pos: Vector2 = Vector2.ZERO

@onready var player_units_node: Node2D = $PlayerUnits
@onready var enemy_units_node: Node2D = $EnemyUnits
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	GameData.reset_game()
	GameData.red_gold = 200
	GameData.blue_gold = 200
	GameData.current_wave = 1
	GameData.game_phase = GameData.GamePhase.PREPARATION

	hud.red_purchase_requested.connect(_on_red_purchase_requested)
	hud.blue_purchase_requested.connect(_on_blue_purchase_requested)
	hud.blue_factory_requested.connect(_on_blue_factory_requested)
	hud.start_wave_requested.connect(_on_start_wave_requested)
	hud.stop_wave_requested.connect(_on_stop_wave_requested)
	hud.restart_requested.connect(_on_restart_requested)
	hud.red_gold_set_requested.connect(_on_red_gold_set_requested)
	hud.blue_gold_set_requested.connect(_on_blue_gold_set_requested)

	queue_redraw()


func _on_red_purchase_requested(unit_type: int) -> void:
	var cost := GameData.get_unit_cost(GameData.Team.RED, unit_type as GameData.UnitType)
	if GameData.red_gold >= cost:
		placement_mode = true
		placement_type = unit_type
		placement_team = GameData.Team.RED
		hud.show_placement_hint(true, GameData.Team.RED)


func _on_blue_purchase_requested(unit_type: int) -> void:
	var cost := GameData.get_unit_cost(GameData.Team.BLUE, unit_type as GameData.UnitType)
	if GameData.blue_gold >= cost:
		placement_mode = true
		placement_type = unit_type
		placement_team = GameData.Team.BLUE
		hud.show_placement_hint(true, GameData.Team.BLUE)


func _on_red_gold_set_requested(amount: int) -> void:
	GameData.red_gold = clampi(amount, 0, 9999)


func _on_blue_gold_set_requested(amount: int) -> void:
	GameData.blue_gold = clampi(amount, 0, 9999)


func _on_blue_factory_requested() -> void:
	if GameData.spend_gold(GameData.Team.BLUE, GameData.FACTORY_COST):
		GameData.blue_factories += 1


func _on_start_wave_requested() -> void:
	if GameData.game_phase != GameData.GamePhase.PREPARATION:
		return
	placement_mode = false
	dragging_unit = null
	hud.show_placement_hint(false)
	for unit in GameData.red_units:
		if is_instance_valid(unit):
			unit.save_spawn_position()
	for unit in GameData.blue_units:
		if is_instance_valid(unit):
			unit.save_spawn_position()
	GameData.start_battle()
	queue_redraw()


func _on_stop_wave_requested() -> void:
	if GameData.game_phase != GameData.GamePhase.BATTLE:
		return
	for child in get_children():
		if child is Node2D and child != player_units_node and child != enemy_units_node:
			if child.get_script() and child.get_script().resource_path.ends_with("projectile.gd"):
				child.queue_free()
	for unit in GameData.red_units:
		if is_instance_valid(unit):
			unit.reset_to_spawn()
	for unit in GameData.blue_units:
		if is_instance_valid(unit):
			unit.reset_to_spawn()
	GameData.game_phase = GameData.GamePhase.PREPARATION
	queue_redraw()


func _on_restart_requested() -> void:
	for child in player_units_node.get_children():
		child.queue_free()
	for child in enemy_units_node.get_children():
		child.queue_free()
	for child in get_children():
		if child is Node2D and child != player_units_node and child != enemy_units_node:
			if child.get_script() and child.get_script().resource_path.ends_with("projectile.gd"):
				child.queue_free()

	GameData.reset_game()
	GameData.red_gold = 200
	GameData.blue_gold = 200
	GameData.current_wave = 1
	GameData.game_phase = GameData.GamePhase.PREPARATION
	placement_mode = false
	dragging_unit = null
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if GameData.game_phase != GameData.GamePhase.PREPARATION:
		return

	if placement_mode:
		_handle_placement_input(event)
		return

	_handle_drag_input(event)


func _handle_placement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var pos := get_global_mouse_position()
			var cost := GameData.get_unit_cost(
				placement_team as GameData.Team,
				placement_type as GameData.UnitType
			)
			if placement_team == GameData.Team.RED:
				var red_lane := _get_red_zone_lane_at(pos)
				if red_lane >= 0 and not _is_position_overlapping(pos):
					if GameData.spend_gold(GameData.Team.RED, cost):
						_spawn_red_unit(placement_type, pos, red_lane)
					if GameData.red_gold < cost:
						placement_mode = false
						hud.show_placement_hint(false)
			else:
				var zone := _get_blue_zone_at(pos)
				if zone >= 0 and not _is_position_overlapping(pos):
					if GameData.spend_gold(GameData.Team.BLUE, cost):
						_spawn_blue_unit(placement_type, pos)
					if GameData.blue_gold < cost:
						placement_mode = false
						hud.show_placement_hint(false)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placement_mode = false
			hud.show_placement_hint(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		placement_mode = false
		hud.show_placement_hint(false)
		get_viewport().set_input_as_handled()


func _handle_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging_unit:
				return
			var pos := get_global_mouse_position()
			var unit := _find_unit_at(pos)
			if unit:
				dragging_unit = unit
				drag_offset = unit.position - pos
				drag_original_pos = unit.position
				get_viewport().set_input_as_handled()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if dragging_unit and is_instance_valid(dragging_unit):
				dragging_unit.position = drag_original_pos
				dragging_unit = null
				queue_redraw()
				get_viewport().set_input_as_handled()
			else:
				var pos := get_global_mouse_position()
				var unit := _find_unit_at(pos)
				if unit:
					_sell_unit(unit)
					queue_redraw()
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging_unit and is_instance_valid(dragging_unit):
				var pos := get_global_mouse_position()
				var target_pos := pos + drag_offset
				if dragging_unit.team == GameData.Team.RED:
					target_pos = _clamp_to_nearest_red_zone(target_pos)
					if _is_position_overlapping(target_pos, dragging_unit):
						target_pos = drag_original_pos
					else:
						dragging_unit.lane = _get_red_zone_lane_at(target_pos)
				else:
					target_pos = _clamp_to_nearest_blue_zone(target_pos)
					if _is_position_overlapping(target_pos, dragging_unit):
						target_pos = drag_original_pos
				dragging_unit.position = target_pos
				dragging_unit.queue_redraw()
				dragging_unit = null
				queue_redraw()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragging_unit and is_instance_valid(dragging_unit):
		var pos := get_global_mouse_position()
		dragging_unit.position = pos + drag_offset
		if dragging_unit.team == GameData.Team.RED:
			var clamped_pos := _clamp_to_nearest_red_zone(dragging_unit.position)
			var new_lane := _get_red_zone_lane_at(clamped_pos)
			if new_lane >= 0 and dragging_unit.lane != new_lane:
				dragging_unit.lane = new_lane
				dragging_unit.queue_redraw()
		get_viewport().set_input_as_handled()


# --- Overlap detection ---

func _is_position_overlapping(pos: Vector2, exclude_unit: Node2D = null) -> bool:
	for unit in GameData.red_units:
		if is_instance_valid(unit) and unit != exclude_unit:
			if pos.distance_to(unit.position) < UNIT_MIN_DISTANCE:
				return true
	for unit in GameData.blue_units:
		if is_instance_valid(unit) and unit != exclude_unit:
			if pos.distance_to(unit.position) < UNIT_MIN_DISTANCE:
				return true
	return false


# --- Zone clamping ---

func _clamp_to_nearest_red_zone(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, RED_MIN.x, RED_MAX.x),
		clampf(pos.y, RED_MIN.y, RED_MAX.y)
	)


func _clamp_to_nearest_blue_zone(pos: Vector2) -> Vector2:
	var zones := [
		[NORTH_MIN, NORTH_MAX],
		[SOUTH_MIN, SOUTH_MAX],
		[EAST_MIN, EAST_MAX],
		[WEST_MIN, WEST_MAX],
	]
	var best_pos := pos
	var best_dist := INF
	for zone in zones:
		var zmin: Vector2 = zone[0]
		var zmax: Vector2 = zone[1]
		var clamped := Vector2(
			clampf(pos.x, zmin.x, zmax.x),
			clampf(pos.y, zmin.y, zmax.y)
		)
		var dist := pos.distance_to(clamped)
		if dist < best_dist:
			best_dist = dist
			best_pos = clamped
	return best_pos


func _sell_unit(unit: Node2D) -> void:
	var team_enum: GameData.Team = unit.team as GameData.Team
	GameData.add_gold(team_enum, unit.unit_cost / 2)
	GameData.unregister_unit(unit, team_enum)
	unit.queue_free()


func _find_unit_at(pos: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = UNIT_CLICK_RADIUS
	for unit in GameData.red_units:
		if is_instance_valid(unit):
			var dist := pos.distance_to(unit.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = unit
	for unit in GameData.blue_units:
		if is_instance_valid(unit):
			var dist := pos.distance_to(unit.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = unit
	return closest


func _process(_delta: float) -> void:
	if placement_mode or dragging_unit:
		queue_redraw()

	if GameData.game_phase == GameData.GamePhase.BATTLE:
		_check_battle_end()


func _check_battle_end() -> void:
	var blue_alive := not GameData.blue_units.is_empty()
	var red_alive := not GameData.red_units.is_empty()

	if not blue_alive or not red_alive:
		_on_round_ended()


func _on_round_ended() -> void:
	for unit in GameData.red_units:
		if is_instance_valid(unit):
			unit.reset_to_spawn()
	for unit in GameData.blue_units:
		if is_instance_valid(unit):
			unit.reset_to_spawn()

	GameData.start_preparation()


func _spawn_red_unit(unit_type: int, pos: Vector2, lane: int) -> void:
	var unit := UNIT_SCENE.instantiate()
	unit.unit_type = unit_type
	unit.team = GameData.Team.RED
	unit.lane = lane
	unit.position = pos
	player_units_node.add_child(unit)


func _spawn_blue_unit(unit_type: int, pos: Vector2) -> void:
	var unit := UNIT_SCENE.instantiate()
	unit.unit_type = unit_type
	unit.team = GameData.Team.BLUE
	unit.position = pos
	enemy_units_node.add_child(unit)


# --- Red zone lane detection ---

func _get_red_zone_lane_at(pos: Vector2) -> int:
	if not _is_in_rect(pos, RED_MIN, RED_MAX):
		return -1
	var dx := pos.x - RED_CENTER.x
	var dy := pos.y - RED_CENTER.y
	if absf(dy) >= absf(dx):
		return GameData.Lane.NORTH if dy < 0 else GameData.Lane.SOUTH
	else:
		return GameData.Lane.EAST if dx > 0 else GameData.Lane.WEST


func _is_in_rect(pos: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	return pos.x >= rect_min.x and pos.x <= rect_max.x \
		and pos.y >= rect_min.y and pos.y <= rect_max.y


# --- Blue zone checks ---

func _get_blue_zone_at(pos: Vector2) -> int:
	if _is_in_rect(pos, NORTH_MIN, NORTH_MAX): return GameData.Lane.NORTH
	if _is_in_rect(pos, EAST_MIN, EAST_MAX): return GameData.Lane.EAST
	if _is_in_rect(pos, SOUTH_MIN, SOUTH_MAX): return GameData.Lane.SOUTH
	if _is_in_rect(pos, WEST_MIN, WEST_MAX): return GameData.Lane.WEST
	return -1


# --- Drawing ---

func _draw() -> void:
	# Dark background
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.09, 0.12))

	# Red zone (single 300x300 square)
	var red_tint := Color(0.22, 0.12, 0.12)
	draw_rect(Rect2(RED_MIN, RED_MAX - RED_MIN), red_tint)

	# Blue zones (4 squares)
	var blue_tint := Color(0.12, 0.14, 0.22)
	draw_rect(Rect2(NORTH_MIN, NORTH_MAX - NORTH_MIN), blue_tint)
	draw_rect(Rect2(SOUTH_MIN, SOUTH_MAX - SOUTH_MIN), blue_tint)
	draw_rect(Rect2(EAST_MIN, EAST_MAX - EAST_MIN), blue_tint)
	draw_rect(Rect2(WEST_MIN, WEST_MAX - WEST_MIN), blue_tint)

	# Zone borders
	var border_color := Color(0.3, 0.3, 0.4)
	_draw_zone_border(RED_MIN, RED_MAX, border_color)
	_draw_zone_border(NORTH_MIN, NORTH_MAX, border_color)
	_draw_zone_border(SOUTH_MIN, SOUTH_MAX, border_color)
	_draw_zone_border(EAST_MIN, EAST_MAX, border_color)
	_draw_zone_border(WEST_MIN, WEST_MAX, border_color)

	# Zone labels (centered in each 100x100 square)
	var font := ThemeDB.fallback_font
	var red_label_color := Color(0.5, 0.3, 0.3, 0.7)
	var blue_label_color := Color(0.3, 0.3, 0.5, 0.7)

	# Red zone label
	_draw_zone_label(font, RED_MIN, RED_MAX, "RED", red_label_color)

	# Blue zone labels
	_draw_zone_label(font, NORTH_MIN, NORTH_MAX, "N", blue_label_color)
	_draw_zone_label(font, SOUTH_MIN, SOUTH_MAX, "S", blue_label_color)
	_draw_zone_label(font, EAST_MIN, EAST_MAX, "E", blue_label_color)
	_draw_zone_label(font, WEST_MIN, WEST_MAX, "O", blue_label_color)

	# Placement ghost
	if placement_mode and GameData.game_phase == GameData.GamePhase.PREPARATION:
		var mouse_pos := get_local_mouse_position()
		var in_zone: bool
		if placement_team == GameData.Team.RED:
			in_zone = _get_red_zone_lane_at(mouse_pos) >= 0
		else:
			in_zone = _get_blue_zone_at(mouse_pos) >= 0

		var overlapping := in_zone and _is_position_overlapping(mouse_pos)

		var ghost_color: Color = GameData.get_unit_color(
			placement_team as GameData.Team, placement_type as GameData.UnitType
		)
		if placement_team == GameData.Team.BLUE:
			ghost_color = ghost_color.darkened(0.15)

		if not in_zone:
			ghost_color.a = 0.15
		elif overlapping:
			ghost_color = Color(1.0, 0.2, 0.2, 0.5)
		else:
			ghost_color.a = 0.5

		draw_circle(mouse_pos, 7.5, ghost_color)
		if in_zone and not overlapping:
			var outline := Color.WHITE if placement_team == GameData.Team.RED else Color(0.3, 0.5, 1.0)
			outline.a = 0.5
			draw_arc(mouse_pos, 7.5, 0, TAU, 32, outline, 0.75)

	# Drag highlight
	if dragging_unit and is_instance_valid(dragging_unit) \
			and GameData.game_phase == GameData.GamePhase.PREPARATION:
		var unit_pos := dragging_unit.position
		var clamped_pos: Vector2
		if dragging_unit.team == GameData.Team.RED:
			clamped_pos = _clamp_to_nearest_red_zone(unit_pos)
		else:
			clamped_pos = _clamp_to_nearest_blue_zone(unit_pos)
		var is_overlap := _is_position_overlapping(clamped_pos, dragging_unit)
		var highlight_color := Color(1, 0.2, 0.2, 0.7) if is_overlap else Color(1, 1, 0, 0.7)
		draw_arc(unit_pos, 10.0, 0, TAU, 32, highlight_color, 1.0)


func _draw_zone_label(font: Font, zmin: Vector2, zmax: Vector2, text: String, color: Color) -> void:
	var mid := (zmin + zmax) / 2.0
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(mid.x - text_size.x / 2.0, mid.y + text_size.y / 4.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, color)


func _draw_zone_border(zmin: Vector2, zmax: Vector2, color: Color) -> void:
	var rect := Rect2(zmin, zmax - zmin)
	draw_rect(rect, color, false, 1.5)
