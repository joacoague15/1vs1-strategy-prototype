extends Node2D

signal destroyed(base_node: Node2D)

var is_base := true

var max_hp: float = 300.0
var current_hp: float = 300.0
var armor_type: String = "heavy"
var team: int = GameData.Team.BLUE
var can_attack: bool = false

# Base shooting (only when can_attack == true)
var base_damage: float = 30.0
var fire_rate: float = 1.5
var fire_cooldown: float = 0.0
var attack_range_rect: Rect2 = Rect2()

# Visual
var _damage_flash_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.1
var _shot_timer: float = 0.0
var _shot_target_pos: Vector2 = Vector2.ZERO
const SHOT_LINE_DURATION: float = 0.12

# ponytail: base = 3x3 grid cells
var SQUARE_SIZE: float = GameData.BLUE_CELL_SIZE * 1.5
# Collision radius: units can't enter this circle
var collision_radius: float = GameData.BLUE_CELL_SIZE * 1.5 + 4.0


func _process(delta: float) -> void:
	if GameData.game_phase != GameData.GamePhase.PLAYING:
		return

	if can_attack:
		fire_cooldown -= delta
		if fire_cooldown <= 0.0:
			var target := _find_closest_enemy()
			if target:
				_shoot(target)
				fire_cooldown = fire_rate

	# Visual timers
	var needs_redraw := false
	if _damage_flash_timer > 0.0:
		_damage_flash_timer -= delta
		needs_redraw = true
	if _shot_timer > 0.0:
		_shot_timer -= delta
		needs_redraw = true
	if needs_redraw:
		queue_redraw()


func _find_closest_enemy() -> Node2D:
	var enemies: Array = GameData.red_units if team == GameData.Team.BLUE else GameData.blue_units
	var closest: Node2D = null
	var closest_dist: float = INF
	for enemy in enemies:
		if is_instance_valid(enemy):
			if attack_range_rect.has_point(enemy.global_position):
				var dist := global_position.distance_to(enemy.global_position)
				if dist < closest_dist:
					closest_dist = dist
					closest = enemy
	return closest


func _shoot(target: Node2D) -> void:
	_shot_timer = SHOT_LINE_DURATION
	_shot_target_pos = target.global_position
	target.take_damage(base_damage)


func take_damage(dmg: float) -> void:
	current_hp -= dmg
	_damage_flash_timer = DAMAGE_FLASH_DURATION
	queue_redraw()
	if current_hp <= 0.0:
		_die()


func _die() -> void:
	destroyed.emit(self)
	queue_free()


func _draw() -> void:
	var s := SQUARE_SIZE
	var is_blue := (team == GameData.Team.BLUE)
	var fill_color := Color(0.12, 0.15, 0.35) if is_blue else Color(0.35, 0.12, 0.12)
	var border_color := Color(0.3, 0.4, 0.8) if is_blue else Color(0.8, 0.3, 0.3)
	var shot_color := Color(0.5, 0.7, 1.0) if is_blue else Color(1.0, 0.5, 0.3)

	draw_rect(Rect2(-s, -s, s * 2, s * 2), fill_color)
	draw_rect(Rect2(-s, -s, s * 2, s * 2), border_color, false, 1.5)

	# Base label
	var font := ThemeDB.fallback_font
	var label := "B" if is_blue else "R"
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, border_color)

	# HP bar
	var bar_w := s * 2
	var bar_h := 3.0
	var bar_y := -s - 5.0
	var hp_ratio := clampf(current_hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.2, 0.0, 0.0))
	draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), Color(0.1, 0.9, 0.1))

	# Damage flash
	if _damage_flash_timer > 0.0:
		var flash_alpha: float = _damage_flash_timer / DAMAGE_FLASH_DURATION
		draw_rect(Rect2(-s, -s, s * 2, s * 2), Color(1.0, 0.85, 0.85, flash_alpha * 0.7))

	# Shot line
	if _shot_timer > 0.0:
		var line_alpha: float = _shot_timer / SHOT_LINE_DURATION
		var local_target := to_local(_shot_target_pos)
		draw_line(Vector2.ZERO, local_target, Color(shot_color.r, shot_color.g, shot_color.b, line_alpha), 1.5)
