extends Node2D

const UNIT_SCENE := preload("res://scenes/unit.tscn")
const BASE_SCRIPT := preload("res://scripts/base.gd")

# Zone rects computed from GameData params.
# Blue = center, Red = sides (N/S/E/W).
var center_min: Vector2
var center_max: Vector2
var center_pos: Vector2
var north_min: Vector2
var north_max: Vector2
var south_min: Vector2
var south_max: Vector2
var west_min: Vector2
var west_max: Vector2
var east_min: Vector2
var east_max: Vector2

const UNIT_CLICK_RADIUS := 9.0
const UNIT_MIN_DISTANCE := 16.0

var placement_mode: bool = false
var placement_type: int = -1
var placement_team: int = GameData.Team.RED
var selected_units: Array = []  # RTS multi-select
var _bomb_effects: Array = []  # [{pos, timer, radius}]
var _ability_aiming: String = ""  # "bomb", "dash", "shield" or ""
var _ability_aim_unit: Node2D = null
var _dash_effects: Array = []  # [{start, end, timer}]
var _wave_timer: float = 0.0
var _wave_number: int = 0

# Box selection (drag-select)
var _box_selecting: bool = false
var _box_start: Vector2 = Vector2.ZERO
var _box_end: Vector2 = Vector2.ZERO
const BOX_SELECT_THRESHOLD := 5.0  # minimum drag in px to count as box select

# Zone edge dragging (active when F1 panel visible)
var zone_dragging: bool = false
var zone_drag_zone: String = ""
var zone_drag_side: String = ""   # "top", "bottom", "left", "right", "body"
var zone_drag_start: Vector2 = Vector2.ZERO
const EDGE_THRESHOLD := 10.0

@onready var player_units_node: Node2D = $PlayerUnits
@onready var enemy_units_node: Node2D = $EnemyUnits
@onready var hud: CanvasLayer = $HUD


func _ready() -> void:
	_recompute_zones()
	GameData.zones_changed.connect(_on_zones_changed)
	GameData.level_loaded.connect(_on_level_loaded)

	GameData.reset_game()
	GameData.game_phase = GameData.GamePhase.PLAYING

	hud.red_purchase_requested.connect(_on_red_purchase_requested)
	hud.blue_purchase_requested.connect(_on_blue_purchase_requested)
	hud.restart_requested.connect(_on_restart_requested)
	hud.wave_requested.connect(_on_wave_requested)

	_create_bases()
	queue_redraw()


func _on_level_loaded() -> void:
	_on_restart_requested()


func _recompute_zones() -> void:
	center_min = GameData.zone_rects["center"][0]
	center_max = GameData.zone_rects["center"][1]
	center_pos = (center_min + center_max) / 2.0
	north_min = GameData.zone_rects["north"][0]
	north_max = GameData.zone_rects["north"][1]
	south_min = GameData.zone_rects["south"][0]
	south_max = GameData.zone_rects["south"][1]
	west_min = GameData.zone_rects["west"][0]
	west_max = GameData.zone_rects["west"][1]
	east_min = GameData.zone_rects["east"][0]
	east_max = GameData.zone_rects["east"][1]


func _on_zones_changed() -> void:
	_recompute_zones()
	queue_redraw()


# --- Bases ---

func _create_bases() -> void:
	_recompute_zones()

	# 1 blue base in center
	var cfg := GameData.base_config
	var bb := Node2D.new()
	bb.set_script(BASE_SCRIPT)
	bb.position = center_pos
	bb.team = GameData.Team.BLUE
	bb.max_hp = cfg["blue_hp"]
	bb.current_hp = cfg["blue_hp"]
	bb.base_damage = cfg["blue_damage"]
	bb.fire_rate = cfg["blue_fire_rate"]
	bb.can_attack = cfg["blue_can_attack"]
	bb.attack_range_rect = Rect2(center_min, center_max - center_min)
	bb.destroyed.connect(_on_base_destroyed)
	add_child(bb)
	GameData.blue_base = bb

	# Red bases in side zones (optional)
	if cfg["red_bases_enabled"]:
		_create_red_bases()


