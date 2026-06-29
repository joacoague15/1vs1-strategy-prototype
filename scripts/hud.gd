extends CanvasLayer

signal red_purchase_requested(unit_type: int)
signal blue_purchase_requested(unit_type: int)
signal blue_factory_requested
signal restart_requested
signal red_gold_set_requested(amount: int)
signal blue_gold_set_requested(amount: int)

# Red panel (top-left)
var red_gold_label: Label
var red_income_label: Label
var red_btn_alpha: Button
var red_btn_bravo: Button
var red_btn_charlie: Button

# Blue panel (top-right)
var blue_gold_label: Label
var blue_income_label: Label
var blue_factory_label: Label
var blue_btn_alpha: Button
var blue_btn_bravo: Button
var blue_btn_charlie: Button
var blue_btn_factory: Button

# Shared
var btn_speed: Button
var speed_index: int = 0
var placement_label: Label
var game_over_panel: Control
var win_panel: Control
var red_panel: Control
var blue_panel: Control
var bottom_panel: Control
var editor_panel: Control

# Editor spinboxes
var red_gold_spinbox: SpinBox
var blue_gold_spinbox: SpinBox
var _updating_spinbox: bool = false

# Debug menu
var debug_panel: PanelContainer
var debug_selected_team: int = GameData.Team.RED
var debug_selected_unit: int = GameData.UnitType.ALPHA
var debug_team_btn: Button
var debug_unit_btn: Button
var debug_spinboxes: Dictionary = {}
var _updating_debug: bool = false
var _debug_dragging: bool = false
var _debug_drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_red_panel(root)
	_build_blue_panel(root)
	_build_bottom_panel(root)
	_build_editor_panel(root)
	_build_placement_hint(root)
	_build_game_over_panel(root)
	_build_win_panel(root)
	_build_rps_legend(root)
	_build_debug_panel(root)

	GameData.red_gold_changed.connect(_on_red_gold_changed)
	GameData.blue_gold_changed.connect(_on_blue_gold_changed)
	GameData.phase_changed.connect(_on_phase_changed)
	_refresh_labels()
	_on_phase_changed(GameData.game_phase)


func _build_red_panel(root: Control) -> void:
	red_panel = Control.new()
	red_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(red_panel)

	var panel := PanelContainer.new()
	panel.position = Vector2(5, 5)
	red_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "ROJO"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	title_row.add_child(title)

	red_gold_label = Label.new()
	red_gold_label.add_theme_font_size_override("font_size", 15)
	title_row.add_child(red_gold_label)

	red_income_label = Label.new()
	red_income_label.add_theme_font_size_override("font_size", 14)
	red_income_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	title_row.add_child(red_income_label)

	# Unit buttons
	var unit_row := HBoxContainer.new()
	unit_row.add_theme_constant_override("separation", 4)
	vbox.add_child(unit_row)

	var rd := GameData.RED_UNITS
	red_btn_alpha = _make_button("%s $%d" % [rd[GameData.UnitType.ALPHA]["name"], rd[GameData.UnitType.ALPHA]["cost"]], 130)
	red_btn_alpha.pressed.connect(func(): red_purchase_requested.emit(GameData.UnitType.ALPHA))
	unit_row.add_child(red_btn_alpha)

	red_btn_bravo = _make_button("%s $%d" % [rd[GameData.UnitType.BRAVO]["name"], rd[GameData.UnitType.BRAVO]["cost"]], 130)
	red_btn_bravo.pressed.connect(func(): red_purchase_requested.emit(GameData.UnitType.BRAVO))
	unit_row.add_child(red_btn_bravo)

	red_btn_charlie = _make_button("%s $%d" % [rd[GameData.UnitType.CHARLIE]["name"], rd[GameData.UnitType.CHARLIE]["cost"]], 130)
	red_btn_charlie.pressed.connect(func(): red_purchase_requested.emit(GameData.UnitType.CHARLIE))
	unit_row.add_child(red_btn_charlie)


