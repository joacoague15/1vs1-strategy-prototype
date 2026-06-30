extends Node2D

@export var unit_type: int = 0
@export var team: int = GameData.Team.RED
var lane: int = GameData.Lane.NORTH

var max_hp: float = 100.0
var current_hp: float = 100.0
var damage: float = 10.0
var fire_rate: float = 1.0
var attack_range: float = 200.0
var move_speed: float = 56.0
var fire_cooldown: float = 0.0
var target: Node2D = null
var unit_cost: int = 50
var armor_type: String = "heavy"
var bonus_vs_light: float = 0.0
var bonus_vs_heavy: float = 0.0
var shield_hp: float = 0.0
var shield_timer: float = 0.0
var _bomb_cd: float = 0.0
var _dash_cd: float = 0.0
var _medic_cd: float = 0.0
var _ability_ready_flash: float = 0.0
var _heal_cooldown: float = 0.0
var _heal_line_timer: float = 0.0
var _heal_line_target_pos: Vector2 = Vector2.ZERO

# ponytail: blue RTS select+move
var move_target: Vector2 = Vector2.ZERO
var moving: bool = false
var attack_move: bool = false
var selected: bool = false

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

	if team == GameData.Team.RED:
		# ponytail: red always attacks from spawn, no idle/launch flow
		target = _find_closest_enemy()
		if target and global_position.distance_to(target.global_position) <= attack_range:
			if fire_cooldown <= 0.0:
				_shoot()
				fire_cooldown = fire_rate
		elif target:
			var dir := (target.global_position - global_position).normalized()
			position += dir * move_speed * delta
		else:
			var dir := (GameData.get_zone_center() - global_position).normalized()
			position += dir * move_speed * delta
	elif team == GameData.Team.BLUE:
		if moving:
			var arrived := global_position.distance_to(move_target) < 2.0
			var fighting := false
			# ponytail: attack-move — fight/heal in range, then resume
			if attack_move:
				if unit_type == GameData.UnitType.CHARLIE:
					var ally := _find_ally_target(true)
					if ally:
						fighting = true
						_heal_tick(delta)
				elif damage > 0.0:
					target = _find_closest_enemy()
					if target and global_position.distance_to(target.global_position) <= attack_range:
						fighting = true
						if fire_cooldown <= 0.0:
							_shoot()
							fire_cooldown = fire_rate
			if arrived:
				moving = false
				attack_move = false
			elif not fighting:
				var dir := (move_target - global_position).normalized()
				position += dir * move_speed * delta
		elif unit_type == GameData.UnitType.CHARLIE:
			# ponytail: medic heals instead of attacking
			_heal_tick(delta)
		else:
			# ponytail: "si queda quieto que ataque"
			target = _find_closest_enemy()
			if target and global_position.distance_to(target.global_position) <= attack_range:
				if fire_cooldown <= 0.0:
					_shoot()
					fire_cooldown = fire_rate

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
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			shield_hp = 0.0
		needs_redraw = true
	if _bomb_cd > 0.0:
		_bomb_cd -= delta
		if _bomb_cd <= 0.0:
			_ability_ready_flash = 0.3
	if _dash_cd > 0.0:
		_dash_cd -= delta
		if _dash_cd <= 0.0:
			_ability_ready_flash = 0.3
	if _medic_cd > 0.0:
		_medic_cd -= delta
		if _medic_cd <= 0.0:
			_ability_ready_flash = 0.3
	if _ability_ready_flash > 0.0:
		_ability_ready_flash -= delta
		needs_redraw = true
	if _heal_line_timer > 0.0:
		_heal_line_timer -= delta
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
	# Only red units target bases (blue base)
	if team == GameData.Team.RED:
		if is_instance_valid(GameData.blue_base):
			var dist := global_position.distance_to(GameData.blue_base.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = GameData.blue_base
	# ponytail: blue never targets red bases, defensive only
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

		# Full damage to everything in the cone
		var half_arc := flame_arc / 2.0
		var enemies: Array = (GameData.blue_units if team == GameData.Team.RED else GameData.red_units).duplicate()
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var to_enemy = enemy.global_position - global_position
			if to_enemy.length() > attack_range:
				continue
			var angle_diff := absf(_flame_dir.angle_to(to_enemy.normalized()))
			if angle_diff <= half_arc:
				enemy.take_damage(_damage_to(enemy))
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
	if shield_hp > 0.0:
		var absorbed := minf(shield_hp, dmg)
		shield_hp -= absorbed
		dmg -= absorbed
	current_hp -= dmg
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	queue_redraw()
	if current_hp <= 0.0:
		_die()


func set_move_target(pos: Vector2, a_move: bool = false) -> void:
	move_target = pos
	moving = true
	attack_move = a_move


func apply_shield(amount: float, duration: float) -> void:
	shield_hp = amount
	shield_timer = duration
	queue_redraw()


func _heal_tick(delta: float) -> void:
	_heal_cooldown -= delta
	if _heal_cooldown > 0.0:
		return
	var cfg := GameData.ability_config
	var ally := _find_ally_target(true)
	if not ally:
		return
	_heal_cooldown = cfg["medic_heal_rate"]
	ally.current_hp = minf(ally.current_hp + cfg["medic_heal_amount"], ally.max_hp)
	ally.queue_redraw()
	_heal_line_timer = SHOT_LINE_DURATION
	_heal_line_target_pos = ally.global_position


func _find_ally_target(require_injured: bool) -> Node2D:
	var best: Node2D = null
	var best_ratio: float = INF
	var heal_range: float = GameData.ability_config["medic_heal_range"]
	for ally in GameData.blue_units:
		if ally == self or not is_instance_valid(ally):
			continue
		if global_position.distance_to(ally.global_position) > heal_range:
			continue
		if require_injured and ally.current_hp >= ally.max_hp:
			continue
		var ratio: float = ally.current_hp / ally.max_hp
		if ratio < best_ratio:
			best_ratio = ratio
			best = ally
	return best


func _die() -> void:
	GameData.unregister_unit(self, team as GameData.Team)
	queue_free()



func _draw() -> void:
	var body_color: Color = GameData.get_unit_color(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	var is_red := (team == GameData.Team.RED)
	var half := GameData.BLUE_CELL_SIZE * 0.4
	var sq := Rect2(-half, -half, half * 2, half * 2)

	# Body
	draw_rect(sq, body_color)

	# Outline
	var outline_color := Color.WHITE if is_red else Color(0.3, 0.5, 1.0)
	draw_rect(sq, outline_color, false, 0.9)

	# ponytail: selection ring for blue units
	if selected:
		draw_arc(Vector2.ZERO, half + 2.0, 0, TAU, 16, Color(1, 1, 0, 0.85), 1.5)

	# Unit letter
	var font := ThemeDB.fallback_font
	var letter: String = GameData.get_unit_letter(
		team as GameData.Team, unit_type as GameData.UnitType
	)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7)
	draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 4.0), letter, HORIZONTAL_ALIGNMENT_CENTER, -1, 7, Color.WHITE)

	# HP bar
	var bar_w := half * 2
	var bar_h := 1.4
	var bar_y := -half - 2.0
	var hp_ratio := clampf(current_hp / max_hp, 0.0, 1.0)

	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), Color(0.1, 0.9, 0.1))

	# Shield visual
	if shield_hp > 0.0:
		draw_arc(Vector2.ZERO, half + 4.0, 0, TAU, 16, Color(0.3, 0.7, 1.0, 0.6), 1.5)
		var shield_ratio := clampf(shield_hp / maxf(GameData.ability_config["medic_shield_amount"], 1.0), 0.0, 1.0)
		draw_rect(Rect2(-bar_w / 2.0, bar_y - 3.0, bar_w * shield_ratio, bar_h), Color(0.3, 0.7, 1.0))

	# --- Ability ready flash ---
	if _ability_ready_flash > 0.0:
		var fa := _ability_ready_flash / 0.3
		var fr := half + 3.0 + (1.0 - fa) * 8.0
		draw_arc(Vector2.ZERO, fr, 0, TAU, 16, Color(1.0, 1.0, 0.3, fa * 0.8), 2.0)

	# --- Damage flash ---
	if _damage_flash_timer > 0.0:
		var flash_alpha: float = _damage_flash_timer / DAMAGE_FLASH_DURATION
		draw_rect(sq, Color(1.0, 0.85, 0.85, flash_alpha * 0.7))

	# --- Ranged shot line ---
	if _shot_timer > 0.0:
		var line_alpha: float = _shot_timer / SHOT_LINE_DURATION
		var line_color := Color(1.0, 1.0, 0.5, line_alpha)
		var local_target := to_local(_shot_target_pos)
		draw_line(Vector2.ZERO, local_target, line_color, 1.0)

	# --- Heal line (medic) ---
	if _heal_line_timer > 0.0:
		var heal_alpha: float = _heal_line_timer / SHOT_LINE_DURATION
		var local_heal := to_local(_heal_line_target_pos)
		draw_line(Vector2.ZERO, local_heal, Color(0.2, 1.0, 0.4, heal_alpha), 1.0)

	# --- Melee slash ---
	if _melee_slash_timer > 0.0:
		var slash_alpha: float = _melee_slash_timer / MELEE_SLASH_DURATION
		var slash_center = _melee_slash_dir * (half + 5.0)
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