func _create_red_bases() -> void:
	var cfg := GameData.base_config
	var zone_data := [
		["north", north_min, north_max],
		["south", south_min, south_max],
		["east", east_min, east_max],
		["west", west_min, west_max],
	]
	for zd in zone_data:
		var zmin: Vector2 = zd[1]
		var zmax: Vector2 = zd[2]
		var rb := Node2D.new()
		rb.set_script(BASE_SCRIPT)
		rb.position = (zmin + zmax) / 2.0
		rb.team = GameData.Team.RED
		rb.max_hp = cfg["red_base_hp"]
		rb.current_hp = cfg["red_base_hp"]
		rb.base_damage = cfg["red_base_damage"]
		rb.fire_rate = cfg["red_base_fire_rate"]
		rb.can_attack = cfg["red_can_attack"]
		rb.attack_range_rect = Rect2(zmin, zmax - zmin)
		rb.destroyed.connect(_on_base_destroyed)
		add_child(rb)
		GameData.red_bases.append(rb)


func _on_base_destroyed(base_node: Node2D) -> void:
	if base_node.team == GameData.Team.BLUE:
		GameData.blue_base = null
		GameData.game_phase = GameData.GamePhase.GAME_OVER
	else:
		GameData.red_bases.erase(base_node)
		_check_victory()


# --- Purchase / placement ---

func _on_red_purchase_requested(unit_type: int) -> void:
	placement_mode = true
	placement_type = unit_type
	placement_team = GameData.Team.RED
	hud.show_placement_hint(true, GameData.Team.RED)


func _on_blue_purchase_requested(unit_type: int) -> void:
	placement_mode = true
	placement_type = unit_type
	placement_team = GameData.Team.BLUE
	hud.show_placement_hint(true, GameData.Team.BLUE)


func _on_restart_requested() -> void:
	for child in player_units_node.get_children():
		child.queue_free()
	for child in enemy_units_node.get_children():
		child.queue_free()
	if is_instance_valid(GameData.blue_base):
		GameData.blue_base.queue_free()
	for rb in GameData.red_bases:
		if is_instance_valid(rb):
			rb.queue_free()

	GameData.reset_game()

	placement_mode = false
	_deselect_all()
	_box_selecting = false
	_bomb_effects.clear()
	_dash_effects.clear()
	_ability_aiming = ""
	_ability_aim_unit = null
	_wave_timer = 0.0
	_wave_number = 0

	# Recreate bases before setting phase (which triggers HUD update)
	_create_bases()
	GameData.game_phase = GameData.GamePhase.PLAYING
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	# Zone edge dragging when F1 debug panel is visible (works in any phase)
	if hud.debug_panel.visible and _handle_zone_edit_input(event):
		return

	if GameData.game_phase != GameData.GamePhase.PLAYING:
		return

	if _ability_aiming != "" and _handle_aim_input(event):
		return

	if placement_mode:
		_handle_placement_input(event)
		return

	if _handle_ability_input(event):
		return
	_handle_select_input(event)


func _handle_placement_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var pos := get_global_mouse_position()
			if placement_team == GameData.Team.RED:
				var side_lane := _get_side_lane_at(pos)
				if side_lane >= 0:
					var cell_pos := _snap_red_grid(pos)
					if not _is_cell_occupied(cell_pos, GameData.Team.RED):
						_spawn_red_unit(placement_type, cell_pos, _get_side_lane_at(cell_pos))
			else:
				var center_lane := _get_center_lane_at(pos)
				if center_lane >= 0:
					var cell_pos := _snap_blue_grid(pos)
					if not _is_cell_occupied(cell_pos, GameData.Team.BLUE):
						_spawn_blue_unit(placement_type, cell_pos, _get_center_lane_at(cell_pos))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			placement_mode = false
			hud.show_placement_hint(false)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		placement_mode = false
		hud.show_placement_hint(false)
		get_viewport().set_input_as_handled()


func _handle_ability_input(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed):
		return false
	if selected_units.is_empty():
		return false
	var cfg := GameData.ability_config

	# Attack-move: send all selected units
	if event.keycode == KEY_A:
		if not selected_units.is_empty():
			_ability_aiming = "attack_move"
			_ability_aim_unit = null  # will apply to all
			get_viewport().set_input_as_handled()
			return true

	# Find the first selected unit that can use the requested ability
	for u in selected_units:
		if not is_instance_valid(u) or u.team != GameData.Team.BLUE:
			continue
		# Marine bomb (ALPHA)
		if event.keycode == cfg["bomb_key"] and u.unit_type == GameData.UnitType.ALPHA:
			if u._bomb_cd <= 0.0:
				_ability_aiming = "bomb"
				_ability_aim_unit = u
				get_viewport().set_input_as_handled()
				return true
		# Hellbat dash (BRAVO)
		if event.keycode == cfg["dash_key"] and u.unit_type == GameData.UnitType.BRAVO:
			if u._dash_cd <= 0.0:
				_ability_aiming = "dash"
				_ability_aim_unit = u
				get_viewport().set_input_as_handled()
				return true
		# Medic shield (CHARLIE)
		if event.keycode == cfg["medic_key"] and u.unit_type == GameData.UnitType.CHARLIE:
			if u._medic_cd <= 0.0:
				_ability_aiming = "shield"
				_ability_aim_unit = u
				get_viewport().set_input_as_handled()
				return true
	return false


