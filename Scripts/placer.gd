extends Node2D

@export var cell_size: int = 32
@export var selected_scene: PackedScene
@export var placeable_scenes: Array[PackedScene] = []
@export var world: Node2D
@export_node_path("Label") var item_label: NodePath
@export_node_path("Label") var hover_label: NodePath
@export var show_grid: bool = true
@export var grid_color: Color = Color(1, 1, 1, 0.35)
@export var grid_radius_cells: int = 12
@export var place_sound: AudioStream

var _ghost: Node2D
var _ghost_shape: CollisionShape2D
var _placed: Array[Node2D] = []
var _left_held: bool = false
var _right_held: bool = false
var _last_place_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _last_remove_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _selected_index: int = -1
var _item_label_ref: Label
var _hover_label_ref: Label
var _hovered_placeable: Placeable
var _current_direction: int = Placeable.Dir.RIGHT
var _selected_is_pipe: bool = false
var _selected_is_miner: bool = false
var _selected_ignore_pipe_dir: bool = false
var _selected_is_belt: bool = false


func _ready() -> void:
	_item_label_ref = get_node_or_null(item_label) as Label
	_hover_label_ref = get_node_or_null(hover_label) as Label
	_update_hover_label(null)

	if placeable_scenes.is_empty() and selected_scene != null:
		placeable_scenes.append(selected_scene)

	if placeable_scenes.is_empty():
		_select_index(-1)
		return

	var initial_index := 0
	if selected_scene != null:
		var existing_index := placeable_scenes.find(selected_scene)
		if existing_index >= 0:
			initial_index = existing_index

	_select_index(initial_index)


func _process(_delta: float) -> void:
	queue_redraw()

	# Right-click hold deletes continuously, works even with no selection
	if _right_held:
		_try_remove_at_mouse()

	if selected_scene == null:
		_left_held = false
		_last_place_cell = Vector2i(2147483647, 2147483647)
		_clear_ghost()
		return

	if _ghost == null:
		_spawn_ghost()
		show_grid = true

	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	_ghost.global_position = _cell_to_world(cell)

	var blocked: bool = _is_blocked(_cell_to_world(cell))
	_tint(_ghost, Color(1, 0.3, 0.3, 0.6) if blocked else Color(0.3, 1, 0.3, 0.6))

	if _left_held:
		_try_place_at_mouse()

	_refresh_hover()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_left_held = false
			_last_place_cell = Vector2i(2147483647, 2147483647)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_held = false
			_last_remove_cell = Vector2i(2147483647, 2147483647)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and selected_scene:
			if not _left_held:
				_left_held = true
				_try_place_at_mouse()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_held = true
			_last_remove_cell = Vector2i(2147483647, 2147483647)
			_try_remove_at_mouse()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_select_index(-1)
		elif event.keycode == KEY_R:
			_cycle_direction()
		elif event.keycode == KEY_T:
			_toggle_pipe_cross()
		elif event.keycode == KEY_G:
			show_grid = not show_grid
		elif event.keycode == KEY_1:
			_select_index(0)
		elif event.keycode == KEY_2:
			_select_index(1)
		elif event.keycode == KEY_3:
			_select_index(2)
		elif event.keycode == KEY_4:
			_select_index(3)


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
	if _ghost is Placeable:
		var p := _ghost as Placeable
		p.ghost_mode = true
		p.direction = _current_direction
	_disable_physics(_ghost)
	add_child(_ghost)
	_apply_selected_animation(_ghost)
	_apply_display_scale(_ghost)
	_ghost_shape = _find_collision_shape(_ghost)
	_force_on_top(_ghost)


func _force_on_top(node: Node) -> void:
	if node is CanvasItem:
		node.z_index = 4096
		node.z_as_relative = false
	for c in node.get_children():
		_force_on_top(c)


func _clear_ghost() -> void:
	if _ghost:
		_ghost.queue_free()
		_ghost = null
		_ghost_shape = null


func _place(pos: Vector2) -> void:
	var cell: Vector2i = _world_to_cell(pos)
	var obj: Node2D = selected_scene.instantiate()
	var parent: Node = world if world else get_tree().current_scene
	if parent is Node2D:
		(parent as Node2D).y_sort_enabled = true
	if obj is Placeable:
		var p := obj as Placeable
		p.direction = _current_direction
		p.cell = cell
		if obj is ElectricalPipe and _ghost is ElectricalPipe:
			(obj as ElectricalPipe).force_cross = (_ghost as ElectricalPipe).force_cross
	parent.add_child(obj)
	_apply_selected_animation(obj)
	obj.global_position = pos
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


