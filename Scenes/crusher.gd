extends Node2D

@export var processing_time: float = 1.0
@export var electricity_particles_name: StringName = &"animation"
@export var action_particles_name: StringName = &"action"

var _timer: float = 0.0


func _process(delta: float) -> void:
	var placeable: Placeable = _get_placeable()
	if placeable == null or placeable.ghost_mode:
		_set_electricity_particles(false)
		return
	var powered: bool = placeable.powered
	_set_electricity_particles(powered and _has_playing_sprite(placeable))
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


func _has_playing_sprite(placeable: Placeable) -> bool:
	for child in placeable.get_children():
		if child is AnimatedSprite2D and child.visible and (child as AnimatedSprite2D).is_playing():
			return true
	return false
