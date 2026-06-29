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
var dragging_unit: Node2D = null
var drag_offset: Vector2 = Vector2.ZERO
var drag_original_pos: Vector2 = Vector2.ZERO

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

	GameData.reset_game()
	GameData.red_gold = 200
	GameData.blue_gold = 200
	GameData.game_phase = GameData.GamePhase.PLAYING

	hud.red_purchase_requested.connect(_on_red_purchase_requested)
	hud.blue_purchase_requested.connect(_on_blue_purchase_requested)
	hud.blue_factory_requested.connect(_on_blue_factory_requested)
	hud.restart_requested.connect(_on_restart_requested)
	hud.red_gold_set_requested.connect(_on_red_gold_set_requested)
	hud.blue_gold_set_requested.connect(_on_blue_gold_set_requested)

	_create_bases()
	queue_redraw()


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
	# 4 red bases behind each side zone
	var base_offset := 30.0
	var red_positions := {
		"north": Vector2((north_min.x + north_max.x) / 2.0, north_min.y - base_offset),
		"south": Vector2((south_min.x + south_max.x) / 2.0, south_max.y + base_offset),
		"west":  Vector2(west_min.x - base_offset, (west_min.y + west_max.y) / 2.0),
		"east":  Vector2(east_max.x + base_offset, (east_min.y + east_max.y) / 2.0),
	}
	for zone_name in red_positions:
		var base := Node2D.new()
		base.set_script(BASE_SCRIPT)
		base.position = red_positions[zone_name]
		base.team = GameData.Team.RED
		base.destroyed.connect(_on_base_destroyed)
		add_child(base)
		GameData.red_bases.append(base)

	# 1 blue base in center
	var bb := Node2D.new()
	bb.set_script(BASE_SCRIPT)
	bb.position = center_pos
	bb.team = GameData.Team.BLUE
	bb.attack_range_rect = Rect2(center_min, center_max - center_min)
	bb.destroyed.connect(_on_base_destroyed)
	add_child(bb)
	GameData.blue_base = bb


func _on_base_destroyed(base_node: Node2D) -> void:
	if base_node.team == GameData.Team.RED:
		GameData.red_bases.erase(base_node)
		if GameData.red_bases.is_empty():
			GameData.game_phase = GameData.GamePhase.WIN
	else:
		GameData.blue_base = null
		GameData.game_phase = GameData.GamePhase.GAME_OVER


# --- Purchase / placement ---

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


func _on_restart_requested() -> void:
	for child in player_units_node.get_children():
		child.queue_free()
	for child in enemy_units_node.get_children():
		child.queue_free()
	# Remove old bases
	for b in GameData.red_bases:
		if is_instance_valid(b):
			b.queue_free()
	if is_instance_valid(GameData.blue_base):
		GameData.blue_base.queue_free()

	GameData.reset_game()
	GameData.red_gold = 200
	GameData.blue_gold = 200

	placement_mode = false
	dragging_unit = null

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
				var side_lane := _get_side_lane_at(pos)
				if side_lane >= 0:
					var cell_pos := _snap_red_grid(pos)
					if not _is_cell_occupied(cell_pos, GameData.Team.RED):
						if GameData.spend_gold(GameData.Team.RED, cost):
							_spawn_red_unit(placement_type, cell_pos, _get_side_lane_at(cell_pos))
						if GameData.red_gold < cost:
							placement_mode = false
							hud.show_placement_hint(false)
			else:
				var center_lane := _get_center_lane_at(pos)
				if center_lane >= 0:
					var cell_pos := _snap_blue_grid(pos)
					if not _is_cell_occupied(cell_pos, GameData.Team.BLUE):
						if GameData.spend_gold(GameData.Team.BLUE, cost):
							_spawn_blue_unit(placement_type, cell_pos, _get_center_lane_at(cell_pos))
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
			# Click on red zone → launch that lane
			var launch_lane := _get_side_lane_at(pos)
			if launch_lane >= 0:
				_launch_red_lane(launch_lane)
				get_viewport().set_input_as_handled()
				return
			var unit := _find_unit_at(pos)
			if unit and not unit.get("attacking"):
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
				if unit and not unit.get("is_base"):
					_sell_unit(unit)
					queue_redraw()
					get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if dragging_unit and is_instance_valid(dragging_unit):
				var pos := get_global_mouse_position()
				var target_pos := pos + drag_offset
				if dragging_unit.get("is_base"):
					# ponytail: bases drop anywhere, no clamping
					pass
				elif dragging_unit.team == GameData.Team.RED:
					target_pos = _snap_red_grid(target_pos)
					if _is_cell_occupied(target_pos, GameData.Team.RED, dragging_unit):
						target_pos = drag_original_pos
					else:
						dragging_unit.lane = _get_side_lane_at(target_pos)
				else:
					target_pos = _snap_blue_grid(target_pos)
					if _is_cell_occupied(target_pos, GameData.Team.BLUE, dragging_unit):
						target_pos = drag_original_pos
					else:
						dragging_unit.lane = _get_center_lane_at(target_pos)
				dragging_unit.position = target_pos
				dragging_unit.queue_redraw()
				dragging_unit = null
				queue_redraw()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and dragging_unit and is_instance_valid(dragging_unit):
		var pos := get_global_mouse_position()
		dragging_unit.position = pos + drag_offset
		if not dragging_unit.get("is_base") and dragging_unit.team == GameData.Team.BLUE:
			var clamped_pos := _clamp_to_center_zone(dragging_unit.position)
			var new_lane := _get_center_lane_at(clamped_pos)
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


