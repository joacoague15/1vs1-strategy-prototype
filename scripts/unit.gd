extends Node2D

@export var unit_type: int = 0
@export var team: int = GameData.Team.RED
var lane: int = GameData.Lane.NORTH

var max_hp: float = 100.0
var current_hp: float = 100.0
var damage: float = 10.0
var fire_rate: float = 1.0
var attack_range: float = 200.0
var move_speed: float = 80.0
var fire_cooldown: float = 0.0
var target: Node2D = null
var unit_cost: int = 50
var armor_type: String = "heavy"
var bonus_vs_light: float = 0.0
var bonus_vs_heavy: float = 0.0

# --- Visual feedback state ---
var _shot_timer: float = 0.0
var _shot_target_pos: Vector2 = Vector2.ZERO
const SHOT_LINE_DURATION: float = 0.12

var _damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.1

var _melee_slash_timer: float = 0.0
var _melee_slash_dir: Vector2 = Vector2.RIGHT
const MELEE_SLASH_DURATION: float = 0.12
const MELEE_RANGE_THRESHOLD: float = 50.0

# --- Firebat AOE state ---
var flame_arc: float = 0.0
var _flame_timer: float = 0.0
var _flame_dir: Vector2 = Vector2.RIGHT
var _flame_range: float = 0.0
const FLAME_DURATION: float = 0.25

const LANE_DIRECTIONS := {
	GameData.Lane.NORTH: Vector2(0, -1),
	GameData.Lane.EAST:  Vector2(1, 0),
	GameData.Lane.SOUTH: Vector2(0, 1),
	GameData.Lane.WEST:  Vector2(-1, 0),
}


