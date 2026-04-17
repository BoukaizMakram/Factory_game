extends AnimatedSprite2D

var _mineable: Node
var _timer: float = 0.0
var _drilling: bool = false


func _ready() -> void:
	call_deferred("_find_mineable")


func _process(delta: float) -> void:
	if _mineable == null:
		return

	var marker := _get_active_marker()
	if marker == null:
		return

	var ore_scene: PackedScene = _mineable.get("ore_scene")
	if ore_scene == null:
		return

	var placeable = get_parent()
	if placeable is Placeable and not placeable.powered:
		return

	var mining_time: float = _mineable.get("mining_time")
	if mining_time <= 0.0:
		mining_time = 2.0

	if _is_output_blocked(marker):
		_timer = 0.0
		_set_drilling(false)
		return

	_set_drilling(true)
	_timer += delta
	if _timer >= mining_time:
		_timer -= mining_time
		_spawn_ore(ore_scene, marker)


func _find_mineable() -> void:
	var placeable = get_parent()
	if placeable == null:
		return
	var space: PhysicsDirectSpaceState2D = placeable.get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = placeable.global_position
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results: Array[Dictionary] = space.intersect_point(params, 32)
	for result in results:
		var collider: Node = result["collider"]
		if collider is Area2D:
			for c in collider.get_children():
				if c.get("ore_name") != null:
					_mineable = c
					print("Mineable found: ", c.get("ore_name"))
					return
	print("No mineable found at ", placeable.global_position)


func _get_active_marker() -> Marker2D:
	var placeable = get_parent()
	if placeable == null:
		return null
	# Find the visible AnimatedSprite2D child, then get its Marker2D
	for c in placeable.get_children():
		if c is AnimatedSprite2D and c.visible:
			for m in c.get_children():
				if m is Marker2D:
					return m
	return null


func _set_drilling(active: bool) -> void:
	if _drilling == active:
		return
	_drilling = active
	var placeable = get_parent()
	if placeable == null:
		return
	for c in placeable.get_children():
		if c is AnimatedSprite2D and c.visible:
			if active:
				c.play()
			else:
				c.stop()


func _is_output_blocked(marker: Marker2D) -> bool:
	var cell := _marker_cell(marker)
	if Belt.has_belt_at(cell):
		return not Belt.has_room_at_entry(cell)
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(Placeable.CELL_SIZE * 0.8, Placeable.CELL_SIZE * 0.8)
	params.shape = rect
	params.transform = Transform2D(0, marker.global_position)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var results := space.intersect_shape(params, 32)
	for result in results:
		var collider: Node = result["collider"]
		if _is_placeable_child(collider):
			continue
		if _is_mineable_area(collider):
			continue
		return true
	return false


func _marker_cell(marker: Marker2D) -> Vector2i:
	return Vector2i(floor(marker.global_position.x / float(Placeable.CELL_SIZE)), floor(marker.global_position.y / float(Placeable.CELL_SIZE)))


func _is_mineable_area(node: Node) -> bool:
	if node is Area2D:
		for c in node.get_children():
			if c.get("ore_name") != null or c.name == "Mineable":
				return true
	return false


func _is_placeable_child(node: Node) -> bool:
	var current: Node = node
	while current != null:
		if current is Placeable:
			return true
		current = current.get_parent()
	return false


func _spawn_ore(ore_scene: PackedScene, marker: Marker2D) -> void:
	var cell := _marker_cell(marker)
	if Belt.has_belt_at(cell):
		var ore_name: String = _mineable.get("ore_name") if _mineable != null else ""
		Belt.push_item(cell, ore_name)
		return
	var ore: Node2D = ore_scene.instantiate()
	ore.global_position = marker.global_position
	get_tree().current_scene.add_child(ore)
