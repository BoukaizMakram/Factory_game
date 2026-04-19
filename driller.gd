extends Node2D

@export var mining_time_multiplier: float = 1.0
@export var speed_min_fps: float = 5.0
@export var speed_max_fps: float = 16.0
@export var particle_start_frame: int = 30
@export var particle_end_frame: int = 46
@export_group("Sound")
@export var loop_sound: AudioStream = preload("res://SFX/Machines/machine.mp3")
@export var sound_volume_db: float = -6.0
@export var sound_inner_distance: float = 128.0
@export var sound_max_distance: float = 4000.0
@export var sound_attenuation: float = 1.4
@export var sound_distance_curve: float = 1.0
@export var sound_fade_in_seconds: float = 0.35
@export var sound_fade_out_seconds: float = 0.5
@export var sound_silent_db: float = -60.0
@export var sound_pitch_base: float = 1.0
@export var sound_pitch_variance: float = 0.08

var _mineable: Mineable
var _timer: float = 0.0
var _drilling: bool = false
var _drilling_sprite: AnimatedSprite2D
var _stopping_sprite: AnimatedSprite2D
var _drill_particles: Array[CPUParticles2D] = []
var _ore_ready: bool = false
var _loop_player: AudioStreamPlayer2D
var _loop_should_play: bool = false


func _ready() -> void:
	call_deferred("_cache_drill_particles")
	call_deferred("_find_mineable")


func _process(delta: float) -> void:
	if _mineable == null:
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return

	var marker: Marker2D = _get_active_marker()
	if marker == null:
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return

	var ore_scene: PackedScene = _mineable.ore_scene
	if ore_scene == null:
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return

	var placeable: Placeable = _get_placeable()
	if placeable == null:
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return
	if not placeable.powered:
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return

	var mining_time: float = _mineable.mining_time * maxf(mining_time_multiplier, 0.0)
	if mining_time <= 0.0:
		mining_time = 2.0

	if _is_output_blocked(marker):
		_set_drilling(false)
		_update_loop_sound_fade(delta)
		return

	if not _ore_ready:
		_set_drilling(true)
		_timer += delta
		if _timer < mining_time:
			_update_loop_sound_fade(delta)
			return
		_timer = 0.0
		_ore_ready = true

	if not _ore_ready:
		_update_drill_particles()
		_update_loop_sound_fade(delta)
		return
	if _spawn_ore(ore_scene, marker):
		_ore_ready = false

	_update_drill_particles()
	_update_loop_sound_fade(delta)


func _find_mineable() -> void:
	var placeable: Placeable = _get_placeable()
	if placeable == null:
		return
	var space: PhysicsDirectSpaceState2D = placeable.get_world_2d().direct_space_state
	var params: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	params.position = placeable.global_position
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results: Array[Dictionary] = space.intersect_point(params, 32)
	for result in results:
		var collider: Node = result["collider"]
		if collider is Area2D:
			_mineable = _find_mineable_in_area(collider as Area2D, placeable.global_position)
			if _mineable != null:
				DebugConsole.log("Mineable found: " + String(_mineable.ore_name))
				return
	DebugConsole.log("No mineable found at " + str(placeable.global_position))


func _get_active_marker() -> Marker2D:
	var sprite: AnimatedSprite2D = _get_active_sprite()
	if sprite == null:
		return null
	# Find the visible AnimatedSprite2D child, then get its Marker2D
	for m in sprite.get_children():
		if m is Marker2D:
			return m
	return null


func _get_active_sprite() -> AnimatedSprite2D:
	var placeable: Placeable = _get_placeable()
	if placeable == null:
		return null
	for c in placeable.get_children():
		if c is AnimatedSprite2D and c.visible:
			return c as AnimatedSprite2D
	return null


