extends Node2D

@export var speed: float = 64.0
@export var lane_snap_speed: float = 120.0

var _belt_shape: Shape2D
var _belt_shape_transform: Transform2D
var _belt_half_length: float = 0.0


func _ready() -> void:
	var placeable = get_parent()
	if placeable == null:
		return
	for c in placeable.get_children():
		if c is StaticBody2D:
			for sc in c.get_children():
				if sc is CollisionShape2D and sc.shape != null:
					_belt_shape = sc.shape
					_belt_shape_transform = placeable.global_transform.affine_inverse() * sc.global_transform
					if _belt_shape is RectangleShape2D:
						var rect := _belt_shape as RectangleShape2D
						_belt_half_length = max(rect.size.x, rect.size.y) * 0.5 * placeable.scale.x
					break
			break


func _physics_process(delta: float) -> void:
	var placeable = get_parent()
	if placeable == null or not (placeable is Placeable):
		return
	if (placeable as Placeable).ghost_mode:
		return
	if _belt_shape == null:
		return

	var dir: Vector2 = _get_belt_direction(placeable)
	var center: Vector2 = placeable.global_position

	var space := get_world_2d().direct_space_state
	var items: Array[Node2D] = _get_items_on_belt(space, placeable)

	var has_next_belt: bool = _has_belt_ahead(dir)

	# Sort: furthest along belt first so leading items move before trailing ones
	items.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return (a.global_position - center).dot(dir) > (b.global_position - center).dot(dir)
	)

	var min_spacing: float = Placeable.CELL_SIZE * 0.4
	# Collect positions of ALL items (including ones owned by other belts) for spacing
	var all_positions: Array[Vector2] = []
	for item in items:
		all_positions.append(item.global_position)

	for item in items:
		if not _is_closest_belt(item):
			continue

		var offset_along: float = (item.global_position - center).dot(dir)

		# Stop at the end if no next belt
		if offset_along >= _belt_half_length - 2.0 and not has_next_belt:
			continue

		# Check if moving would get too close to any item AHEAD on the belt
		var next_pos: Vector2 = item.global_position + dir * speed * delta
		var blocked: bool = false
		for i in range(all_positions.size()):
			if all_positions[i] == item.global_position:
				continue
			var diff: Vector2 = all_positions[i] - next_pos
			var ahead_dist: float = diff.dot(dir)
			if ahead_dist >= 0.0 and ahead_dist < min_spacing:
				blocked = true
				break
		if blocked:
			continue

		# Update position in the tracking array
		var idx: int = all_positions.find(item.global_position)
		item.global_position = next_pos
		if idx >= 0:
			all_positions[idx] = next_pos

		# Snap to belt center on the perpendicular axis
		if abs(dir.x) > 0.5:
			var diff_y: float = center.y - item.global_position.y
			if abs(diff_y) > 1.0:
				item.global_position.y += sign(diff_y) * min(lane_snap_speed * delta, abs(diff_y))
		elif abs(dir.y) > 0.5:
			var diff_x: float = center.x - item.global_position.x
			if abs(diff_x) > 1.0:
				item.global_position.x += sign(diff_x) * min(lane_snap_speed * delta, abs(diff_x))


func _get_items_on_belt(space: PhysicsDirectSpaceState2D, placeable: Placeable) -> Array[Node2D]:
	var items: Array[Node2D] = []
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _belt_shape
	params.transform = placeable.global_transform * _belt_shape_transform
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = _collect_rids(placeable)
	var results := space.intersect_shape(params, 32)

	for result in results:
		var body: Node = result["collider"]
		if _is_placeable_child(body):
			continue
		if _is_mineable_collider(body):
			continue
		var item: Node2D = body.get_parent()
		if item == null:
			continue
		if not items.has(item):
			items.append(item)

	return items


func _has_belt_ahead(dir: Vector2) -> bool:
	var placeable = get_parent() as Placeable
	var dir_i := Vector2i(int(dir.x), int(dir.y))
	for i in range(1, 4):
		var check_cell: Vector2i = placeable.cell + dir_i * i
		for node in get_tree().get_nodes_in_group("placeable"):
			if node is Placeable and not node.is_pipe and node.cell == check_cell:
				for c in node.get_children():
					if c.get_script() == get_script():
						return true
	return false


func _get_belt_direction(placeable: Placeable) -> Vector2:
	match placeable.direction:
		Placeable.Dir.UP:
			return Vector2(0, -1)
		Placeable.Dir.DOWN:
			return Vector2(0, 1)
		Placeable.Dir.LEFT:
			return Vector2(-1, 0)
		Placeable.Dir.RIGHT:
			return Vector2(1, 0)
	return Vector2(1, 0)


func _collect_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject2D:
		rids.append(node.get_rid())
	for c in node.get_children():
		var child_rids := _collect_rids(c)
		rids.append_array(child_rids)
	return rids



func _is_closest_belt(item: Node2D) -> bool:
	var my_placeable = get_parent() as Placeable
	var my_dist: float = item.global_position.distance_squared_to(my_placeable.global_position)
	for node in get_tree().get_nodes_in_group("placeable"):
		if node is Placeable and not node.is_pipe and node != my_placeable:
			for c in node.get_children():
				if c.get_script() == get_script():
					var dist: float = item.global_position.distance_squared_to(node.global_position)
					if dist < my_dist:
						return false
	return true


func _is_mineable_collider(node: Node) -> bool:
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
