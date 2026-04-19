class_name SFX
extends Object

const DEFAULT_MAX_DISTANCE: float = 4000.0
const DEFAULT_ATTENUATION: float = 1.4
const DEFAULT_PITCH_VARIANCE: float = 0.08
const DEFAULT_INNER_DISTANCE: float = 128.0

static var _duck_sources: Dictionary = {}


static func duck_master(source_id: StringName, db_offset: float) -> void:
	_duck_sources[source_id] = db_offset
	_apply_master_duck()


static func unduck_master(source_id: StringName) -> void:
	if not _duck_sources.has(source_id):
		return
	_duck_sources.erase(source_id)
	_apply_master_duck()


static func refresh_master_volume() -> void:
	_apply_master_duck()


static func _apply_master_duck() -> void:
	var duck_offset: float = 0.0
	for db in _duck_sources.values():
		duck_offset = minf(duck_offset, float(db))
	var bus_idx: int = AudioServer.get_bus_index(&"Master")
	if bus_idx < 0:
		return
	var base_db: float = 0.0
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop is SceneTree:
		var settings_node: Node = (main_loop as SceneTree).root.get_node_or_null("GameSettings")
		if settings_node != null:
			var master_linear: float = float(settings_node.get("master_volume"))
			base_db = -80.0 if master_linear <= 0.001 else linear_to_db(master_linear)
	AudioServer.set_bus_volume_db(bus_idx, base_db + duck_offset)


static func configure_2d(player: AudioStreamPlayer2D, max_distance: float = DEFAULT_MAX_DISTANCE, attenuation: float = DEFAULT_ATTENUATION) -> void:
	if player == null:
		return
	player.max_distance = max_distance if max_distance > 0.0 else DEFAULT_MAX_DISTANCE
	player.attenuation = attenuation if attenuation > 0.0 else DEFAULT_ATTENUATION
	player.panning_strength = 1.0


static func configure_camera_radius_2d(player: AudioStreamPlayer2D) -> void:
	if player == null:
		return
	player.max_distance = 1000000.0
	player.attenuation = 1.0
	player.panning_strength = 1.0


static func camera_distance_volume_db(source_position: Vector2, full_volume_db: float, silent_db: float, max_distance: float = DEFAULT_MAX_DISTANCE, inner_distance: float = DEFAULT_INNER_DISTANCE, curve: float = 1.0) -> float:
	var camera: Camera2D = _current_camera_2d()
	if camera == null:
		return full_volume_db
	var radius: float = maxf(max_distance, 1.0)
	var inner: float = clampf(inner_distance, 0.0, radius - 0.001)
	var distance: float = camera.global_position.distance_to(source_position)
	if distance <= inner:
		return full_volume_db
	if distance >= radius:
		return silent_db
	var t: float = (distance - inner) / maxf(radius - inner, 0.001)
	t = pow(clampf(t, 0.0, 1.0), maxf(curve, 0.01))
	return lerpf(full_volume_db, silent_db, t)


static func _current_camera_2d() -> Camera2D:
	var main_loop: MainLoop = Engine.get_main_loop()
	if not main_loop is SceneTree:
		return null
	var tree: SceneTree = main_loop as SceneTree
	var viewport: Viewport = tree.root
	if viewport == null:
		return null
	return viewport.get_camera_2d()


static func random_pitch(base: float = 1.0, variance: float = DEFAULT_PITCH_VARIANCE) -> float:
	var v: float = maxf(variance, 0.0)
	return maxf(0.05, base + randf_range(-v, v))


static func apply_random_pitch(player: Node, base: float = 1.0, variance: float = DEFAULT_PITCH_VARIANCE) -> void:
	if player == null:
		return
	var pitch: float = random_pitch(base, variance)
	if player is AudioStreamPlayer2D:
		(player as AudioStreamPlayer2D).pitch_scale = pitch
	elif player is AudioStreamPlayer:
		(player as AudioStreamPlayer).pitch_scale = pitch
	elif player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).pitch_scale = pitch


static func play_oneshot_2d(parent: Node, stream: AudioStream, global_pos: Vector2, volume_db: float = 0.0, base_pitch: float = 1.0, pitch_variance: float = DEFAULT_PITCH_VARIANCE, max_distance: float = DEFAULT_MAX_DISTANCE, attenuation: float = DEFAULT_ATTENUATION) -> AudioStreamPlayer2D:
	if parent == null or stream == null:
		return null
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	configure_2d(player, max_distance, attenuation)
	apply_random_pitch(player, base_pitch, pitch_variance)
	parent.add_child(player)
	player.global_position = global_pos
	player.play()
	player.finished.connect(player.queue_free)
	return player


static func play_oneshot(parent: Node, stream: AudioStream, volume_db: float = 0.0, base_pitch: float = 1.0, pitch_variance: float = DEFAULT_PITCH_VARIANCE) -> AudioStreamPlayer:
	if parent == null or stream == null:
		return null
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	apply_random_pitch(player, base_pitch, pitch_variance)
	parent.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
	return player
