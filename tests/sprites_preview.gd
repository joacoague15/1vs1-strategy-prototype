extends Node2D
# Preview visual de los sprites de las 6 unidades: screenshot y quit.
# Correr: godot --path . res://tests/sprites_preview.tscn

const UNIT_SCENE := preload("res://scenes/unit.tscn")
const OUT_PATH := "C:/Users/joaco/AppData/Local/Temp/claude/C--Users-joaco-OneDrive-Documents-nuevo-proyecto-sobre--towe-defense--capaz-/e622f9e3-2773-4247-913e-88f9c0d99964/scratchpad/sprites_preview.png"

var _frames := 0


func _ready() -> void:
	# Congelar la logica de combate: solo queremos ver los sprites
	GameData.game_phase = GameData.GamePhase.GAME_OVER
	var layout := [
		[GameData.Team.RED, GameData.UnitType.ALPHA, Vector2(250, 220)],
		[GameData.Team.RED, GameData.UnitType.BRAVO, Vector2(550, 220)],
		[GameData.Team.RED, GameData.UnitType.CHARLIE, Vector2(850, 220)],
		[GameData.Team.BLUE, GameData.UnitType.ALPHA, Vector2(250, 480)],
		[GameData.Team.BLUE, GameData.UnitType.BRAVO, Vector2(550, 480)],
		[GameData.Team.BLUE, GameData.UnitType.CHARLIE, Vector2(850, 480)],
	]
	for entry in layout:
		var u := UNIT_SCENE.instantiate()
		u.team = entry[0]
		u.unit_type = entry[1]
		u.position = entry[2]
		u.scale = Vector2(6, 6)
		add_child(u)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.08, 0.09, 0.12))
	var font := ThemeDB.fallback_font
	var names := ["Zergling", "Hydralisk", "Roach", "Marine", "Hellbat", "Medic"]
	var xs := [250, 550, 850, 250, 550, 850]
	var ys := [330, 330, 330, 590, 590, 590]
	for i in 6:
		var sz := font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		draw_string(font, Vector2(xs[i] - sz.x / 2.0, ys[i]), names[i],
			HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 20:
		var img := get_viewport().get_texture().get_image()
		img.save_png(OUT_PATH)
		print("preview guardado")
		get_tree().quit()