func _try_place_at_mouse() -> void:
	if selected_scene == null:
		return

	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	if cell == _last_place_cell:
		return

	var pos: Vector2 = _cell_to_world(cell)
	if _is_blocked(pos):
		return

	_place(pos)
	_last_place_cell = cell


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


func _try_remove_at_mouse() -> void:
	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	if cell == _last_remove_cell:
		return
	_last_remove_cell = cell
	_remove_at(get_global_mouse_position())


func _remove_at(pos: Vector2) -> void:
	var cell: Vector2i = _world_to_cell(pos)
	# First pass: remove a machine (non-pipe) at this cell
	for i in range(_placed.size() - 1, -1, -1):
		var node = _placed[i]
		if node is Placeable and not (node as Placeable).is_pipe:
			if (node as Placeable).cell == cell:
				node.queue_free()
				_placed.remove_at(i)
				return
	# Second pass: remove a pipe if no machine was found
	for i in range(_placed.size() - 1, -1, -1):
		var node = _placed[i]
		if node is Placeable and (node as Placeable).cell == cell:
			node.queue_free()
			_placed.remove_at(i)
			return


func _is_blocked(pos: Vector2) -> bool:
	var cell: Vector2i = _world_to_cell(pos)
	var pg := get_node_or_null("/root/PowerGrid")

	# Miners can only be placed on Mineable areas
	if _selected_is_miner:
		if not _is_over_mineable(pos):
			return true

	# Belts can be placed anywhere, skip all checks
	if _selected_is_belt:
		print("Belt: not blocked")
		return false

	if _selected_is_pipe:
		# Pipes: blocked if a pipe already exists at this cell
		if pg != null and pg.has_pipe_at(cell):
			return true
		# Block placing if adjacent pipe has conflicting orientation
		if pg != null and _ghost is ElectricalPipe:
			var ghost_pipe := _ghost as ElectricalPipe
			var ghost_horizontal: bool = not ghost_pipe.force_cross and _current_direction in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]
			var ghost_vertical: bool = not ghost_pipe.force_cross and _current_direction in [Placeable.Dir.UP, Placeable.Dir.DOWN]
			for offset in PowerGrid.NEIGHBOR_OFFSETS:
				var nc: Vector2i = cell + offset
				var neighbor = pg.get_pipe_at(nc)
				if neighbor == null or not (neighbor is ElectricalPipe):
					continue
				var n := neighbor as ElectricalPipe
				if n.force_cross:
					continue
				var n_horizontal: bool = (n.connection_mask & (ElectricalPipe.LEFT_BIT | ElectricalPipe.RIGHT_BIT)) != 0 and (n.connection_mask & (ElectricalPipe.UP_BIT | ElectricalPipe.DOWN_BIT)) == 0
				var n_vertical: bool = (n.connection_mask & (ElectricalPipe.UP_BIT | ElectricalPipe.DOWN_BIT)) != 0 and (n.connection_mask & (ElectricalPipe.LEFT_BIT | ElectricalPipe.RIGHT_BIT)) == 0
				if ghost_horizontal and n_vertical:
					return true
				if ghost_vertical and n_horizontal:
					return true
	else:
		# Machines: MUST have a pipe underneath, and no other machine
		if pg == null or not pg.has_pipe_at(cell):
			return true
		if pg.has_machine_at(cell):
			return true
		# Block if machine direction doesn't match the pipe's orientation
		if not _selected_ignore_pipe_dir:
			var pipe = pg.get_pipe_at(cell)
			if pipe != null and pipe is ElectricalPipe and not (pipe as ElectricalPipe).force_cross:
				var p := pipe as ElectricalPipe
				var p_horizontal: bool = (p.connection_mask & (ElectricalPipe.LEFT_BIT | ElectricalPipe.RIGHT_BIT)) != 0 and (p.connection_mask & (ElectricalPipe.UP_BIT | ElectricalPipe.DOWN_BIT)) == 0
				var p_vertical: bool = (p.connection_mask & (ElectricalPipe.UP_BIT | ElectricalPipe.DOWN_BIT)) != 0 and (p.connection_mask & (ElectricalPipe.LEFT_BIT | ElectricalPipe.RIGHT_BIT)) == 0
				var machine_horizontal: bool = _current_direction in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]
				var machine_vertical: bool = _current_direction in [Placeable.Dir.UP, Placeable.Dir.DOWN]
				if machine_horizontal and p_vertical:
					return true
				if machine_vertical and p_horizontal:
					return true

	# Physics overlap check (catches terrain, other non-grid obstacles)
	if _ghost_shape == null or _ghost_shape.shape == null:
		return false
	var space := get_world_2d().direct_space_state
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = _ghost_shape.shape
	var ghost_shape_local: Transform2D = _ghost.global_transform.affine_inverse() * _ghost_shape.global_transform
	var placement_transform := _ghost.global_transform
	placement_transform.origin = pos
	params.transform = placement_transform * ghost_shape_local
	params.collide_with_bodies = true
	params.collide_with_areas = true
	params.exclude = _collect_rids(_ghost)
	var hits := space.intersect_shape(params, 10)

	# Filter out Mineable areas and loose items (ore etc.) from hits
	var filtered_hits: Array = []
	for hit in hits:
		var collider: Node = hit.get("collider")
		if _is_mineable_area(collider):
			continue
		# Skip loose items (not part of any placeable)
		if _find_placeable_ancestor(collider) == null:
			continue
		filtered_hits.append(hit)

	if filtered_hits.is_empty():
		return false

	# When placing a machine, ignore collisions with the pipe underneath
	if not _selected_is_pipe:
		for hit in filtered_hits:
			var collider: Node = hit.get("collider")
			if collider == null:
				return true
			var placeable := _find_placeable_ancestor(collider)
			if placeable == null or not placeable.is_pipe:
				return true
		return false

	return true


