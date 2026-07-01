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

# ponytail: collision avoidance — hitbox a bit bigger than the body so units
# keep a small gap instead of sitting on top of each other. Body half = 8px;
# two units stay ~one cell (20px) apart at rest.
var radius: float = GameData.BLUE_CELL_SIZE * 0.5
# How hard separation pushes relative to move_speed. >1 lets it overcome seek
# enough to unstick overlaps, but stays soft so the horde compresses and flows.
const SEPARATION_WEIGHT: float = 1.4
# Cap the summed push so a unit surrounded asymmetrically can't fling away.
const MAX_SEPARATION: float = 2.0

# ponytail: blue RTS select+move
var move_target: Vector2 = Vector2.ZERO
var moving: bool = false
var attack_move: bool = false
var selected: bool = false
var forced_target: Node2D = null

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

	# ponytail: passive regen for blue units
	if team == GameData.Team.BLUE and current_hp < max_hp:
		current_hp = minf(current_hp + GameData.ability_config["blue_regen"] * delta, max_hp)
		queue_redraw()

	# Clear dead forced target
	if forced_target != null and not is_instance_valid(forced_target):
		forced_target = null

	if team == GameData.Team.RED:
		# ponytail: red always attacks from spawn, no idle/launch flow
		target = _find_closest_enemy()
		if target and global_position.distance_to(target.global_position) <= attack_range:
			# In range: stop pushing forward, but still separate (spread the line).
			if fire_cooldown <= 0.0:
				_shoot()
				fire_cooldown = fire_rate
			_move_with_separation(Vector2.ZERO, delta)
		elif target:
			var dir := (target.global_position - global_position).normalized()
			_move_with_separation(dir, delta)
		else:
			var dir := (GameData.get_zone_center() - global_position).normalized()
			_move_with_separation(dir, delta)
	elif team == GameData.Team.BLUE:
		if moving:
			var arrived := global_position.distance_to(move_target) < 2.0
			if arrived:
				moving = false
				attack_move = false
				_move_with_separation(Vector2.ZERO, delta)
			else:
				var fighting := false
				var chase_dir := Vector2.ZERO
				# Attack-move: stop to fight, resume when target dies or leaves range
				if attack_move:
					if unit_type == GameData.UnitType.CHARLIE:
						var ally := _find_ally_target(true)
						if ally:
							fighting = true
							_heal_tick(delta)
					elif damage > 0.0:
						target = _find_closest_enemy()
						if target:
							var dist_to_target := global_position.distance_to(target.global_position)
							if dist_to_target <= attack_range:
								fighting = true
								if fire_cooldown <= 0.0:
									_shoot()
									fire_cooldown = fire_rate
							elif flame_arc > 0.0 and dist_to_target <= GameData.TILE_SIZE * 6.0:
								# ponytail: hellbat aggro — chase enemies on the path, max 6 tiles
								chase_dir = (target.global_position - global_position).normalized()
				if fighting:
					_move_with_separation(Vector2.ZERO, delta)
				elif chase_dir != Vector2.ZERO:
					_move_with_separation(chase_dir, delta)
				else:
					var dir := (move_target - global_position).normalized()
					_move_with_separation(dir, delta)
		elif unit_type == GameData.UnitType.CHARLIE:
			_heal_tick(delta)
			# ponytail: idle medic walks toward injured allies
			var chase := _find_ally_target(true, true)
			if chase and global_position.distance_to(chase.global_position) > attack_range:
				_move_with_separation((chase.global_position - global_position).normalized(), delta)
			else:
				_move_with_separation(Vector2.ZERO, delta)
		elif forced_target != null and is_instance_valid(forced_target):
			# Right-click focus: chase and attack forced target
			target = forced_target
			var dist_ft := global_position.distance_to(target.global_position)
			if dist_ft <= attack_range:
				if fire_cooldown <= 0.0:
					_shoot()
					fire_cooldown = fire_rate
				_move_with_separation(Vector2.ZERO, delta)
			else:
				_move_with_separation((target.global_position - global_position).normalized(), delta)
		else:
			# Idle: auto-attack enemies in range
			target = _find_closest_enemy()
			if target and global_position.distance_to(target.global_position) <= attack_range:
				if fire_cooldown <= 0.0:
					_shoot()
					fire_cooldown = fire_rate
			_move_with_separation(Vector2.ZERO, delta)

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


