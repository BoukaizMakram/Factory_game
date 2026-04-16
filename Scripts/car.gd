extends Sprite2D

@export var move_speed: float = 400.0
@export var acceleration: float = 8.0
@export var rotate_to_direction: bool = true
@export var turn_smoothing: float = 10.0

var _velocity: Vector2 = Vector2.ZERO


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		dir.y += 1
	if Input.is_key_pressed(KEY_A):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		dir.x += 1

	var target_velocity := Vector2.ZERO
	if dir != Vector2.ZERO:
		target_velocity = dir.normalized() * move_speed

	_velocity = _velocity.lerp(target_velocity, clamp(acceleration * delta, 0.0, 1.0))
	position += _velocity * delta

	if rotate_to_direction and _velocity.length() > 1.0:
		var target_angle := _velocity.angle()
		rotation = lerp_angle(rotation, target_angle, clamp(turn_smoothing * delta, 0.0, 1.0))