func _build_blue_panel(root: Control) -> void:
	blue_panel = Control.new()
	blue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(blue_panel)

	var panel := PanelContainer.new()
	panel.position = Vector2(830, 5)
	blue_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Title row
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	vbox.add_child(title_row)

	var title := Label.new()
	title.text = "AZUL"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.3, 0.5, 1.0))
	title_row.add_child(title)

	blue_gold_label = Label.new()
	blue_gold_label.add_theme_font_size_override("font_size", 15)
	title_row.add_child(blue_gold_label)

	blue_income_label = Label.new()
	blue_income_label.add_theme_font_size_override("font_size", 14)
	blue_income_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	title_row.add_child(blue_income_label)

	blue_factory_label = Label.new()
	blue_factory_label.add_theme_font_size_override("font_size", 14)
	title_row.add_child(blue_factory_label)

	# Unit buttons
	var unit_row := HBoxContainer.new()
	unit_row.add_theme_constant_override("separation", 4)
	vbox.add_child(unit_row)

	var bd := GameData.BLUE_UNITS
	blue_btn_alpha = _make_button("%s $%d" % [bd[GameData.UnitType.ALPHA]["name"], bd[GameData.UnitType.ALPHA]["cost"]], 120)
	blue_btn_alpha.pressed.connect(func(): blue_purchase_requested.emit(GameData.UnitType.ALPHA))
	unit_row.add_child(blue_btn_alpha)

	blue_btn_bravo = _make_button("%s $%d" % [bd[GameData.UnitType.BRAVO]["name"], bd[GameData.UnitType.BRAVO]["cost"]], 120)
	blue_btn_bravo.pressed.connect(func(): blue_purchase_requested.emit(GameData.UnitType.BRAVO))
	unit_row.add_child(blue_btn_bravo)

	blue_btn_charlie = _make_button("%s $%d" % [bd[GameData.UnitType.CHARLIE]["name"], bd[GameData.UnitType.CHARLIE]["cost"]], 120)
	blue_btn_charlie.pressed.connect(func(): blue_purchase_requested.emit(GameData.UnitType.CHARLIE))
	unit_row.add_child(blue_btn_charlie)

	blue_btn_factory = _make_button("Factory $10", 110)
	blue_btn_factory.pressed.connect(func(): blue_factory_requested.emit())
	unit_row.add_child(blue_btn_factory)


func _build_bottom_panel(root: Control) -> void:
	bottom_panel = Control.new()
	bottom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bottom_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.position = Vector2(550, 640)
	bottom_panel.add_child(hbox)

	btn_speed = Button.new()
	btn_speed.text = "x1"
	btn_speed.custom_minimum_size = Vector2(60, 40)
	btn_speed.pressed.connect(_cycle_speed)
	hbox.add_child(btn_speed)


func _build_editor_panel(root: Control) -> void:
	editor_panel = Control.new()
	editor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(editor_panel)

	var panel := PanelContainer.new()
	panel.position = Vector2(5, 560)
	editor_panel.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "EDITOR"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Red gold editor
	var red_row := HBoxContainer.new()
	red_row.add_theme_constant_override("separation", 6)
	vbox.add_child(red_row)

	var red_lbl := Label.new()
	red_lbl.text = "Oro Rojo:"
	red_lbl.add_theme_font_size_override("font_size", 13)
	red_row.add_child(red_lbl)

	red_gold_spinbox = SpinBox.new()
	red_gold_spinbox.min_value = 0
	red_gold_spinbox.max_value = 9999
	red_gold_spinbox.step = 1
	red_gold_spinbox.value = GameData.red_gold
	red_gold_spinbox.custom_minimum_size = Vector2(90, 28)
	red_gold_spinbox.value_changed.connect(_on_red_spinbox_changed)
	red_row.add_child(red_gold_spinbox)

	var btn_r10 := Button.new()
	btn_r10.text = "+10"
	btn_r10.custom_minimum_size = Vector2(45, 28)
	btn_r10.pressed.connect(func(): red_gold_set_requested.emit(int(red_gold_spinbox.value) + 10))
	red_row.add_child(btn_r10)

	var btn_r100 := Button.new()
	btn_r100.text = "+100"
	btn_r100.custom_minimum_size = Vector2(50, 28)
	btn_r100.pressed.connect(func(): red_gold_set_requested.emit(int(red_gold_spinbox.value) + 100))
	red_row.add_child(btn_r100)

	# Blue gold editor
	var blue_row := HBoxContainer.new()
	blue_row.add_theme_constant_override("separation", 6)
	vbox.add_child(blue_row)

	var blue_lbl := Label.new()
	blue_lbl.text = "Oro Azul:"
	blue_lbl.add_theme_font_size_override("font_size", 13)
	blue_row.add_child(blue_lbl)

	blue_gold_spinbox = SpinBox.new()
	blue_gold_spinbox.min_value = 0
	blue_gold_spinbox.max_value = 9999
	blue_gold_spinbox.step = 1
	blue_gold_spinbox.value = GameData.blue_gold
	blue_gold_spinbox.custom_minimum_size = Vector2(90, 28)
	blue_gold_spinbox.value_changed.connect(_on_blue_spinbox_changed)
	blue_row.add_child(blue_gold_spinbox)

	var btn_b10 := Button.new()
	btn_b10.text = "+10"
	btn_b10.custom_minimum_size = Vector2(45, 28)
	btn_b10.pressed.connect(func(): blue_gold_set_requested.emit(int(blue_gold_spinbox.value) + 10))
	blue_row.add_child(btn_b10)

	var btn_b100 := Button.new()
	btn_b100.text = "+100"
	btn_b100.custom_minimum_size = Vector2(50, 28)
	btn_b100.pressed.connect(func(): blue_gold_set_requested.emit(int(blue_gold_spinbox.value) + 100))
	blue_row.add_child(btn_b100)


