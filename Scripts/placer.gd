extends Node2D

@export var cell_size: int = 32
@export var selected_scene: PackedScene
@export var world: Node2D
@export var show_grid: bool = true
@export var grid_color: Color = Color(1, 1, 1, 0.35)
@export var grid_radius_cells: int = 12
@export var place_sound: AudioStream

var _ghost: Node2D
var _ghost_shape: CollisionShape2D
var _collider_offset: Vector2 = Vector2.ZERO
var _placed: Array[Node2D] = []
var _slot_1: PackedScene
var _left_held: bool = false


func _ready() -> void:
	_slot_1 = selected_scene


func _process(_delta: float) -> void:
	queue_redraw()

	if selected_scene == null:
		_clear_ghost()
		return

	if _ghost == null:
		_spawn_ghost()

	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	_ghost.global_position = _cell_to_world(cell) - _collider_offset

	var blocked: bool = _is_blocked(_cell_to_world(cell))
	_tint(_ghost, Color(1, 0.3, 0.3, 0.6) if blocked else Color(0.3, 1, 0.3, 0.6))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_left_held = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and selected_scene:
			if not _left_held:
				var cell: Vector2i = _world_to_cell(get_global_mouse_position())
				var pos: Vector2 = _cell_to_world(cell)
				if not _is_blocked(pos):
					_place(pos)
				_left_held = true
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_at(get_global_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			selected_scene = null
		elif event.keycode == KEY_G:
			show_grid = not show_grid
		elif event.keycode == KEY_1:
			selected_scene = _slot_1


func _draw() -> void:
	if not show_grid or _ghost == null:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	var line_width: float = 1.0 / (cam.zoom.x if cam else 1.0)
	var center: Vector2 = _ghost.global_position if _ghost else get_global_mouse_position()
	var center_cell: Vector2i = _world_to_cell(center)
	var r: int = grid_radius_cells
	var max_dist: float = float(r * cell_size)

	for dx in range(-r, r + 2):
		for dy in range(-r, r + 1):
			var a: Vector2 = Vector2((center_cell.x + dx) * cell_size, (center_cell.y + dy) * cell_size)
			var b: Vector2 = a + Vector2(0, cell_size)
			var d: float = a.lerp(b, 0.5).distance_to(center)
			if d >= max_dist:
				continue
			var col: Color = grid_color
			col.a *= 1.0 - d / max_dist
			draw_line(to_local(a), to_local(b), col, line_width)

	for dy in range(-r, r + 2):
		for dx in range(-r, r + 1):
			var a: Vector2 = Vector2((center_cell.x + dx) * cell_size, (center_cell.y + dy) * cell_size)
			var b: Vector2 = a + Vector2(cell_size, 0)
			var d: float = a.lerp(b, 0.5).distance_to(center)
			if d >= max_dist:
				continue
			var col: Color = grid_color
			col.a *= 1.0 - d / max_dist
			draw_line(to_local(a), to_local(b), col, line_width)


func _spawn_ghost() -> void:
	_ghost = selected_scene.instantiate()
	add_child(_ghost)
	_apply_display_scale(_ghost)
	_ghost_shape = _find_collision_shape(_ghost)
	_collider_offset = _get_collider_offset(_ghost, _ghost_shape)
	_disable_physics(_ghost)
	_force_on_top(_ghost)


func _force_on_top(node: Node) -> void:
	if node is CanvasItem:
		node.z_index = 4096
		node.z_as_relative = false
	for c in node.get_children():
		_force_on_top(c)


func _get_collider_offset(root: Node2D, shape: CollisionShape2D) -> Vector2:
	if shape == null:
		return Vector2.ZERO
	return (shape.global_position - root.global_position)


func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_shape = null
		_collider_offset = Vector2.ZERO


func _place(pos: Vector2) -> void:
	var obj: Node2D = selected_scene.instantiate()
	var parent: Node = world if world else get_tree().current_scene
	if parent is Node2D:
		(parent as Node2D).y_sort_enabled = true
	parent.add_child(obj)
	obj.global_position = pos - _collider_offset
	obj.z_index = 1
	obj.z_as_relative = false
	obj.y_sort_enabled = true
	_apply_display_scale(obj)
	_placed.append(obj)
	if place_sound:
		var sfx := AudioStreamPlayer.new()
		sfx.stream = place_sound
		sfx.bus = &"Master"
		add_child(sfx)
		sfx.play()
		sfx.finished.connect(sfx.queue_free)


func _apply_display_scale(node: Node2D) -> void:
	node.scale = Vector2.ONE
	if not node is Placeable:
		return
	var target_px: float = (node as Placeable).display_size_px
	var native: Vector2 = _get_native_size(node)
	if native.x <= 0 or native.y <= 0:
		return
	var s: float = target_px / maxf(native.x, native.y)
	node.scale = Vector2(s, s)


func _get_native_size(node: Node) -> Vector2:
	for c in node.get_children():
		if c is AnimatedSprite2D and c.sprite_frames and c.sprite_frames.has_animation(c.animation):
			var tex: Texture2D = c.sprite_frames.get_frame_texture(c.animation, 0)
			if tex:
				return tex.get_size()
		elif c is Sprite2D and c.texture:
			return c.texture.get_size()
		var recursed: Vector2 = _get_native_size(c)
		if recursed != Vector2.ZERO:
			return recursed
	return Vector2.ZERO


func _remove_at(pos: Vector2) -> void:
	var cell: Vector2i = _world_to_cell(pos)
	var target_pos: Vector2 = _cell_to_world(cell)
	for i in range(_placed.size() - 1, -1, -1):
		if _placed[i].global_position.distance_to(target_pos) < cell_size * 0.5:
			_placed[i].queue_free()
			_placed.remove_at(i)
			return


func _is_blocked(pos: Vector2) -> bool:
	if _ghost_shape == null or _ghost_shape.shape == null:
		return false
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _ghost_shape.shape
	params.transform = Transform2D(0, _ghost_shape.scale, 0, pos + _ghost_shape.position)
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = _collect_rids(_ghost)
	var hits := space.intersect_shape(params, 1)
	return hits.size() > 0


func _collect_rids(node: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if node is CollisionObject2D:
		rids.append(node.get_rid())
	for c in node.get_children():
		rids.append_array(_collect_rids(c))
	return rids


func _find_collision_shape(node: Node) -> CollisionShape2D:
	if node is CollisionShape2D:
		return node
	for c in node.get_children():
		var found := _find_collision_shape(c)
		if found:
			return found
	return null


func _disable_physics(node: Node) -> void:
	if node is CollisionObject2D:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for c in node.get_children():
		_disable_physics(c)


func _tint(node: Node, color: Color) -> void:
	if node is CanvasItem:
		node.modulate = color
	for c in node.get_children():
		_tint(c, color)


func _world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / cell_size), floor(pos.y / cell_size))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size / 2.0, cell.y * cell_size + cell_size / 2.0)