func _handle_aim_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _execute_aimed_ability():
				return true  # no valid target, stay in aiming
			_ability_aiming = ""
			_ability_aim_unit = null
			get_viewport().set_input_as_handled()
			return true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Right-click cancels aiming AND issues a move order
			_ability_aiming = ""
			_ability_aim_unit = null
			if not selected_units.is_empty():
				var pos := get_global_mouse_position()
				for u in selected_units:
					if is_instance_valid(u):
						u.set_move_target(pos)
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_ability_aiming = ""
		_ability_aim_unit = null
		get_viewport().set_input_as_handled()
		return true
	return false


func _execute_aimed_ability() -> bool:
	var cfg := GameData.ability_config
	var pos := get_global_mouse_position()
	match _ability_aiming:
		"bomb":
			if not is_instance_valid(_ability_aim_unit):
				return true
			for enemy in GameData.red_units.duplicate():
				if is_instance_valid(enemy) and enemy.global_position.distance_to(pos) <= cfg["bomb_radius"]:
					enemy.take_damage(cfg["bomb_damage"])
			_bomb_effects.append({"pos": pos, "timer": 0.4, "radius": cfg["bomb_radius"]})
			_ability_aim_unit._bomb_cd = cfg["bomb_cooldown"]
			return true
		"dash":
			if not is_instance_valid(_ability_aim_unit):
				return true
			_execute_dash(_ability_aim_unit, pos)
			return true
		"shield":
			if not is_instance_valid(_ability_aim_unit):
				return true
			var best: Node2D = null
			var best_dist: float = INF
			for ally in GameData.blue_units:
				if ally == _ability_aim_unit or not is_instance_valid(ally):
					continue
				var d := pos.distance_to(ally.global_position)
				if d < best_dist:
					best_dist = d
					best = ally
			if best:
				best.apply_shield(cfg["medic_shield_amount"], cfg["medic_shield_duration"])
				_ability_aim_unit._medic_cd = cfg["medic_cooldown"]
				return true
			return false  # no ally found, stay in aiming
		"attack_move":
			for u in selected_units:
				if is_instance_valid(u):
					u.set_move_target(pos, true)
			return true
	return true


const DASH_HIT_RADIUS := 15.0

func _execute_dash(unit: Node2D, target_pos: Vector2) -> void:
	var cfg := GameData.ability_config
	var start_pos := unit.global_position
	var dir := target_pos - start_pos
	var dist := dir.length()
	var max_dist: float = cfg["dash_distance"]
	if dist > max_dist:
		dir = dir.normalized() * max_dist
	var end_pos := start_pos + dir

	# Damage enemies along path
	var dmg: float = cfg["dash_damage"]
	for enemy in GameData.red_units.duplicate():
		if is_instance_valid(enemy):
			var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position, start_pos, end_pos)
			if enemy.global_position.distance_to(closest) <= DASH_HIT_RADIUS:
				enemy.take_damage(dmg)

	# Move unit
	unit.position = end_pos
	unit.moving = false
	unit._dash_cd = cfg["dash_cooldown"]

	# Trail effect
	_dash_effects.append({"start": start_pos, "end": end_pos, "timer": 0.4})