func _is_mineable_area(node: Node) -> bool:
	if node is Area2D:
		for c in node.get_children():
			if c.name == "Mineable":
				return true
	return false


func _find_placeable_ancestor(node: Node) -> Placeable:
	var current: Node = node
	while current != null:
		if current is Placeable:
			return current as Placeable
		current = current.get_parent()
	return null


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
		if node is StaticBody2D or node is Area2D:
			for c in node.get_children():
				if c is CollisionShape2D:
					c.disabled = true
	for c in node.get_children():
		_disable_physics(c)


func _tint(node: Node, color: Color) -> void:
	if node is CanvasItem:
		node.modulate = color
	for c in node.get_children():
		_tint(c, color)


func _is_over_mineable(pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results := space.intersect_point(params, 32)
	for result in results:
		var collider = result["collider"]
		if _is_mineable_area(collider):
			return true
	return false


func _world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floor(pos.x / cell_size), floor(pos.y / cell_size))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size / 2.0, cell.y * cell_size + cell_size / 2.0)


func _select_index(index: int) -> void:
	_left_held = false
	_last_place_cell = Vector2i(2147483647, 2147483647)

	if index < 0:
		_selected_index = -1
		selected_scene = null
		_update_item_label()
		_clear_ghost()
		return

	if index >= placeable_scenes.size():
		return

	_selected_index = index
	selected_scene = placeable_scenes[index]
	_cache_scene_properties()
	_update_item_label()
	_clear_ghost()


func _cache_scene_properties() -> void:
	_selected_is_pipe = false
	_selected_is_miner = false
	if selected_scene == null:
		return
	var temp := selected_scene.instantiate()
	if temp is Placeable:
		_selected_is_pipe = (temp as Placeable).is_pipe
		_selected_is_miner = (temp as Placeable).is_miner
		_selected_ignore_pipe_dir = (temp as Placeable).ignore_pipe_direction
		_selected_is_belt = (temp as Placeable).is_belt
	temp.free()


func _update_item_label() -> void:
	if _item_label_ref == null:
		return

	if selected_scene == null:
		_item_label_ref.text = "Item: None"
		return

	_item_label_ref.text = "Item: %s\nDir: %s" % [_get_scene_display_name(selected_scene), Placeable.direction_name(_current_direction).to_upper()]


func _get_scene_display_name(scene: PackedScene) -> String:
	if scene == null:
		return "None"

	var instance := scene.instantiate()
	var display_name := ""

	if instance is Placeable:
		display_name = (instance as Placeable).item_name.strip_edges()

	if display_name.is_empty():
		display_name = instance.name.strip_edges()

	if instance != null:
		instance.free()

	if not display_name.is_empty() and display_name != "Node2D":
		return display_name

	return scene.resource_path.get_file().get_basename()


func _cycle_direction() -> void:
	var order: Array[int] = [Placeable.Dir.UP, Placeable.Dir.RIGHT, Placeable.Dir.DOWN, Placeable.Dir.LEFT]
	var available: Array[int] = _available_directions(order)
	if available.is_empty():
		available = order
	var start_idx: int = available.find(_current_direction)
	var next_idx: int = 0 if start_idx < 0 else (start_idx + 1) % available.size()
	_current_direction = available[next_idx]
	_update_item_label()
	if _ghost:
		if _ghost is Placeable:
			(_ghost as Placeable).set_direction(_current_direction)
		else:
			_apply_selected_animation(_ghost)


