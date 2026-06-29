extends Node2D

var target: Node2D
var damage: float
var attacker_type: int
var speed: float = 400.0
var color: Color = Color.YELLOW


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		queue_free()
		return

	var direction := (target.global_position - global_position).normalized()
	global_position += direction * speed * delta

	if global_position.distance_to(target.global_position) < 10.0:
		if target.has_method("take_damage"):
			target.take_damage(damage, attacker_type)
		queue_free()


func _draw() -> void:
	draw_circle(Vector2.ZERO, 1.5, color)