func _set_drilling(active: bool) -> void:
	var placeable: Placeable = _get_placeable()
	if placeable == null:
		_stop_loop_sound()
		return
	var active_sprite: AnimatedSprite2D = _get_active_sprite()
	_set_loop_sound(placeable, active)
	if _drilling == active and _drilling_sprite == active_sprite:
		if active and active_sprite != null:
			_stopping_sprite = null
			_apply_drill_speed(active_sprite, placeable)
		elif not active:
			_pause_sprite(_stopping_sprite)
		_update_drill_particles()
		return
	_drilling = active
	_drilling_sprite = active_sprite
	for c in placeable.get_children():
		if c is AnimatedSprite2D:
			if active:
				if c == active_sprite:
					_stopping_sprite = null
					_apply_drill_speed(c as AnimatedSprite2D, placeable)
					_resume_sprite(c as AnimatedSprite2D)
				else:
					_pause_sprite(c as AnimatedSprite2D)
			else:
				if c == active_sprite:
					_stopping_sprite = active_sprite
					_apply_drill_speed(c as AnimatedSprite2D, placeable)
					_pause_sprite(c as AnimatedSprite2D)
				else:
					_pause_sprite(c as AnimatedSprite2D)
	_update_drill_particles()


func _finish_stop_at_first_frame(sprite: AnimatedSprite2D) -> void:
	if sprite == null or _stopping_sprite != sprite:
		return
	_pause_sprite(sprite)
	_stopping_sprite = null


func _apply_drill_speed(sprite: AnimatedSprite2D, placeable: Placeable) -> void:
	if sprite.sprite_frames == null:
		return
	var ratio: float = clampf(float(placeable.get("_power_ratio")), 0.0, 1.0)
	var min_fps: float = maxf(speed_min_fps, 0.0)
	var max_fps: float = maxf(speed_max_fps, min_fps)
	var target_fps: float = lerp(min_fps, max_fps, ratio)
	var base_fps: float = sprite.sprite_frames.get_animation_speed(sprite.animation)
	if base_fps <= 0.0:
		base_fps = maxf(max_fps, 0.001)
	sprite.speed_scale = target_fps / base_fps


func _resume_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if not sprite.is_playing():
		sprite.play()


func _pause_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if sprite.is_playing():
		sprite.pause()


func _set_loop_sound(placeable: Placeable, playing: bool) -> void:
	if placeable == null or placeable.ghost_mode or loop_sound == null:
		_stop_loop_sound()
		return
	var player: AudioStreamPlayer2D = _get_loop_player(placeable)
	if player == null:
		return
	_make_loop_stream(loop_sound)
	if player.stream != loop_sound:
		player.stream = loop_sound
		player.volume_db = sound_silent_db
	SFX.configure_camera_radius_2d(player)
	if playing:
		_loop_should_play = true
		if not player.playing:
			player.volume_db = sound_silent_db
			SFX.apply_random_pitch(player, sound_pitch_base, sound_pitch_variance)
			player.play()
	else:
		_loop_should_play = false


func _stop_loop_sound() -> void:
	_loop_should_play = false


func _update_loop_sound_fade(delta: float) -> void:
	if _loop_player == null or not is_instance_valid(_loop_player):
		return
	var active_volume: float = SFX.camera_distance_volume_db(_loop_player.global_position, sound_volume_db, sound_silent_db, sound_max_distance, sound_inner_distance, sound_distance_curve)
	var target_volume: float = active_volume if _loop_should_play else sound_silent_db
	var fade_seconds: float = sound_fade_in_seconds if _loop_should_play else sound_fade_out_seconds
	if fade_seconds <= 0.0:
		_loop_player.volume_db = target_volume
	else:
		var db_span: float = absf(maxf(sound_volume_db, active_volume) - sound_silent_db)
		var step: float = maxf(db_span, 0.001) * delta / fade_seconds
		_loop_player.volume_db = move_toward(_loop_player.volume_db, target_volume, step)
	if not _loop_should_play and _loop_player.playing and _loop_player.volume_db <= sound_silent_db + 0.1:
		_loop_player.stop()


func _get_loop_player(placeable: Placeable) -> AudioStreamPlayer2D:
	if _loop_player != null and is_instance_valid(_loop_player):
		return _loop_player
	var existing: Node = placeable.get_node_or_null("DrillLoopSound")
	if existing is AudioStreamPlayer2D:
		_loop_player = existing as AudioStreamPlayer2D
		return _loop_player
	_loop_player = AudioStreamPlayer2D.new()
	_loop_player.name = "DrillLoopSound"
	_loop_player.autoplay = false
	placeable.add_child(_loop_player)
	return _loop_player


