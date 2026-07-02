extends Node2D
# Test headless de las mejoras del dash (hellbat) y del medic.
# Correr: godot --headless --path . res://tests/dash_medic_upgrades_test.tscn

var main_node: Node2D
var hellbat: Node2D
var medic1: Node2D
var red: Node2D
var medic2: Node2D
var marine2: Node2D
var medic3: Node2D
var marine3: Node2D
var marine4: Node2D
var marine4_d0: float = 0.0
var red_hp0: float = 0.0
var medic2_hp0: float = 0.0
var t: float = 0.0
var fire_t: float = -1.0
var checked_early := false
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
		# Hellbat
		cfg["dash_damage"] = 10.0
		cfg["dash_distance"] = 150.0
		cfg["dash_upgrade_stun"] = true
		cfg["stun_radius"] = 80.0
		cfg["stun_duration"] = 2.0
		cfg["dash_upgrade_shield"] = true
		cfg["dash_shield_amount"] = 60.0
		cfg["dash_shield_duration"] = 6.0
		cfg["dash_upgrade_napalm"] = true
		cfg["napalm_duration"] = 6.0
		cfg["napalm_dps_light"] = 25.0
		cfg["napalm_dps_heavy"] = 15.0
		cfg["napalm_width"] = 15.0
		# Medic
		cfg["medic_heal_amount"] = 2.0
		cfg["medic_heal_rate"] = 0.5
		cfg["medic_upgrade_selfheal"] = true
		cfg["medic_upgrade_atk"] = true
		cfg["medic_atk_bonus"] = 0.2
		cfg["medic_upgrade_sprint"] = true
		cfg["medic_sprint_range"] = 200.0
		cfg["medic_sprint_bonus"] = 0.4
		cfg["medic_sprint_hp_pct"] = 0.5
		cfg["medic_upgrade_overheal"] = true
		cfg["medic_overheal_max"] = 50.0
		cfg["blue_regen"] = 0.0
		for ut in GameData.BLUE_UNITS:
			GameData.BLUE_UNITS[ut]["vision_range"] = 8.0
		GameData.wave_config["auto"] = false
		# Hellbat sin daño propio para no ensuciar la cuenta de HP del rojo
		GameData.BLUE_UNITS[GameData.UnitType.BRAVO]["damage"] = 0.0
		GameData.BLUE_UNITS[GameData.UnitType.BRAVO]["bonus_vs_light"] = 0.0
		GameData.BLUE_UNITS[GameData.UnitType.BRAVO]["bonus_vs_heavy"] = 0.0

		# Cluster 1: dash con las 3 mejoras
		main_node._spawn_blue_unit(GameData.UnitType.BRAVO, Vector2(400, 300), GameData.Lane.NORTH)
		main_node._spawn_blue_unit(GameData.UnitType.CHARLIE, Vector2(450, 300), GameData.Lane.NORTH)
		main_node._spawn_red_unit(GameData.UnitType.CHARLIE, Vector2(520, 300), GameData.Lane.NORTH)
		hellbat = GameData.blue_units[0]
		medic1 = GameData.blue_units[1]
		red = GameData.red_units[0]
		red_hp0 = red.current_hp

		main_node._execute_dash(hellbat, Vector2(550, 300))
		_check(hellbat.position.is_equal_approx(Vector2(550, 300)), "hellbat termina el dash en destino")
		_check(medic1.shield_hp == 60.0, "aliado sobre el recorrido recibe 60 de escudo")
		_check(red._stun_timer > 1.9, "enemigo cerca del final queda paralizado")
		_check(absf(red.current_hp - (red_hp0 - 10.0)) < 0.01, "daño del dash aplicado")

		# Cluster 2: medic con selfheal + atk + sprint
		main_node._spawn_blue_unit(GameData.UnitType.CHARLIE, Vector2(900, 600), GameData.Lane.NORTH)
		main_node._spawn_blue_unit(GameData.UnitType.ALPHA, Vector2(920, 600), GameData.Lane.NORTH)
		medic2 = GameData.blue_units[2]
		marine2 = GameData.blue_units[3]
		medic2.current_hp = medic2.max_hp - 20.0
		medic2_hp0 = medic2.current_hp
		marine2.current_hp = 5.0
		# Anclado: con vision_range el marine idle perseguiria al rojo y rompe las cuentas
		marine2.move_speed = 0.0

		# Cluster 3: medic con sobrecura sobre aliado full de vida
		main_node._spawn_blue_unit(GameData.UnitType.CHARLIE, Vector2(1100, 150), GameData.Lane.NORTH)
		main_node._spawn_blue_unit(GameData.UnitType.ALPHA, Vector2(1120, 150), GameData.Lane.NORTH)
		medic3 = GameData.blue_units[4]
		marine3 = GameData.blue_units[5]
		# Anclados: que no persigan y saquen a marine3 de rango de curacion
		medic3.move_speed = 0.0
		marine3.move_speed = 0.0

		# Cluster 4: marine idle que debe perseguir al rojo por rango de vision
		main_node._spawn_blue_unit(GameData.UnitType.ALPHA, Vector2(920, 300), GameData.Lane.NORTH)
		marine4 = GameData.blue_units[6]
		marine4_d0 = marine4.global_position.distance_to(red.global_position)
		fire_t = t
		return

	var elapsed := t - fire_t
	if not checked_early and elapsed > 0.3:
		checked_early = true
		_check(absf(medic2._speed_mult - 1.4) < 0.01, "medic con sprint por aliado herido cerca")
		var d_now := marine4.global_position.distance_to(red.global_position)
		_check(d_now < marine4_d0 - 10.0, "marine idle persigue enemigo dentro del rango de vision")
		_check(marine2._heal_atk_timer > 0.0, "aliado curado tiene buff de ataque activo")
		_check(absf(marine2._atk_mult - 1.2) < 0.01, "buff de ataque = +20%%")
		_check(medic2.current_hp > medic2_hp0 + 0.5, "medic se cura a si mismo al curar")

	if elapsed > 1.4:
		done = true
		if is_instance_valid(red):
			var napalm_dmg: float = 25.0 if red.armor_type == "light" else 15.0
			_check(absf(red.current_hp - (red_hp0 - 10.0 - napalm_dmg)) < 0.01,
				"napalm hizo 1 tick por armadura (esperado %.0f, real %.0f)" % [red_hp0 - 10.0 - napalm_dmg, red.current_hp])
			_check(red._stun_timer > 0.0, "paralisis sigue activa dentro de los 2s")
		else:
			_check(false, "rojo deberia seguir vivo")
		_check(marine3.shield_hp >= 4.0 and marine3.shield_hp <= 50.0,
			"sobrecura genero escudo en aliado full (real %.1f)" % marine3.shield_hp)
		print("DASH+MEDIC UPGRADES TEST: " + ("FAILED" if _failed else "PASSED"))
		get_tree().quit(1 if _failed else 0)