func _on_red_spinbox_changed(value: float) -> void:
	if _updating_spinbox:
		return
	red_gold_set_requested.emit(int(value))


func _on_blue_spinbox_changed(value: float) -> void:
	if _updating_spinbox:
		return
	blue_gold_set_requested.emit(int(value))


func _build_placement_hint(root: Control) -> void:
	placement_label = Label.new()
	placement_label.text = "Click en la zona CENTRO para colocar | Click derecho o ESC para cancelar"
	placement_label.add_theme_font_size_override("font_size", 13)
	placement_label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	placement_label.position = Vector2(380, 630)
	placement_label.visible = false
	root.add_child(placement_label)


func _build_game_over_panel(root: Control) -> void:
	game_over_panel = Control.new()
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.visible = false
	root.add_child(game_over_panel)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	game_over_panel.add_child(vbox)

	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Base azul destruida - Rojo gana!"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var btn := Button.new()
	btn.text = "Reiniciar"
	btn.custom_minimum_size = Vector2(200, 50)
	btn.pressed.connect(func(): restart_requested.emit())
	vbox.add_child(btn)


func _build_win_panel(root: Control) -> void:
	win_panel = Control.new()
	win_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_panel.visible = false
	root.add_child(win_panel)

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_panel.add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	win_panel.add_child(vbox)

	var title := Label.new()
	title.text = "VICTORIA!"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.3, 1, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Todas las bases rojas destruidas - Azul gana!"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var btn := Button.new()
	btn.text = "Reiniciar"
	btn.custom_minimum_size = Vector2(200, 50)
	btn.pressed.connect(func(): restart_requested.emit())
	vbox.add_child(btn)


func _build_rps_legend(_root: Control) -> void:
	pass


func _make_button(text: String, min_w: float = 120) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(min_w, 30)
	return btn


func _on_red_gold_changed(_amount: int) -> void:
	_refresh_labels()


func _on_blue_gold_changed(_amount: int) -> void:
	_refresh_labels()