func _handle_select_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var pos := get_global_mouse_position()
		if event.pressed:
			# Start box select
			_box_selecting = true
			_box_start = pos
			_box_end = pos
		else:
			# Release: finalize selection
			_box_end = pos
			if _box_selecting:
				_box_selecting = false
				var drag_dist := _box_start.distance_to(_box_end)
				if drag_dist < BOX_SELECT_THRESHOLD:
					# Small drag = single click select
					var unit := _find_blue_unit_at(_box_start)
					_deselect_all()
					if unit:
						_select_add(unit)
				else:
					# Box select: select all blue units inside the rect
					_deselect_all()
					var sel_rect := _make_rect(_box_start, _box_end)
					for u in GameData.blue_units:
						if is_instance_valid(u) and sel_rect.has_point(u.global_position):
							_select_add(u)
				queue_redraw()
	elif event is InputEventMouseMotion and _box_selecting:
		_box_end = get_global_mouse_position()
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if not selected_units.is_empty():
			var pos := get_global_mouse_position()
			for u in selected_units:
				if is_instance_valid(u):
					u.set_move_target(pos)
			queue_redraw()


func _deselect_all() -> void:
	for u in selected_units:
		if is_instance_valid(u):
			u.selected = false
			u.queue_redraw()
	selected_units.clear()


func _select_add(unit: Node2D) -> void:
	if unit and not selected_units.has(unit):
		selected_units.append(unit)
		unit.selected = true
		unit.queue_redraw()


func _make_rect(a: Vector2, b: Vector2) -> Rect2:
	var min_p := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var max_p := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	return Rect2(min_p, max_p - min_p)


