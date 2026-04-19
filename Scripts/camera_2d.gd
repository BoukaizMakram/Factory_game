extends Camera2D

@export var target: Node2D
@export var move_speed: float = 600.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.2
@export var max_zoom: float = 4.0
@export var move_smoothing: float = 12.0
@export var zoom_smoothing: float = 10.0
@export var follow_smoothing: float = 8.0

var _velocity: Vector2 = Vector2.ZERO
var _target_zoom: float = 1.0


func _ready() -> void:
	_target_zoom = zoom.x


func _process(delta: float) -> void:
	if target != null:
		var t: float = clamp(follow_smoothing * delta, 0.0, 1.0)
		global_position = global_position.lerp(target.global_position, t)
	else:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(GameSettings.get_key("move_up")):
			dir.y -= 1
		if Input.is_key_pressed(GameSettings.get_key("move_down")):
			dir.y += 1
		if Input.is_key_pressed(GameSettings.get_key("move_left")):
			dir.x -= 1
		if Input.is_key_pressed(GameSettings.get_key("move_right")):
			dir.x += 1

		var target_velocity := Vector2.ZERO
		if dir != Vector2.ZERO:
			target_velocity = dir.normalized() * move_speed / zoom.x

		_velocity = _velocity.lerp(target_velocity, clamp(move_smoothing * delta, 0.0, 1.0))
		position += _velocity * delta

	var new_zoom: float = lerp(zoom.x, _target_zoom, clamp(zoom_smoothing * delta, 0.0, 1.0))
	zoom = Vector2(new_zoom, new_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_zoom = clamp(_target_zoom * (1.0 + zoom_speed), min_zoom, max_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_zoom = clamp(_target_zoom * (1.0 - zoom_speed), min_zoom, max_zoom)
