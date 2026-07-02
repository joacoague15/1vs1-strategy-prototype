extends Node2D
# Test headless de las mejoras de bomba del marine.
# Correr: godot --headless --path . res://tests/bomb_upgrades_test.tscn

var main_node: Node2D
var marine: Node2D
var red: Node2D
var hp0: float = 0.0
var t: float = 0.0
var fire_t: float = -1.0
var checked_mults := false
var done := false
var _failed := false


func _ready() -> void:
	main_node = load("res://scenes/main.tscn").instantiate()
	add_child(main_node)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed = true
		push_error("FAIL: " + msg)


func _process(delta: float) -> void:
	if done:
		return
	t += delta
	if fire_t < 0.0:
		var cfg: Dictionary = GameData.ability_config
		cfg["bomb_damage"] = 10.0
		cfg["bomb_radius"] = 200.0
		cfg["bomb_cooldown"] = 3.0
		cfg["bomb_upgrade_count"] = true
		cfg["bomb_charges"] = 2
		cfg["bomb_upgrade_acid"] = true
		cfg["acid_duration"] = 6.0
		cfg["acid_damage"] = 20.0
		cfg["acid_interval"] = 1.0
		cfg["bomb_upgrade_stim"] = true
		cfg["stim_duration"] = 6.0
		cfg["stim_bonus"] = 0.4
		cfg["bomb_upgrade_slow"] = true
		cfg["slow_duration"] = 6.0
		cfg["slow_amount"] = 0.5
		cfg["bomb_upgrade_circuit"] = true
		cfg["circuit_delay"] = 0.6
		cfg["circuit_fraction"] = 0.5
		cfg["blue_regen"] = 0.0
		for ut in GameData.BLUE_UNITS:
			GameData.BLUE_UNITS[ut]["vision_range"] = 8.0
		GameData.wave_config["auto"] = false

		main_node._spawn_red_unit(GameData.UnitType.CHARLIE, Vector2(100, 100), GameData.Lane.NORTH)
		main_node._spawn_blue_unit(GameData.UnitType.ALPHA, Vector2(1200, 650), GameData.Lane.NORTH)
		red = GameData.red_units[0]
		marine = GameData.blue_units[0]
		hp0 = red.current_hp

		# Bomba 1 sobre el rojo: daño directo + areas acido/slow + circuito
		main_node._fire_bomb(marine, red.global_position)
		_check(absf(red.current_hp - (hp0 - 10.0)) < 0.01, "daño directo de bomba")
		_check(marine._bomb_cd <= 0.0, "con mejora cantidad, 1 bomba no activa cooldown")
		# Bomba 2 a los pies del marine: stim + agota cargas
		main_node._fire_bomb(marine, marine.global_position)
		_check(marine._bomb_cd > 0.0, "segunda bomba agota cargas y activa cooldown")
		_check(GameData.bomb_areas.size() == 6, "cada bomba deja 3 areas (acido/stim/slow)")
		fire_t = t
		return

	var elapsed := t - fire_t
	if not checked_mults and elapsed > 0.3:
		checked_mults = true
		_check(absf(red._speed_mult - 0.5) < 0.01, "rojo ralentizado al 50%% en area slow")
		_check(marine._stim_timer > 0.0, "marine con buff de adrenalina activo")
		_check(absf(marine._speed_mult - 1.4) < 0.01, "marine con +40%% de velocidad")

	if elapsed > 1.5:
		done = true
		# 10 (bomba) + 5 (circuito 50%) + 20 (1 tick de acido a t=1.0)
		_check(is_instance_valid(red), "rojo sigue vivo")
		if is_instance_valid(red):
			_check(absf(red.current_hp - (hp0 - 35.0)) < 0.01,
				"daño total = bomba + circuito + acido (esperado %.0f, real %.0f)" % [hp0 - 35.0, red.current_hp])
		# Round-trip de dificultad/creditos en niveles guardados
		GameData.level_difficulty = "dificil"
		GameData.level_credits = 777
		GameData.save_level("__test_nivel__")
		GameData.level_difficulty = "facil"
		GameData.level_credits = 0
		GameData.load_level("__test_nivel__")
		_check(GameData.level_difficulty == "dificil" and GameData.level_credits == 777,
			"nivel persiste dificultad y creditos")
		GameData.delete_level("__test_nivel__.json")
		print("BOMB UPGRADES TEST: " + ("FAILED" if _failed else "PASSED"))
		get_tree().quit(1 if _failed else 0)