func _find_blue_unit_at(pos: Vector2) -> Node2D:
	var closest: Node2D = null
	var closest_dist: float = UNIT_CLICK_RADIUS
	for u in GameData.blue_units:
		if is_instance_valid(u):
			var dist := pos.distance_to(u.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = u
	return closest


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


# --- Grid helpers ---

func _snap_to_grid(pos: Vector2, zmin: Vector2, zmax: Vector2) -> Vector2:
	var cs := GameData.BLUE_CELL_SIZE
	var col := int((pos.x - zmin.x) / cs)
	var row := int((pos.y - zmin.y) / cs)
	col = clampi(col, 0, int((zmax.x - zmin.x) / cs) - 1)
	row = clampi(row, 0, int((zmax.y - zmin.y) / cs) - 1)
	return Vector2(zmin.x + (col + 0.5) * cs, zmin.y + (row + 0.5) * cs)


func _snap_blue_grid(pos: Vector2) -> Vector2:
	return _snap_to_grid(pos, center_min, center_max)


func _snap_red_grid(pos: Vector2) -> Vector2:
	# Snap to nearest side zone grid
	var zones := [[north_min, north_max], [south_min, south_max],
				  [east_min, east_max], [west_min, west_max]]
	var best := pos
	var best_dist := INF
	for z in zones:
		var snapped := _snap_to_grid(pos, z[0], z[1])
		var d := pos.distance_to(snapped)
		if d < best_dist:
			best_dist = d
			best = snapped
	return best


func _is_cell_occupied(cell_pos: Vector2, team: int, exclude_unit: Node2D = null) -> bool:
	if team == GameData.Team.BLUE:
		# Base occupies 3x3 cells
		if is_instance_valid(GameData.blue_base):
			var bp := GameData.blue_base.global_position
			var cs15 := GameData.BLUE_CELL_SIZE * 1.5
			if absf(cell_pos.x - bp.x) < cs15 and absf(cell_pos.y - bp.y) < cs15:
				return true
	var units: Array = GameData.blue_units if team == GameData.Team.BLUE else GameData.red_units
	for unit in units:
		if is_instance_valid(unit) and unit != exclude_unit:
			if unit.position.distance_to(cell_pos) < 1.0:
				return true
	return false


# --- Zone clamping ---

func _clamp_to_center_zone(pos: Vector2) -> Vector2:
	return Vector2(
		clampf(pos.x, center_min.x, center_max.x),
		clampf(pos.y, center_min.y, center_max.y)
	)


func _clamp_to_nearest_side_zone(pos: Vector2) -> Vector2:
	var zones := [
		[north_min, north_max],
		[south_min, south_max],
		[east_min, east_max],
		[west_min, west_max],
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


func _process(delta: float) -> void:
	# ponytail: rebuild the spatial grid once per frame BEFORE units run their
	# own _process (main is the tree root, so it processes first). Units query it
	# for separation/collision avoidance.
	GameData.rebuild_spatial_grid()

	var any_moving := false
	for u in selected_units:
		if is_instance_valid(u) and u.moving:
			any_moving = true
			break
	if placement_mode or zone_dragging or _ability_aiming != "" or _box_selecting or any_moving:
		queue_redraw()
	if not _bomb_effects.is_empty():
		for i in range(_bomb_effects.size() - 1, -1, -1):
			_bomb_effects[i]["timer"] -= delta
			if _bomb_effects[i]["timer"] <= 0.0:
				_bomb_effects.remove_at(i)
		queue_redraw()
	if not _dash_effects.is_empty():
		for i in range(_dash_effects.size() - 1, -1, -1):
			_dash_effects[i]["timer"] -= delta
			if _dash_effects[i]["timer"] <= 0.0:
				_dash_effects.remove_at(i)
		queue_redraw()
	# Victory: survive time
	if GameData.game_phase == GameData.GamePhase.PLAYING:
		GameData.time_elapsed += delta
		if GameData.victory_condition == GameData.VictoryCondition.SURVIVE_TIME:
			if GameData.time_elapsed >= GameData.victory_param:
				GameData.victory_message = "Sobreviviste %.0f segundos!" % GameData.victory_param
				GameData.game_phase = GameData.GamePhase.WIN

	# ponytail: auto wave timer
	if GameData.wave_config["auto"] and GameData.game_phase == GameData.GamePhase.PLAYING:
		_wave_timer -= delta
		if _wave_timer <= 0.0:
			_spawn_wave()
			_wave_timer = GameData.wave_config["interval"]


func _spawn_wave() -> void:
	var cfg := GameData.wave_config
	# Build flat list of unit types to spawn
	var units_to_spawn: Array = []
	for i in int(cfg["alpha_count"]):
		units_to_spawn.append(GameData.UnitType.ALPHA)
	for i in int(cfg["bravo_count"]):
		units_to_spawn.append(GameData.UnitType.BRAVO)
	for i in int(cfg["charlie_count"]):
		units_to_spawn.append(GameData.UnitType.CHARLIE)
	if units_to_spawn.is_empty():
		return
	# Collect all available grid cells across red zones
	var cs := GameData.BLUE_CELL_SIZE
	var zone_lanes := [
		[north_min, north_max, GameData.Lane.NORTH],
		[south_min, south_max, GameData.Lane.SOUTH],
		[east_min, east_max, GameData.Lane.EAST],
		[west_min, west_max, GameData.Lane.WEST],
	]
	var cells: Array = []  # [{pos, lane}]
	for zl in zone_lanes:
		var zmin: Vector2 = zl[0]
		var zmax: Vector2 = zl[1]
		var lane: int = zl[2]
		var cols := int((zmax.x - zmin.x) / cs)
		var rows := int((zmax.y - zmin.y) / cs)
		for col in cols:
			for row in rows:
				var cell_pos := Vector2(zmin.x + (col + 0.5) * cs, zmin.y + (row + 0.5) * cs)
				if not _is_cell_occupied(cell_pos, GameData.Team.RED):
					cells.append({"pos": cell_pos, "lane": lane})
	cells.shuffle()
	units_to_spawn.shuffle()
	var count := mini(units_to_spawn.size(), cells.size())
	for i in count:
		_spawn_red_unit(units_to_spawn[i], cells[i]["pos"], cells[i]["lane"])
	_wave_number += 1
	GameData.rounds_survived = _wave_number
	hud.update_wave_label(_wave_number)
	_check_victory()


func _on_wave_requested() -> void:
	_spawn_wave()


func _check_victory() -> void:
	if GameData.game_phase != GameData.GamePhase.PLAYING:
		return
	if GameData.victory_condition == GameData.VictoryCondition.NONE:
		return

	match GameData.victory_condition:
		GameData.VictoryCondition.SURVIVE_ROUNDS:
			if GameData.rounds_survived >= int(GameData.victory_param):
				GameData.victory_message = "Sobreviviste %d rondas!" % int(GameData.victory_param)
				GameData.game_phase = GameData.GamePhase.WIN
		GameData.VictoryCondition.DESTROY_RED_BASES:
			var alive := 0
			for rb in GameData.red_bases:
				if is_instance_valid(rb):
					alive += 1
			if GameData.base_config["red_bases_enabled"] and alive == 0:
				GameData.victory_message = "Todas las bases rojas destruidas!"
				GameData.game_phase = GameData.GamePhase.WIN
		GameData.VictoryCondition.GENERATE_MARINES:
			if GameData.marines_generated >= int(GameData.victory_param):
				GameData.victory_message = "Generaste %d marines!" % int(GameData.victory_param)
				GameData.game_phase = GameData.GamePhase.WIN
		# SURVIVE_TIME is checked in _process


func _spawn_red_unit(unit_type: int, pos: Vector2, lane: int) -> void:
	var unit := UNIT_SCENE.instantiate()
	unit.unit_type = unit_type
	unit.team = GameData.Team.RED
	unit.lane = lane
	unit.position = pos
	player_units_node.add_child(unit)


func _spawn_blue_unit(unit_type: int, pos: Vector2, lane: int) -> void:
	var unit := UNIT_SCENE.instantiate()
	unit.unit_type = unit_type
	unit.team = GameData.Team.BLUE
	unit.lane = lane
	unit.position = pos
	enemy_units_node.add_child(unit)
	if unit_type == GameData.UnitType.ALPHA:
		GameData.marines_generated += 1
		_check_victory()


# --- Center zone lane detection (for blue units) ---

func _get_center_lane_at(pos: Vector2) -> int:
	if not _is_in_rect(pos, center_min, center_max):
		return -1
	var dx := pos.x - center_pos.x
	var dy := pos.y - center_pos.y
	if absf(dy) >= absf(dx):
		return GameData.Lane.NORTH if dy < 0 else GameData.Lane.SOUTH
	else:
		return GameData.Lane.EAST if dx > 0 else GameData.Lane.WEST


func _is_in_rect(pos: Vector2, rect_min: Vector2, rect_max: Vector2) -> bool:
	return pos.x >= rect_min.x and pos.x <= rect_max.x \
		and pos.y >= rect_min.y and pos.y <= rect_max.y


# --- Side zone detection (for red units) ---

func _get_side_lane_at(pos: Vector2) -> int:
	if _is_in_rect(pos, north_min, north_max): return GameData.Lane.NORTH
	if _is_in_rect(pos, east_min, east_max): return GameData.Lane.EAST
	if _is_in_rect(pos, south_min, south_max): return GameData.Lane.SOUTH
	if _is_in_rect(pos, west_min, west_max): return GameData.Lane.WEST
	return -1


# --- Zone edge dragging ---

func _handle_zone_edit_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var pos := get_global_mouse_position()
			var hit := _detect_zone_edge(pos)
			if not hit.is_empty():
				zone_dragging = true
				zone_drag_zone = hit[0]
				zone_drag_side = hit[1]
				zone_drag_start = pos
				get_viewport().set_input_as_handled()
				return true
		else:
			if zone_dragging:
				zone_dragging = false
				GameData.save_zones_json()
				get_viewport().set_input_as_handled()
				return true

	elif event is InputEventMouseMotion and zone_dragging:
		_apply_zone_drag(get_global_mouse_position())
		get_viewport().set_input_as_handled()
		return true

	return false


func _detect_zone_edge(pos: Vector2) -> Array:
	var t := EDGE_THRESHOLD
	# Check all 4 edges of every zone
	for zone_name in GameData.zone_rects:
		var r: Array = GameData.zone_rects[zone_name]
		var zmin: Vector2 = r[0]
		var zmax: Vector2 = r[1]
		var in_x := pos.x >= zmin.x - t and pos.x <= zmax.x + t
		var in_y := pos.y >= zmin.y - t and pos.y <= zmax.y + t
		if in_x and absf(pos.y - zmin.y) < t: return [zone_name, "top"]
		if in_x and absf(pos.y - zmax.y) < t: return [zone_name, "bottom"]
		if in_y and absf(pos.x - zmin.x) < t: return [zone_name, "left"]
		if in_y and absf(pos.x - zmax.x) < t: return [zone_name, "right"]
	# Body drag for any zone
	for zone_name in GameData.zone_rects:
		var r: Array = GameData.zone_rects[zone_name]
		if _is_in_rect(pos, r[0], r[1]): return [zone_name, "body"]
	return []


func _apply_zone_drag(pos: Vector2) -> void:
	var r: Array = GameData.zone_rects[zone_drag_zone]
	var min_size := 20.0
	match zone_drag_side:
		"top":    r[0].y = minf(pos.y, r[1].y - min_size)
		"bottom": r[1].y = maxf(pos.y, r[0].y + min_size)
		"left":   r[0].x = minf(pos.x, r[1].x - min_size)
		"right":  r[1].x = maxf(pos.x, r[0].x + min_size)
		"body":
			var delta := pos - zone_drag_start
			r[0] += delta
			r[1] += delta
			zone_drag_start = pos
	_recompute_zones()
	queue_redraw()


func _draw_zone_handles() -> void:
	var hs := 6.0
	var colors := {
		"center": Color(1, 1, 0, 0.8),
		"north": Color(1, 0.5, 0, 0.8), "south": Color(1, 0.5, 0, 0.8),
		"west": Color(1, 0.5, 0, 0.8), "east": Color(1, 0.5, 0, 0.8),
	}
	for zone_name in GameData.zone_rects:
		var r: Array = GameData.zone_rects[zone_name]
		var zmin: Vector2 = r[0]
		var zmax: Vector2 = r[1]
		var cx := (zmin.x + zmax.x) / 2.0
		var cy := (zmin.y + zmax.y) / 2.0
		var c: Color = colors[zone_name]
		_draw_handle(Vector2(cx, zmin.y), hs, c)
		_draw_handle(Vector2(cx, zmax.y), hs, c)
		_draw_handle(Vector2(zmin.x, cy), hs, c)
		_draw_handle(Vector2(zmax.x, cy), hs, c)


func _draw_handle(pos: Vector2, size: float, color: Color) -> void:
	draw_rect(Rect2(pos.x - size / 2.0, pos.y - size / 2.0, size, size), color)


# --- Drawing ---

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.09, 0.12))

	# Blue = center + grid
	draw_rect(Rect2(center_min, center_max - center_min), Color(0.12, 0.14, 0.22))
	var cs := GameData.BLUE_CELL_SIZE
	var grid_color := Color(0.2, 0.22, 0.32)
	var x := center_min.x + cs
	while x < center_max.x:
		draw_line(Vector2(x, center_min.y), Vector2(x, center_max.y), grid_color, 0.5)
		x += cs
	var y := center_min.y + cs
	while y < center_max.y:
		draw_line(Vector2(center_min.x, y), Vector2(center_max.x, y), grid_color, 0.5)
		y += cs

	# Red = sides + grid
	var red_tint := Color(0.22, 0.12, 0.12)
	var red_grid_color := Color(0.32, 0.2, 0.2)
	for zone in [[north_min, north_max], [south_min, south_max],
				 [east_min, east_max], [west_min, west_max]]:
		var zmin: Vector2 = zone[0]
		var zmax: Vector2 = zone[1]
		draw_rect(Rect2(zmin, zmax - zmin), red_tint)
		var rx := zmin.x + cs
		while rx < zmax.x:
			draw_line(Vector2(rx, zmin.y), Vector2(rx, zmax.y), red_grid_color, 0.5)
			rx += cs
		var ry := zmin.y + cs
		while ry < zmax.y:
			draw_line(Vector2(zmin.x, ry), Vector2(zmax.x, ry), red_grid_color, 0.5)
			ry += cs

	# Borders
	var border_color := Color(0.3, 0.3, 0.4)
	_draw_zone_border(center_min, center_max, border_color)
	_draw_zone_border(north_min, north_max, border_color)
	_draw_zone_border(south_min, south_max, border_color)
	_draw_zone_border(east_min, east_max, border_color)
	_draw_zone_border(west_min, west_max, border_color)

	# Labels
	var font := ThemeDB.fallback_font
	var red_lc := Color(0.5, 0.3, 0.3, 0.7)
	var blue_lc := Color(0.3, 0.3, 0.5, 0.7)
	_draw_zone_label(font, center_min, center_max, "BLUE", blue_lc)
	_draw_zone_label(font, north_min, north_max, "N", red_lc)
	_draw_zone_label(font, south_min, south_max, "S", red_lc)
	_draw_zone_label(font, east_min, east_max, "E", red_lc)
	_draw_zone_label(font, west_min, west_max, "O", red_lc)

	# Placement ghost
	if placement_mode and GameData.game_phase == GameData.GamePhase.PLAYING:
		var mouse_pos := get_local_mouse_position()
		var ghalf := GameData.BLUE_CELL_SIZE * 0.4

		# Unit placement ghost
		var in_zone: bool
		var ghost_pos := mouse_pos
		var overlapping: bool
		if placement_team == GameData.Team.RED:
			in_zone = _get_side_lane_at(mouse_pos) >= 0
			if in_zone:
				ghost_pos = _snap_red_grid(mouse_pos)
			overlapping = in_zone and _is_cell_occupied(ghost_pos, GameData.Team.RED)
		else:
			in_zone = _get_center_lane_at(mouse_pos) >= 0
			if in_zone:
				ghost_pos = _snap_blue_grid(mouse_pos)
			overlapping = in_zone and _is_cell_occupied(ghost_pos, GameData.Team.BLUE)

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

		draw_rect(Rect2(ghost_pos.x - ghalf, ghost_pos.y - ghalf, ghalf * 2, ghalf * 2), ghost_color)
		if in_zone and not overlapping:
			var outline := Color.WHITE if placement_team == GameData.Team.RED else Color(0.3, 0.5, 1.0)
			outline.a = 0.5
			draw_rect(Rect2(ghost_pos.x - ghalf, ghost_pos.y - ghalf, ghalf * 2, ghalf * 2), outline, false, 0.75)

	# Move target indicators for all selected units
	for u in selected_units:
		if is_instance_valid(u) and u.moving:
			var mc := Color(1.0, 0.3, 0.0, 0.5) if u.attack_move else Color(1, 1, 0, 0.5)
			draw_circle(u.move_target, 3.0, mc)

	# Box selection rectangle
	if _box_selecting:
		var sel_rect := _make_rect(_box_start, _box_end)
		draw_rect(sel_rect, Color(0.2, 0.8, 0.2, 0.1))
		draw_rect(sel_rect, Color(0.3, 1.0, 0.3, 0.6), false, 1.0)

	# Ability aiming indicators
	if _ability_aiming != "":
		var mouse := get_local_mouse_position()
		match _ability_aiming:
			"bomb":
				if is_instance_valid(_ability_aim_unit):
					var radius: float = GameData.ability_config["bomb_radius"]
					draw_circle(mouse, radius, Color(1.0, 0.5, 0.0, 0.15))
					draw_arc(mouse, radius, 0, TAU, 24, Color(1.0, 0.3, 0.0, 0.5), 1.5)
			"dash":
				if is_instance_valid(_ability_aim_unit):
					var ds := _ability_aim_unit.global_position
					var dd := mouse - ds
					var max_d: float = GameData.ability_config["dash_distance"]
					if dd.length() > max_d:
						dd = dd.normalized() * max_d
					var de := ds + dd
					draw_line(ds, de, Color(1.0, 0.5, 0.0, 0.6), 2.0)
					draw_circle(de, 4.0, Color(1.0, 0.5, 0.0, 0.4))
			"shield":
				if is_instance_valid(_ability_aim_unit):
					var best: Node2D = null
					var best_dist: float = INF
					for ally in GameData.blue_units:
						if ally == _ability_aim_unit or not is_instance_valid(ally):
							continue
						var d := mouse.distance_to(ally.global_position)
						if d < best_dist:
							best_dist = d
							best = ally
					if best:
						draw_arc(best.global_position, 12.0, 0, TAU, 16, Color(0.3, 1.0, 0.5, 0.7), 2.0)
			"attack_move":
				for u in selected_units:
					if is_instance_valid(u):
						draw_line(u.global_position, mouse, Color(1.0, 0.3, 0.0, 0.15), 1.0)
				draw_circle(mouse, 3.0, Color(1.0, 0.3, 0.0, 0.7))

	# Dash trail effects
	for effect in _dash_effects:
		var da: float = effect["timer"] / 0.4
		draw_line(effect["start"], effect["end"], Color(1.0, 0.5, 0.0, da * 0.6), 3.0)

	# Bomb explosions
	for effect in _bomb_effects:
		var alpha: float = effect["timer"] / 0.4
		draw_circle(effect["pos"], effect["radius"], Color(1.0, 0.5, 0.0, alpha * 0.3))
		draw_arc(effect["pos"], effect["radius"], 0, TAU, 24, Color(1.0, 0.3, 0.0, alpha * 0.7), 2.0)

	# Zone edit handles when F1 is visible
	if hud.debug_panel.visible:
		_draw_zone_handles()


func _draw_zone_label(font: Font, zmin: Vector2, zmax: Vector2, text: String, color: Color) -> void:
	var mid := (zmin + zmax) / 2.0
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font, Vector2(mid.x - text_size.x / 2.0, mid.y + text_size.y / 4.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13, color)


func _draw_zone_border(zmin: Vector2, zmax: Vector2, color: Color) -> void:
	var rect := Rect2(zmin, zmax - zmin)
	draw_rect(rect, color, false, 1.5)