# ponytail: separation steering. Sums a push away from every near neighbor
# (own + enemy team), weighted by how deep the overlap is. Only looks at units
# in nearby grid cells, so cost scales with local density, not total count.
func _separation_velocity() -> Vector2:
	var push := Vector2.ZERO
	# Query radius = our reach to the farthest possible touching neighbor.
	var query_r := radius + radius
	for other in GameData.get_nearby_units(global_position, query_r):
		if other == self or not is_instance_valid(other):
			continue
		# ponytail: red can't push blue — blues hold ground, reds go around
		if team == GameData.Team.BLUE and other.team == GameData.Team.RED:
			continue
		var offset: Vector2 = global_position - other.global_position
		var d: float = offset.length()
		var min_dist: float = radius + other.radius
		if d >= min_dist:
			continue
		if d > 0.01:
			# Closer = stronger push (linear falloff to 0 at min_dist).
			push += (offset / d) * (1.0 - d / min_dist)
		else:
			# Exactly stacked: scatter in a stable per-unit direction so they
			# don't freeze into an immobile ball.
			var ang := float(get_instance_id() % 628) / 100.0
			push += Vector2(cos(ang), sin(ang))
	return push.limit_length(MAX_SEPARATION)


# Combines a desired seek direction (normalized, or ZERO when holding position)
# with separation + base avoidance, then advances.
func _move_with_separation(seek_dir: Vector2, delta: float) -> void:
	# Steer around bases if the seek path is blocked
	var steered_dir := seek_dir
	if seek_dir != Vector2.ZERO:
		steered_dir = _steer_around_bases(seek_dir)
	var vel := steered_dir * move_speed + _separation_velocity() * move_speed * SEPARATION_WEIGHT
	# Hard push out of any base we're overlapping
	vel += _base_push() * move_speed * 3.0
	if vel != Vector2.ZERO:
		position += vel * delta


# Push units out if they overlap a base's collision circle.
func _base_push() -> Vector2:
	var push := Vector2.ZERO
	var bases: Array = []
	if is_instance_valid(GameData.blue_base):
		bases.append(GameData.blue_base)
	for rb in GameData.red_bases:
		if is_instance_valid(rb):
			bases.append(rb)
	for b in bases:
		var offset: Vector2 = global_position - b.global_position
		var d := offset.length()
		var min_dist: float = b.collision_radius + radius
		if d < min_dist and d > 0.01:
			push += (offset / d) * (1.0 - d / min_dist)
		elif d <= 0.01:
			var ang := float(get_instance_id() % 628) / 100.0
			push += Vector2(cos(ang), sin(ang))
	return push.limit_length(2.0)


# If the direct seek path goes through a base, steer around it.
func _steer_around_bases(seek_dir: Vector2) -> Vector2:
	var bases: Array = []
	if is_instance_valid(GameData.blue_base):
		bases.append(GameData.blue_base)
	for rb in GameData.red_bases:
		if is_instance_valid(rb):
			bases.append(rb)
	var result := seek_dir
	for b in bases:
		var to_base: Vector2 = b.global_position - global_position
		var dist_to_base := to_base.length()
		var avoid_radius: float = b.collision_radius + radius + 4.0
		# Only care about bases ahead of us and close enough to matter
		if dist_to_base > avoid_radius * 3.0 or dist_to_base < 0.01:
			continue
		# Project to see if our path goes near the base
		var dot := result.dot(to_base.normalized())
		if dot <= 0.0:
			continue  # base is behind us
		# Closest point on our movement ray to the base center
		var proj_len := result.dot(to_base)
		var closest_on_ray := result * proj_len
		var perp := to_base - closest_on_ray
		var perp_dist := perp.length()
		if perp_dist >= avoid_radius:
			continue  # path doesn't intersect
		# Steer perpendicular: pick the side that requires less turning
		var tangent := Vector2(-to_base.y, to_base.x).normalized()
		if result.dot(tangent) < 0.0:
			tangent = -tangent
		# Blend: the closer to the base, the harder the steer
		var urgency := clampf(1.0 - perp_dist / avoid_radius, 0.0, 1.0)
		result = (result.normalized() * (1.0 - urgency) + tangent * urgency).normalized()
	return result


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
	# Red units target blue base
	if team == GameData.Team.RED:
		if is_instance_valid(GameData.blue_base):
			var dist := global_position.distance_to(GameData.blue_base.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = GameData.blue_base
	# Blue units target red bases
	if team == GameData.Team.BLUE:
		for rb in GameData.red_bases:
			if is_instance_valid(rb):
				var dist := global_position.distance_to(rb.global_position)
				if dist < closest_dist:
					closest_dist = dist
					closest = rb
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
	forced_target = null


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


func _find_ally_target(require_injured: bool, any_range: bool = false) -> Node2D:
	var best: Node2D = null
	var best_ratio: float = INF
	var heal_range: float = attack_range
	for ally in GameData.blue_units:
		if ally == self or not is_instance_valid(ally):
			continue
		if not any_range and global_position.distance_to(ally.global_position) > heal_range:
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