func _ready() -> void:
	var data: Dictionary = GameData.get_unit_data(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	max_hp = data["hp"]
	current_hp = max_hp
	damage = data["damage"]
	attack_range = data["attack_range"] * GameData.TILE_SIZE
	fire_rate = data["fire_rate"]
	move_speed = data["move_speed"]
	unit_cost = data["cost"]
	armor_type = data.get("armor_type", "heavy")
	bonus_vs_light = data.get("bonus_vs_light", 0.0)
	bonus_vs_heavy = data.get("bonus_vs_heavy", 0.0)
	if data.has("flame_arc"):
		flame_arc = deg_to_rad(data["flame_arc"])
	else:
		flame_arc = 0.0
	GameData.register_unit(self, team as GameData.Team)


func reload_stats() -> void:
	var data: Dictionary = GameData.get_unit_data(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	var old_max_hp := max_hp
	max_hp = data["hp"]
	if old_max_hp > 0.0 and max_hp != old_max_hp:
		current_hp = clampf(current_hp * (max_hp / old_max_hp), 1.0, max_hp)
	damage = data["damage"]
	attack_range = data["attack_range"] * GameData.TILE_SIZE
	fire_rate = data["fire_rate"]
	move_speed = data["move_speed"]
	unit_cost = data["cost"]
	armor_type = data.get("armor_type", "heavy")
	bonus_vs_light = data.get("bonus_vs_light", 0.0)
	bonus_vs_heavy = data.get("bonus_vs_heavy", 0.0)
	if data.has("flame_arc"):
		flame_arc = deg_to_rad(data["flame_arc"])
	else:
		flame_arc = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	if GameData.game_phase != GameData.GamePhase.PLAYING:
		return

	fire_cooldown -= delta
	target = _find_closest_enemy()

	if target and global_position.distance_to(target.global_position) <= attack_range:
		if fire_cooldown <= 0.0:
			_shoot()
			fire_cooldown = fire_rate
	elif target:
		var dir := (target.global_position - global_position).normalized()
		position += dir * move_speed * delta
	else:
		# No enemies found, advance in default direction
		var dir: Vector2
		if team == GameData.Team.RED:
			# Red on sides, advance toward center
			dir = (GameData.get_zone_center() - global_position).normalized()
		else:
			# Blue in center, advance outward via lane
			dir = LANE_DIRECTIONS[lane]
		position += dir * move_speed * delta

	# --- Visual effect timers ---
	var needs_redraw := false
	if _shot_timer > 0.0:
		_shot_timer -= delta
		needs_redraw = true
	if _damage_flash_timer > 0.0:
		_damage_flash_timer -= delta
		needs_redraw = true
	if _melee_slash_timer > 0.0:
		_melee_slash_timer -= delta
		needs_redraw = true
	if _flame_timer > 0.0:
		_flame_timer -= delta
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func _find_closest_enemy() -> Node2D:
	var enemies: Array = GameData.blue_units if team == GameData.Team.RED else GameData.red_units
	var closest: Node2D = null
	var closest_dist: float = INF
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist := global_position.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = enemy
	# Also consider bases as targets
	if team == GameData.Team.RED:
		if is_instance_valid(GameData.blue_base):
			var dist := global_position.distance_to(GameData.blue_base.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = GameData.blue_base
	else:
		for b in GameData.red_bases:
			if is_instance_valid(b):
				var dist := global_position.distance_to(b.global_position)
				if dist < closest_dist:
					closest_dist = dist
					closest = b
	return closest


func _damage_to(enemy: Node2D) -> float:
	# ponytail: flat bonus vs light, same as SC1 bonus damage
	if bonus_vs_light > 0.0 and enemy.armor_type == "light":
		return damage + bonus_vs_light
	if bonus_vs_heavy > 0.0 and enemy.armor_type == "heavy":
		return damage + bonus_vs_heavy
	return damage


func _shoot() -> void:
	if not is_instance_valid(target):
		return

	var dist := global_position.distance_to(target.global_position)

	if flame_arc > 0.0:
		# --- Firebat flamethrower cone ---
		_flame_dir = (target.global_position - global_position).normalized()
		_flame_range = attack_range
		_flame_timer = FLAME_DURATION

		# Full damage to primary target
		target.take_damage(_damage_to(target))

		# Half damage to other enemies in the cone
		var half_arc := flame_arc / 2.0
		var enemies: Array = (GameData.blue_units if team == GameData.Team.RED else GameData.red_units).duplicate()
		for enemy in enemies:
			if not is_instance_valid(enemy) or enemy == target:
				continue
			var to_enemy = enemy.global_position - global_position
			var enemy_dist = to_enemy.length()
			if enemy_dist > attack_range:
				continue
			var angle_diff := absf(_flame_dir.angle_to(to_enemy.normalized()))
			if angle_diff <= half_arc:
				enemy.take_damage(_damage_to(enemy) * 0.5)
	elif dist <= MELEE_RANGE_THRESHOLD:
		# Melee attack
		_melee_slash_timer = MELEE_SLASH_DURATION
		_melee_slash_dir = (target.global_position - global_position).normalized()
		target.take_damage(_damage_to(target))
	else:
		# Ranged attack
		_shot_timer = SHOT_LINE_DURATION
		_shot_target_pos = target.global_position
		target.take_damage(_damage_to(target))


func take_damage(dmg: float) -> void:
	current_hp -= dmg
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	queue_redraw()
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	GameData.unregister_unit(self, team as GameData.Team)
	queue_free()



func _draw() -> void:
	var body_color: Color = GameData.get_unit_color(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	var is_red := (team == GameData.Team.RED)
	var radius := 7.5

	# Body
	draw_circle(Vector2.ZERO, radius, body_color)

	# Outline - white for red team, bright blue for blue team
	var outline_color := Color.WHITE if is_red else Color(0.3, 0.5, 1.0)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, outline_color, 1.25)

	# Unit letter
	var font := ThemeDB.fallback_font
	var letter: String = GameData.get_unit_letter(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7)
	draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 4.0), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

	# HP bar
	var bar_w := 15.0
	var bar_h := 2.0
	var bar_y := -11.0
	var hp_ratio := clampf(current_hp / max_hp, 0.0, 1.0)

	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), Color(0.1, 0.9, 0.1))

	# --- Damage flash ---
	if _damage_flash_timer > 0.0:
		var flash_alpha: float = _damage_flash_timer / DAMAGE_FLASH_DURATION
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.85, 0.85, flash_alpha * 0.7))

	# --- Ranged shot line ---
	if _shot_timer > 0.0:
		var line_alpha: float = _shot_timer / SHOT_LINE_DURATION
		var line_color := Color(1.0, 1.0, 0.5, line_alpha)
		var local_target := to_local(_shot_target_pos)
		draw_line(Vector2.ZERO, local_target, line_color, 1.0)

	# --- Melee slash ---
	if _melee_slash_timer > 0.0:
		var slash_alpha: float = _melee_slash_timer / MELEE_SLASH_DURATION
		var slash_center := _melee_slash_dir * (radius + 5.0)
		var slash_angle := _melee_slash_dir.angle()
		draw_arc(slash_center, 6.0, slash_angle - 0.8, slash_angle + 0.8, 8, Color(1.0, 0.9, 0.6, slash_alpha * 0.9), 2.0)

	# --- Flamethrower cone ---
	if _flame_timer > 0.0 and flame_arc > 0.0:
		var flame_alpha: float = _flame_timer / FLAME_DURATION
		var half_arc := flame_arc / 2.0
		var base_angle := _flame_dir.angle()
		var cone_range := _flame_range * 0.8

		# Outer layer: orange
		var segments := 12
		var points: PackedVector2Array = PackedVector2Array()
		points.append(Vector2.ZERO)
		for i in range(segments + 1):
			var t := float(i) / float(segments)
			var angle := base_angle - half_arc + t * flame_arc
			points.append(Vector2(cos(angle), sin(angle)) * cone_range)
		draw_colored_polygon(points, Color(1.0, 0.5, 0.1, flame_alpha * 0.35))

		# Inner layer: yellow core
		var inner_points: PackedVector2Array = PackedVector2Array()
		inner_points.append(Vector2.ZERO)
		var inner_range := cone_range * 0.5
		for i in range(segments + 1):
			var t := float(i) / float(segments)
			var angle := base_angle - half_arc * 0.6 + t * flame_arc * 0.6
			inner_points.append(Vector2(cos(angle), sin(angle)) * inner_range)
		draw_colored_polygon(inner_points, Color(1.0, 0.9, 0.3, flame_alpha * 0.5))

		# Arc outline
		draw_arc(Vector2.ZERO, cone_range, base_angle - half_arc, base_angle + half_arc, segments, Color(1.0, 0.6, 0.2, flame_alpha * 0.6), 1.5)

	# Lane direction arrow for blue units (center team advances outward)
	if not is_red:
		var arrow_dir: Vector2 = LANE_DIRECTIONS[lane]
		var arrow_start := arrow_dir * (radius + 3.0)
		var arrow_end := arrow_dir * (radius + 10.0)
		var arrow_color := Color(1.0, 1.0, 0.5, 0.9)
		draw_line(arrow_start, arrow_end, arrow_color, 1.0)
		var perp := Vector2(-arrow_dir.y, arrow_dir.x) * 2.0
		var head_base := arrow_dir * (radius + 6.0)
		draw_line(arrow_end, head_base + perp, arrow_color, 1.0)
		draw_line(arrow_end, head_base - perp, arrow_color, 1.0)