func _make_loop_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _cache_drill_particles() -> void:
	_drill_particles.clear()
	var placeable: Placeable = _get_placeable()
	if placeable == null:
		return
	_collect_drill_particles(placeable)
	_update_drill_particles()


func _collect_drill_particles(node: Node) -> void:
	for child in node.get_children():
		if child is CPUParticles2D:
			_drill_particles.append(child as CPUParticles2D)
		_collect_drill_particles(child)


func _update_drill_particles() -> void:
	var sprite: AnimatedSprite2D = _drilling_sprite
	var should_emit: bool = _drilling and sprite != null and sprite.frame >= particle_start_frame and sprite.frame <= particle_end_frame
	for particles in _drill_particles:
		if is_instance_valid(particles):
			particles.emitting = should_emit


func _get_placeable() -> Placeable:
	var parent: Node = get_parent()
	if parent is Placeable:
		return parent as Placeable
	if parent is AnimatedSprite2D and parent.get_parent() is Placeable:
		return parent.get_parent() as Placeable
	return null


func _is_output_blocked(marker: Marker2D) -> bool:
	var cell: Vector2i = _marker_cell(marker)
	if Belt.has_belt_at(cell):
		return not Belt.has_room_at_entry(cell, marker.global_position)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	rect.size = Vector2(Placeable.CELL_SIZE * 0.8, Placeable.CELL_SIZE * 0.8)
	params.shape = rect
	params.transform = Transform2D(0, marker.global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var results: Array[Dictionary] = space.intersect_shape(params, 32)
	for result in results:
		var collider: Node = result["collider"]
		if _is_placeable_child(collider):
			continue
		if _is_mineable_area(collider, marker.global_position):
			continue
		return true
	return false


func _marker_cell(marker: Marker2D) -> Vector2i:
	return Vector2i(floor(marker.global_position.x / float(Placeable.CELL_SIZE)), floor(marker.global_position.y / float(Placeable.CELL_SIZE)))


func _is_mineable_area(node: Node, point: Vector2) -> bool:
	return node is Area2D and _find_mineable_in_area(node as Area2D, point) != null


func _find_mineable_in_area(area: Area2D, point: Vector2) -> Mineable:
	for child in area.get_children():
		if child is Mineable and _mineable_shape_contains_point(child, point):
			return child as Mineable
	return null


func _mineable_shape_contains_point(node: Node, point: Vector2) -> bool:
	if not (node is CollisionShape2D):
		return false
	var collision: CollisionShape2D = node as CollisionShape2D
	if collision.disabled or collision.shape == null:
		return false
	var point_shape: CircleShape2D = CircleShape2D.new()
	point_shape.radius = 0.1
	return collision.shape.collide(collision.global_transform, point_shape, Transform2D(0.0, point))


func _is_placeable_child(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current is Placeable:
			return true
		current = current.get_parent()
	return false


func _spawn_ore(ore_scene: PackedScene, marker: Marker2D) -> bool:
	var cell: Vector2i = _marker_cell(marker)
	var ore_name: String = _mineable.ore_name if _mineable != null else ""
	if Belt.has_belt_at(cell):
		return Belt.push_item(cell, ore_name, marker.global_position)
	var ore: Node2D = ore_scene.instantiate()
	ore.global_position = marker.global_position
	_apply_ore_texture(ore, ore_name)
	get_tree().current_scene.add_child(ore)
	return true


func _apply_ore_texture(ore: Node, _ore_name: String) -> void:
	var texture: Texture2D = Belt.get_ore_texture("dirty")
	if texture == null:
		return
	var sprite: Sprite2D = _find_sprite_2d(ore)
	if sprite != null:
		sprite.texture = texture


func _find_sprite_2d(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite: Sprite2D = _find_sprite_2d(child)
		if sprite != null:
			return sprite
	return null