func _sell_unit(unit: Node2D) -> void:
	var team_enum: GameData.Team = unit.team as GameData.Team
	GameData.add_gold(team_enum, unit.unit_cost / 2)
	GameData.unregister_unit(unit, team_enum)
	unit.queue_free()


const BASE_CLICK_RADIUS := 20.0

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
	# Also check bases (larger click radius)
	for b in GameData.red_bases:
		if is_instance_valid(b):
			var dist := pos.distance_to(b.global_position)
			if dist < BASE_CLICK_RADIUS and dist < closest_dist:
				closest_dist = dist
				closest = b
	if is_instance_valid(GameData.blue_base):
		var dist := pos.distance_to(GameData.blue_base.global_position)
		if dist < BASE_CLICK_RADIUS and dist < closest_dist:
			closest = GameData.blue_base
	return closest


func _process(_delta: float) -> void:
	if placement_mode or dragging_unit or zone_dragging:
		queue_redraw()


func _launch_red_lane(lane: int) -> void:
	for unit in GameData.red_units:
		if is_instance_valid(unit) and unit.lane == lane and not unit.attacking:
			unit.attacking = true


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

		var ghalf := GameData.BLUE_CELL_SIZE * 0.4
		draw_rect(Rect2(ghost_pos.x - ghalf, ghost_pos.y - ghalf, ghalf * 2, ghalf * 2), ghost_color)
		if in_zone and not overlapping:
			var outline := Color.WHITE if placement_team == GameData.Team.RED else Color(0.3, 0.5, 1.0)
			outline.a = 0.5
			draw_rect(Rect2(ghost_pos.x - ghalf, ghost_pos.y - ghalf, ghalf * 2, ghalf * 2), outline, false, 0.75)

	# Drag highlight
	if dragging_unit and is_instance_valid(dragging_unit) \
			and GameData.game_phase == GameData.GamePhase.PLAYING:
		var unit_pos := dragging_unit.position
		var snap_pos: Vector2
		var team_id: int = dragging_unit.team
		if team_id == GameData.Team.RED:
			snap_pos = _snap_red_grid(unit_pos)
		else:
			snap_pos = _snap_blue_grid(unit_pos)
		var is_overlap := _is_cell_occupied(snap_pos, team_id, dragging_unit)
		var highlight_color := Color(1, 0.2, 0.2, 0.7) if is_overlap else Color(1, 1, 0, 0.7)
		var hs := GameData.BLUE_CELL_SIZE * 0.5
		draw_rect(Rect2(snap_pos.x - hs, snap_pos.y - hs, hs * 2, hs * 2), highlight_color, false, 1.0)

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
