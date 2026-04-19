extends Node2D

@export var processing_time: float = 1.0
@export var electricity_particles_name: StringName = &"animation"
@export var action_particles_name: StringName = &"action"
@export_group("Sound")
@export var loop_sound: AudioStream = preload("res://SFX/Machines/crusher loop.mp3")
@export var action_sound: AudioStream = preload("res://SFX/Machines/action/crush.wav")
@export var sound_volume_db: float = -6.0
@export var action_volume_db: float = -2.0
@export var sound_inner_distance: float = 128.0
@export var sound_max_distance: float = 4000.0
@export var sound_attenuation: float = 1.4
@export var sound_distance_curve: float = 1.0
@export var sound_fade_in_seconds: float = 0.35
@export var sound_fade_out_seconds: float = 0.5
@export var sound_silent_db: float = -60.0
@export var sound_pitch_base: float = 1.0
@export var sound_pitch_variance: float = 0.08
@export var action_pitch_variance: float = 0.12

var _timer: float = 0.0
var _loop_player: AudioStreamPlayer2D
var _action_player: AudioStreamPlayer2D
var _loop_should_play: bool = false


func _process(delta: float) -> void:
	var placeable: Placeable = _get_placeable()
	if placeable == null or placeable.ghost_mode:
		_set_electricity_particles(false)
		_set_loop_sound(null, false)
		_update_loop_sound_fade(delta)
		return
	var powered: bool = placeable.powered
	var animating: bool = powered and _has_playing_sprite(placeable)
	_set_electricity_particles(animating)
	_set_loop_sound(placeable, animating)
	_update_loop_sound_fade(delta)
	if not powered:
		_timer = 0.0
		return

	var item: Dictionary = _find_raw_item(placeable)
	if item.is_empty():
		_timer = 0.0
		return

	_timer += delta
	if _timer < maxf(processing_time, 0.01):
		return
	_timer = 0.0
	Belt.crush_item(item)


func on_transport_item_received(_item: Dictionary) -> void:
	_burst_action_particles()
	_play_action_sound()


func _get_placeable() -> Placeable:
	var parent: Node = get_parent()
	if parent is Placeable:
		return parent as Placeable
	return null


func _find_raw_item(placeable: Placeable) -> Dictionary:
	var items: Array = placeable.get_meta(Belt.META_KEY, [])
	for item_data in items:
		if item_data is Dictionary:
			var item: Dictionary = item_data as Dictionary
			if Belt.is_raw_item(item):
				return item
	return {}


func _set_electricity_particles(enabled: bool) -> void:
	var particles: CPUParticles2D = _find_particles(electricity_particles_name)
	if particles != null:
		particles.emitting = enabled


func _burst_action_particles() -> void:
	var particles: CPUParticles2D = _find_particles(action_particles_name)
	if particles != null:
		particles.restart()
		particles.emitting = true


func _find_particles(node_name: StringName) -> CPUParticles2D:
	var placeable: Placeable = _get_placeable()
	if placeable == null:
		return null
	var found: Node = placeable.find_child(String(node_name), true, false)
	if found is CPUParticles2D:
		return found as CPUParticles2D
	return null


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


func _play_action_sound() -> void:
	var placeable: Placeable = _get_placeable()
	if placeable == null or placeable.ghost_mode or action_sound == null:
		return
	var player: AudioStreamPlayer2D = _get_action_player(placeable)
	if player == null:
		return
	player.stream = action_sound
	player.volume_db = SFX.camera_distance_volume_db(player.global_position, action_volume_db, sound_silent_db, sound_max_distance, sound_inner_distance, sound_distance_curve)
	SFX.configure_camera_radius_2d(player)
	SFX.apply_random_pitch(player, sound_pitch_base, action_pitch_variance)
	player.play()


func _get_loop_player(placeable: Placeable) -> AudioStreamPlayer2D:
	if _loop_player != null and is_instance_valid(_loop_player):
		return _loop_player
	var existing: Node = placeable.get_node_or_null("CrusherLoopSound")
	if existing is AudioStreamPlayer2D:
		_loop_player = existing as AudioStreamPlayer2D
		return _loop_player
	_loop_player = AudioStreamPlayer2D.new()
	_loop_player.name = "CrusherLoopSound"
	_loop_player.autoplay = false
	placeable.add_child(_loop_player)
	return _loop_player


func _get_action_player(placeable: Placeable) -> AudioStreamPlayer2D:
	if _action_player != null and is_instance_valid(_action_player):
		return _action_player
	var existing: Node = placeable.get_node_or_null("CrusherActionSound")
	if existing is AudioStreamPlayer2D:
		_action_player = existing as AudioStreamPlayer2D
		return _action_player
	_action_player = AudioStreamPlayer2D.new()
	_action_player.name = "CrusherActionSound"
	_action_player.autoplay = false
	placeable.add_child(_action_player)
	return _action_player


func _make_loop_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _has_playing_sprite(placeable: Placeable) -> bool:
	for child in placeable.get_children():
		if child is AnimatedSprite2D and child.visible and (child as AnimatedSprite2D).is_playing():
			return true
	return false