func _toggle_pipe_cross() -> void:
	if _ghost == null or not (_ghost is ElectricalPipe):
		return
	var pipe := _ghost as ElectricalPipe
	pipe.force_cross = not pipe.force_cross
	pipe.apply_direction_animation()


func _available_directions(order: Array[int]) -> Array[int]:
	var out: Array[int] = []
	if _ghost == null:
		return out
	for d in order:
		if _direction_has_animation(d):
			out.append(d)
	return out


func _direction_has_animation(d: int) -> bool:
	if _ghost == null:
		return true
	for anim_name in _anim_fallbacks(d):
		if _node_has_animation(_ghost, anim_name):
			return true
	return false


func _anim_fallbacks(d: int) -> Array:
	match d:
		Placeable.Dir.LEFT:
			return ["left", "default"]
		Placeable.Dir.RIGHT:
			return ["right", "default"]
		Placeable.Dir.UP:
			return ["up", "Rotated"]
		Placeable.Dir.DOWN:
			return ["down", "Rotated"]
	return ["default"]


func _node_has_animation(node: Node, anim_name: String) -> bool:
	if node is AnimatedSprite2D:
		var s := node as AnimatedSprite2D
		if s.sprite_frames != null and s.sprite_frames.has_animation(anim_name):
			return true
	for c in node.get_children():
		if _node_has_animation(c, anim_name):
			return true
	return false


func _apply_selected_animation(node: Node) -> void:
	_set_animation_recursive(node, _current_direction)


func _refresh_hover() -> void:
	if _hover_label_ref == null:
		return
	var hovered: Placeable = _find_placeable_at_mouse()
	if hovered == _hovered_placeable:
		if hovered != null:
			_update_hover_label(hovered)
		return
	if _hovered_placeable != null and is_instance_valid(_hovered_placeable):
		if _hovered_placeable.power_state_changed.is_connected(_on_hovered_power_changed):
			_hovered_placeable.power_state_changed.disconnect(_on_hovered_power_changed)
	_hovered_placeable = hovered
	if _hovered_placeable != null:
		if not _hovered_placeable.power_state_changed.is_connected(_on_hovered_power_changed):
			_hovered_placeable.power_state_changed.connect(_on_hovered_power_changed)
	_update_hover_label(_hovered_placeable)


func _find_placeable_at_mouse() -> Placeable:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var mouse_cell: Vector2i = _world_to_cell(mouse_pos)
	var pg := get_node_or_null("/root/PowerGrid")
	if pg != null:
		# Machines on top take hover priority
		if pg.has_machine_at(mouse_cell):
			var m: Placeable = pg._machines[mouse_cell]
			if is_instance_valid(m):
				return m
		if pg.has_pipe_at(mouse_cell):
			var p: Placeable = pg._pipes[mouse_cell]
			if is_instance_valid(p):
				return p
	for node in _placed:
		if not is_instance_valid(node):
			continue
		if not (node is Placeable):
			continue
		var pl: Placeable = node as Placeable
		var half: float = cell_size * pl.effective_span() / 2.0
		var rect := Rect2(pl.global_position - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
		if rect.has_point(mouse_pos):
			return pl
	return null


func _on_hovered_power_changed(_is_powered: bool) -> void:
	if _hovered_placeable != null and is_instance_valid(_hovered_placeable):
		_update_hover_label(_hovered_placeable)


func _update_hover_label(p: Placeable) -> void:
	if _hover_label_ref == null:
		return
	if p == null or not is_instance_valid(p):
		_hover_label_ref.text = ""
		return
	var role: String
	if p.watts_produced > 0.0 and p.watts_consumed > 0.0:
		role = "Input + Output"
	elif p.watts_produced > 0.0:
		role = "Output"
	elif p.watts_consumed > 0.0:
		role = "Input"
	else:
		role = "Passive"
	var state: String
	if p.watts_consumed <= 0.0:
		state = "N/A"
	else:
		state = "ON" if p.powered else "OFF"
	var name_str: String = p.item_name if p.item_name != "" else String(p.name)
	_hover_label_ref.text = "%s\nStatus: %s\nRole: %s\nProduces: %.1f W\nConsumes: %.1f W\nDir: %s\nCell: (%d, %d)" % [
		name_str,
		state,
		role,
		p.watts_produced,
		p.watts_consumed,
		Placeable.direction_name(p.direction).to_upper(),
		p.cell.x,
		p.cell.y,
	]


func _set_animation_recursive(node: Node, d: int) -> void:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames != null:
			for anim_name in _anim_fallbacks(d):
				if sprite.sprite_frames.has_animation(anim_name):
					sprite.play(anim_name)
					break
	for child in node.get_children():
		_set_animation_recursive(child, d)