func _cycle_speed() -> void:
	const SPEEDS := [1.0, 2.0, 4.0]
	const LABELS := ["x1", "x2", "x4"]
	speed_index = (speed_index + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[speed_index]
	btn_speed.text = LABELS[speed_index]


func _on_phase_changed(phase: GameData.GamePhase) -> void:
	var playing := (phase == GameData.GamePhase.PLAYING)
	red_panel.visible = playing
	blue_panel.visible = playing
	bottom_panel.visible = playing
	editor_panel.visible = playing
	game_over_panel.visible = (phase == GameData.GamePhase.GAME_OVER)
	win_panel.visible = (phase == GameData.GamePhase.WIN)
	placement_label.visible = false
	_refresh_labels()


func _refresh_labels() -> void:
	if red_gold_label:
		red_gold_label.text = "Oro: %d" % GameData.red_gold
	if red_income_label:
		red_income_label.text = "(+%d/s)" % GameData.red_income()
	if blue_gold_label:
		blue_gold_label.text = "Oro: %d" % GameData.blue_gold
	if blue_income_label:
		blue_income_label.text = "(+%d/s)" % GameData.blue_income()
	if blue_factory_label:
		blue_factory_label.text = "Fab: %d" % GameData.blue_factories
	if red_gold_spinbox:
		_updating_spinbox = true
		red_gold_spinbox.value = GameData.red_gold
		_updating_spinbox = false
	if blue_gold_spinbox:
		_updating_spinbox = true
		blue_gold_spinbox.value = GameData.blue_gold
		_updating_spinbox = false
	_update_buttons()


func _update_buttons() -> void:
	if not red_btn_alpha:
		return
	var playing := GameData.game_phase == GameData.GamePhase.PLAYING
	red_btn_alpha.disabled = not (playing and GameData.red_gold >= GameData.get_unit_cost(GameData.Team.RED, GameData.UnitType.ALPHA))
	red_btn_bravo.disabled = not (playing and GameData.red_gold >= GameData.get_unit_cost(GameData.Team.RED, GameData.UnitType.BRAVO))
	red_btn_charlie.disabled = not (playing and GameData.red_gold >= GameData.get_unit_cost(GameData.Team.RED, GameData.UnitType.CHARLIE))

	blue_btn_alpha.disabled = not (playing and GameData.blue_gold >= GameData.get_unit_cost(GameData.Team.BLUE, GameData.UnitType.ALPHA))
	blue_btn_bravo.disabled = not (playing and GameData.blue_gold >= GameData.get_unit_cost(GameData.Team.BLUE, GameData.UnitType.BRAVO))
	blue_btn_charlie.disabled = not (playing and GameData.blue_gold >= GameData.get_unit_cost(GameData.Team.BLUE, GameData.UnitType.CHARLIE))
	blue_btn_factory.disabled = not (playing and GameData.blue_gold >= GameData.FACTORY_COST)


func show_placement_hint(show: bool, team: int = GameData.Team.RED) -> void:
	placement_label.visible = show
	if show:
		if team == GameData.Team.RED:
			placement_label.text = "Click en una zona ROJA (N/S/E/O) para colocar | Click derecho o ESC para cancelar"
		else:
			placement_label.text = "Click en la zona CENTRO (azul) para colocar | Click derecho o ESC para cancelar"


# --- Debug panel ---

func _build_debug_panel(root: Control) -> void:
	debug_panel = PanelContainer.new()
	debug_panel.position = Vector2(900, 120)
	debug_panel.visible = false
	root.add_child(debug_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	debug_panel.add_child(vbox)

	var title := Label.new()
	title.text = "DEBUG STATS (F1) [drag to move]"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_debug_title_input)
	vbox.add_child(title)

	# Team selector
	var team_row := HBoxContainer.new()
	team_row.add_theme_constant_override("separation", 4)
	vbox.add_child(team_row)

	var team_lbl := Label.new()
	team_lbl.text = "Team:"
	team_lbl.add_theme_font_size_override("font_size", 12)
	team_row.add_child(team_lbl)

	debug_team_btn = Button.new()
	debug_team_btn.text = "RED"
	debug_team_btn.custom_minimum_size = Vector2(80, 26)
	debug_team_btn.pressed.connect(_debug_cycle_team)
	team_row.add_child(debug_team_btn)

	# Unit selector
	var unit_row := HBoxContainer.new()
	unit_row.add_theme_constant_override("separation", 4)
	vbox.add_child(unit_row)

	var unit_lbl := Label.new()
	unit_lbl.text = "Unit:"
	unit_lbl.add_theme_font_size_override("font_size", 12)
	unit_row.add_child(unit_lbl)

	debug_unit_btn = Button.new()
	debug_unit_btn.text = "ALPHA"
	debug_unit_btn.custom_minimum_size = Vector2(150, 26)
	debug_unit_btn.pressed.connect(_debug_cycle_unit)
	unit_row.add_child(debug_unit_btn)

	# Stat spinboxes
	var stats := ["hp", "damage", "bonus_vs_light", "bonus_vs_heavy", "attack_range", "move_speed", "fire_rate", "flame_arc"]
	var labels := {
		"hp": "HP", "damage": "Damage", "bonus_vs_light": "Bonus vs Light",
		"bonus_vs_heavy": "Bonus vs Heavy", "attack_range": "Range (tiles)",
		"move_speed": "Speed", "fire_rate": "Fire Rate (s)", "flame_arc": "Flame Arc (deg)"
	}
	var steps := {
		"hp": 5.0, "damage": 1.0, "bonus_vs_light": 1.0, "bonus_vs_heavy": 1.0,
		"attack_range": 0.1, "move_speed": 5.0, "fire_rate": 0.1, "flame_arc": 5.0
	}
	var ranges := {
		"hp": [1.0, 999.0], "damage": [0.0, 200.0], "bonus_vs_light": [0.0, 100.0],
		"bonus_vs_heavy": [0.0, 100.0], "attack_range": [0.1, 10.0],
		"move_speed": [0.0, 500.0], "fire_rate": [0.05, 10.0], "flame_arc": [10.0, 360.0]
	}

	for stat_key in stats:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = labels[stat_key] + ":"
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.custom_minimum_size = Vector2(110, 0)
		row.add_child(lbl)

		var spinbox := SpinBox.new()
		spinbox.min_value = ranges[stat_key][0]
		spinbox.max_value = ranges[stat_key][1]
		spinbox.step = steps[stat_key]
		spinbox.custom_minimum_size = Vector2(90, 26)
		row.add_child(spinbox)

		debug_spinboxes[stat_key] = spinbox

	var apply_btn := Button.new()
	apply_btn.text = "Apply"
	apply_btn.custom_minimum_size = Vector2(120, 30)
	apply_btn.pressed.connect(_debug_apply_stats)
	vbox.add_child(apply_btn)

	_debug_refresh_spinboxes()


func _on_debug_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_debug_dragging = true
			_debug_drag_offset = debug_panel.position - event.global_position
		else:
			_debug_dragging = false
	elif event is InputEventMouseMotion and _debug_dragging:
		debug_panel.position = event.global_position + _debug_drag_offset


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		debug_panel.visible = not debug_panel.visible
		if debug_panel.visible:
			_debug_refresh_spinboxes()
		get_viewport().set_input_as_handled()


func _debug_cycle_team() -> void:
	if debug_selected_team == GameData.Team.RED:
		debug_selected_team = GameData.Team.BLUE
		debug_team_btn.text = "BLUE"
	else:
		debug_selected_team = GameData.Team.RED
		debug_team_btn.text = "RED"
	_debug_refresh_spinboxes()


func _debug_cycle_unit() -> void:
	debug_selected_unit = (debug_selected_unit + 1) % 3
	_debug_refresh_spinboxes()


func _debug_refresh_spinboxes() -> void:
	_updating_debug = true
	var data: Dictionary = GameData.get_unit_data(
		debug_selected_team as GameData.Team,
		debug_selected_unit as GameData.UnitType
	)
	for stat_key in debug_spinboxes:
		var spinbox: SpinBox = debug_spinboxes[stat_key]
		if data.has(stat_key):
			spinbox.value = data[stat_key]
			spinbox.editable = true
			spinbox.get_parent().visible = true
		else:
			spinbox.value = 0
			spinbox.editable = false
			spinbox.get_parent().visible = false

	var type_names := ["ALPHA", "BRAVO", "CHARLIE"]
	var unit_name: String = data.get("name", "???")
	debug_unit_btn.text = "%s (%s)" % [type_names[debug_selected_unit], unit_name]
	_updating_debug = false


func _debug_apply_stats() -> void:
	var data: Dictionary = GameData.get_unit_data(
		debug_selected_team as GameData.Team,
		debug_selected_unit as GameData.UnitType
	)
	for stat_key in debug_spinboxes:
		if data.has(stat_key):
			var spinbox: SpinBox = debug_spinboxes[stat_key]
			data[stat_key] = spinbox.value
	GameData.notify_stats_changed(
		debug_selected_team as GameData.Team,
		debug_selected_unit as GameData.UnitType
	)
