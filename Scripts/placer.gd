extends Node2D

@export var cell_size: int = Placeable.CELL_SIZE
@export var selected_scene: PackedScene
@export var placeable_scenes: Array[PackedScene] = []
@export var world: Node2D
@export_node_path("Label") var item_label: NodePath
@export_node_path("Label") var hover_label: NodePath
@export var inventory_holder_path: NodePath
@export var hotbar_ui_path: NodePath
@export var add_placeables_to_inventory_on_start: bool = true
@export var starting_placeable_stack_size: int = 100
@export var show_grid: bool = true
@export var grid_color: Color = Color(1, 1, 1, 0.35)
@export var grid_radius_cells: int = 12
@export var place_sound: AudioStream
@export_group("Hover Direction")
@export var hover_direction_enabled: bool = true
@export var hover_rect_node_name: StringName = &"Hover"
@export var hover_arrow_node_name: StringName = &"Arrow"

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
var _pipe_inspect_active: bool = false
var _inventory_holder: InventoryHolder
var _hotbar_ui: HotbarUI
var _selected_inventory_slot_index: int = -1
var _selected_inventory_label: String = ""


func _ready() -> void:
	cell_size = Placeable.CELL_SIZE
	z_index = 4095
	z_as_relative = false

	_item_label_ref = get_node_or_null(item_label) as Label
	_hover_label_ref = get_node_or_null(hover_label) as Label
	_resolve_inventory_holder()
	_update_hover_label(null)
	call_deferred("_connect_hotbar")
	call_deferred("_add_placeable_scenes_to_inventory")

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

	_refresh_hover()

	if selected_scene == null:
		_left_held = false
		_last_place_cell = Vector2i(2147483647, 2147483647)
		_clear_ghost()
		return

	if _ghost == null:
		_spawn_ghost()

	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	_ghost.global_position = _cell_to_world(cell)

	var blocked: bool = not _can_update_same_object_at_cell(cell) and _is_blocked(_cell_to_world(cell))
	_tint(_ghost, Color(1, 0.3, 0.3, 0.6) if blocked else Color(0.3, 1, 0.3, 0.6))

	if _left_held:
		_try_place_at_mouse()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_left_held = false
			_last_place_cell = Vector2i(2147483647, 2147483647)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_held = false
			_last_remove_cell = Vector2i(2147483647, 2147483647)
	elif event is InputEventKey:
		if event.keycode == KEY_ALT:
			_set_pipe_inspect(event.pressed)


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
			if selected_scene != null:
				if not _selected_is_pipe:
					_cycle_direction()
			elif not _rotate_hovered_placeable():
				_cycle_direction()
		elif event.keycode == KEY_T:
			_toggle_pipe_cross()
		elif event.keycode == KEY_G:
			show_grid = not show_grid
		elif event.keycode == KEY_1:
			_select_hotbar_or_placeable(0)
		elif event.keycode == KEY_2:
			_select_hotbar_or_placeable(1)
		elif event.keycode == KEY_3:
			_select_hotbar_or_placeable(2)
		elif event.keycode == KEY_4:
			_select_hotbar_or_placeable(3)
		elif event.keycode == KEY_5:
			_select_hotbar_or_placeable(4)
		elif event.keycode == KEY_6:
			_select_hotbar_or_placeable(5)
		elif event.keycode == KEY_7:
			_select_hotbar_or_placeable(6)
		elif event.keycode == KEY_8:
			_select_hotbar_or_placeable(7)
		elif event.keycode == KEY_9:
			_select_hotbar_or_placeable(8)
		elif event.keycode == KEY_0:
			_select_hotbar_or_placeable(9)


func _draw() -> void:
	if not show_grid:
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
		if p is ElectricalPipe:
			(p as ElectricalPipe).force_cross = true
		_apply_direction_to_placeable(p, _current_direction)
	_disable_physics(_ghost)
	add_child(_ghost)
	_apply_direction_to_node(_ghost, _current_direction)
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
		if not p.is_pipe:
			_ensure_pipe_under_machine(cell, pos, parent, p)
		_apply_direction_to_placeable(p, _current_direction)
		p.cell = cell
		if obj is ElectricalPipe:
			(obj as ElectricalPipe).force_cross = true
	parent.add_child(obj)
	_apply_direction_to_node(obj, _current_direction)
	obj.global_position = pos
	obj.z_index = 1
	obj.z_as_relative = false
	obj.y_sort_enabled = true
	_apply_display_scale(obj)
	_placed.append(obj)
	_play_place_sound()


func _ensure_pipe_under_machine(cell: Vector2i, _pos: Vector2, parent: Node, machine: Placeable) -> void:
	var support_cells: Array[Vector2i] = [cell]
	if machine.footprint_height() >= 4:
		support_cells.append(cell + Vector2i(0, -2))
	for support_cell in support_cells:
		_ensure_pipe_at_cell(support_cell, _cell_to_world(support_cell), parent, true, _current_direction)


func _ensure_pipe_at_cell(cell: Vector2i, pos: Vector2, parent: Node, _force_cross: bool = false, pipe_direction: int = -1) -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg != null and pg.has_pipe_at(cell):
		_adapt_pipe_for_machine_direction(cell, pipe_direction if pipe_direction >= 0 else _current_direction, true)
		return
	var pipe_scene: PackedScene = _get_electrical_pipe_scene()
	if pipe_scene == null:
		return
	var pipe_obj: Node2D = pipe_scene.instantiate()
	if pipe_obj is ElectricalPipe:
		(pipe_obj as ElectricalPipe).force_cross = true
	if pipe_obj is Placeable:
		var pipe_placeable: Placeable = pipe_obj as Placeable
		_apply_direction_to_placeable(pipe_placeable, pipe_direction if pipe_direction >= 0 else _current_direction)
		pipe_placeable.cell = cell
	pipe_obj.global_position = pos
	pipe_obj.y_sort_enabled = true
	_apply_display_scale(pipe_obj)
	parent.add_child(pipe_obj)
	_apply_direction_to_node(pipe_obj, pipe_direction if pipe_direction >= 0 else _current_direction)
	_placed.append(pipe_obj)


func _adapt_pipe_for_machine_direction(cell: Vector2i, machine_direction: int, force_all: bool = false) -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	var pipe = pg.get_pipe_at(cell)
	if pipe == null or not (pipe is ElectricalPipe):
		return
	var electrical_pipe := pipe as ElectricalPipe
	if force_all:
		electrical_pipe.force_cross = true
	elif electrical_pipe.force_cross:
		pass
	elif _directions_share_axis(electrical_pipe.direction, machine_direction):
		_apply_direction_to_placeable(electrical_pipe, machine_direction)
	else:
		electrical_pipe.force_cross = true
	electrical_pipe.update_connections()
	electrical_pipe._notify_neighbors()
	pg.mark_dirty()


func _get_electrical_pipe_scene() -> PackedScene:
	for scene in placeable_scenes:
		if scene == null:
			continue
		var instance := scene.instantiate()
		var is_electrical_pipe := instance is ElectricalPipe
		instance.free()
		if is_electrical_pipe:
			return scene
	return null


func _update_same_object_at_cell(cell: Vector2i) -> bool:
	if _selected_is_pipe:
		return false
	var existing := _get_same_object_at_anchor_cell(cell)
	if existing == null:
		return false
	if not _same_object_needs_direction_update(existing, cell):
		return false
	_apply_direction_to_placeable(existing, _current_direction)
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if existing is ElectricalPipe and _ghost is ElectricalPipe:
		(existing as ElectricalPipe).force_cross = (_ghost as ElectricalPipe).force_cross
	if existing is ElectricalPipe:
		(existing as ElectricalPipe).update_connections()
	elif pg != null:
		for support_cell in _support_cells_for_placeable(existing, cell):
			var existing_pipe = pg.get_pipe_at(support_cell)
			if existing_pipe != null and existing_pipe is ElectricalPipe:
				_adapt_pipe_for_machine_direction(support_cell, _current_direction, true)
	if pg != null:
		pg.mark_dirty()
	_play_place_sound()
	return true


func _can_update_same_object_at_cell(cell: Vector2i) -> bool:
	if _selected_is_pipe:
		return false
	var existing := _get_same_object_at_anchor_cell(cell)
	return existing != null and _same_object_needs_direction_update(existing, cell)


func _same_object_needs_direction_update(existing: Placeable, cell: Vector2i) -> bool:
	if existing.direction != _current_direction:
		return true
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null or existing is ElectricalPipe:
		return false
	var pipe = pg.get_pipe_at(cell)
	if pipe == null or not (pipe is ElectricalPipe):
		return false
	var electrical_pipe := pipe as ElectricalPipe
	if electrical_pipe.force_cross:
		return false
	if not _directions_share_axis(electrical_pipe.direction, _current_direction):
		return true
	return electrical_pipe.direction != _current_direction


func _get_same_object_at_anchor_cell(cell: Vector2i) -> Placeable:
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return null
	var existing: Placeable = null
	if _selected_is_pipe:
		var pipe = pg.get_pipe_at(cell)
		if pipe != null and pipe is Placeable:
			existing = pipe as Placeable
	elif pg.has_machine_at(cell):
		var machine = pg._machines.get(cell, null)
		if machine != null and machine is Placeable:
			existing = machine as Placeable
	if existing == null or not is_instance_valid(existing):
		return null
	if not _selected_scene_matches_placeable(existing):
		return null
	return existing


func _selected_scene_matches_placeable(placeable: Placeable) -> bool:
	if selected_scene == null:
		return false
	var instance := selected_scene.instantiate()
	var matches: bool = instance.get_script() == placeable.get_script()
	if matches and instance is Placeable:
		var selected_name: String = (instance as Placeable).item_name.strip_edges()
		var existing_name: String = placeable.item_name.strip_edges()
		if selected_name != "" or existing_name != "":
			matches = selected_name == existing_name
	instance.free()
	return matches


func _play_place_sound() -> void:
	if place_sound == null:
		return
	var sfx := AudioStreamPlayer.new()
	sfx.stream = place_sound
	sfx.bus = &"Master"
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


func _try_place_at_mouse() -> void:
	if selected_scene == null:
		return
	if _selected_inventory_slot_index >= 0 and not _selected_inventory_has_placeable():
		return

	var cell: Vector2i = _world_to_cell(get_global_mouse_position())
	if cell == _last_place_cell:
		return

	var pos: Vector2 = _cell_to_world(cell)
	if _update_same_object_at_cell(cell):
		_last_place_cell = cell
		return
	if _is_blocked(pos):
		return

	if _selected_allows_belt_overlap():
		_remove_belts_in_selected_footprint(cell)
	_place(pos)
	_consume_selected_inventory_item()
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
	var placeables: Array[Placeable] = _get_registered_placeables()
	# First pass: remove a machine (non-pipe) at this cell
	for i in range(placeables.size() - 1, -1, -1):
		var node: Placeable = placeables[i]
		if node != null and is_instance_valid(node) and not node.is_pipe:
			if node.footprint_contains_cell(cell):
				if not _add_placeable_to_inventory(node):
					return
				_forget_and_free_placeable(node)
				return
	# Second pass: remove a pipe if no machine was found
	for i in range(placeables.size() - 1, -1, -1):
		var node: Placeable = placeables[i]
		if node != null and is_instance_valid(node) and node.footprint_contains_cell(cell):
			if not _add_placeable_to_inventory(node):
				return
			_forget_and_free_placeable(node)
			return
	if _remove_loose_item_at(pos):
		return


func _remove_belts_in_selected_footprint(anchor_cell: Vector2i) -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	var removed: Dictionary = {}
	for placeable in _get_registered_placeables():
		if placeable == null or not is_instance_valid(placeable) or removed.has(placeable):
			continue
		if not _is_belt_placeable(placeable):
			continue
		if not _footprints_intersect(_selected_footprint_cells(anchor_cell), placeable):
			continue
		removed[placeable] = true
		if pg != null and pg.has_method("unregister_machine"):
			pg.unregister_machine(placeable)
		var placed_index: int = _placed.find(placeable)
		if placed_index >= 0:
			_placed.remove_at(placed_index)
		placeable.queue_free()


func _forget_and_free_placeable(placeable: Placeable) -> void:
	var placed_index: int = _placed.find(placeable)
	if placed_index >= 0:
		_placed.remove_at(placed_index)
	placeable.queue_free()


func _selected_inventory_has_placeable() -> bool:
	var inventory: Inventory = _selected_inventory()
	if inventory == null:
		return false
	var slot: Dictionary = inventory.get_slot(_selected_inventory_slot_index)
	return not slot.is_empty() and String(slot.get("scene_path", "")).strip_edges() != ""


func _consume_selected_inventory_item() -> void:
	if _selected_inventory_slot_index < 0:
		return
	var inventory: Inventory = _selected_inventory()
	if inventory == null:
		return
	inventory.remove_from_slot(_selected_inventory_slot_index, 1)
	var slot: Dictionary = inventory.get_slot(_selected_inventory_slot_index)
	if slot.is_empty():
		_select_inventory_scene(null, _selected_inventory_slot_index, "")
	else:
		_on_hotbar_selection_changed(_selected_inventory_slot_index, slot)


func _selected_inventory() -> Inventory:
	_resolve_inventory_holder()
	if _inventory_holder == null:
		return null
	return _inventory_holder.get_inventory()


func _resolve_inventory_holder() -> void:
	if _inventory_holder != null and is_instance_valid(_inventory_holder):
		return
	if inventory_holder_path != NodePath(""):
		_inventory_holder = get_node_or_null(inventory_holder_path) as InventoryHolder
		if _inventory_holder != null:
			return
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		_inventory_holder = current_scene.find_child("PlayerInventory", true, false) as InventoryHolder
		if _inventory_holder != null:
			return
	_inventory_holder = get_tree().root.find_child("PlayerInventory", true, false) as InventoryHolder


func _add_placeable_to_inventory(placeable: Placeable) -> bool:
	if placeable == null:
		print("Inventory pickup failed: placeable is null.")
		return false
	_resolve_inventory_holder()
	if _inventory_holder == null:
		print("Inventory pickup failed for %s: inventory_holder_path is not connected." % placeable.name)
		return false
	var item_type: String = placeable.item_name.strip_edges()
	if item_type == "":
		item_type = placeable.name.strip_edges()
	if item_type == "":
		item_type = "Placeable"
	var texture: Texture2D = _texture_for_node(placeable)
	var icon_path: String = _icon_path_for_texture(texture)
	var scene_path: String = _scene_path_for_placeable(placeable)
	var remaining: int = _inventory_holder.add_item(item_type, 1, texture, scene_path, icon_path)
	print("Inventory pickup placeable: type=%s remaining=%d scene_path=%s icon_path=%s has_texture=%s" % [
		item_type,
		remaining,
		scene_path,
		icon_path,
		str(texture != null),
	])
	return remaining == 0


func _remove_loose_item_at(pos: Vector2) -> bool:
	var loose_item: Node2D = _find_loose_item_at(pos)
	if loose_item == null:
		print("Inventory pickup failed: no loose item at mouse.")
		return false
	_resolve_inventory_holder()
	if _inventory_holder == null:
		print("Inventory pickup failed for %s: inventory_holder_path is not connected." % loose_item.name)
		return false
	var item_type: String = _item_type_for_loose_item(loose_item)
	var texture: Texture2D = _texture_for_node(loose_item)
	var icon_path: String = _icon_path_for_texture(texture)
	var remaining: int = _inventory_holder.add_item(item_type, 1, texture, "", icon_path)
	print("Inventory pickup loose item: type=%s remaining=%d icon_path=%s has_texture=%s" % [
		item_type,
		remaining,
		icon_path,
		str(texture != null),
	])
	if remaining != 0:
		return false
	loose_item.queue_free()
	return true


func _find_loose_item_at(pos: Vector2) -> Node2D:
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	params.position = pos
	params.collide_with_areas = true
	params.collide_with_bodies = true
	var results: Array[Dictionary] = space.intersect_point(params, 16)
	for result in results:
		var collider: Node = result.get("collider") as Node
		var loose_item: Node2D = _find_loose_item_ancestor(collider)
		if loose_item != null:
			return loose_item
	return null


func _find_loose_item_ancestor(node: Node) -> Node2D:
	var current: Node = node
	while current != null:
		if current is Placeable:
			return null
		if current is Node2D and current.name.to_lower().contains("ore"):
			return current as Node2D
		current = current.get_parent()
	return null


func _item_type_for_loose_item(item: Node) -> String:
	var sprite: Sprite2D = _find_sprite(item)
	if sprite != null:
		var sprite_name: String = sprite.name.to_lower().replace("ore", "").strip_edges()
		if sprite_name != "":
			return sprite_name
	return item.name.to_lower()


func _scene_path_for_placeable(placeable: Placeable) -> String:
	for scene in placeable_scenes:
		if scene == null:
			continue
		if _scene_matches_placeable(scene, placeable):
			return scene.resource_path
	return ""


func _scene_matches_placeable(scene: PackedScene, placeable: Placeable) -> bool:
	var instance: Node = scene.instantiate()
	var matches: bool = instance.get_script() == placeable.get_script()
	if matches and instance is Placeable:
		var selected_name: String = (instance as Placeable).item_name.strip_edges()
		var existing_name: String = placeable.item_name.strip_edges()
		if selected_name != "" or existing_name != "":
			matches = selected_name == existing_name
	instance.free()
	return matches


func _item_name_for_scene(scene: PackedScene) -> String:
	var instance: Node = scene.instantiate()
	var item_type: String = ""
	if instance is Placeable:
		item_type = (instance as Placeable).item_name.strip_edges()
	if item_type == "":
		item_type = instance.name.strip_edges()
	if item_type == "":
		item_type = scene.resource_path.get_file().get_basename()
	instance.free()
	return item_type


func _texture_for_scene(scene: PackedScene) -> Texture2D:
	var instance: Node = scene.instantiate()
	var texture: Texture2D = _texture_for_node(instance)
	instance.free()
	return texture


func _icon_path_for_texture(texture: Texture2D) -> String:
	if texture == null:
		return ""
	return texture.resource_path


func _texture_for_node(node: Node) -> Texture2D:
	if node is Sprite2D:
		var sprite_2d: Sprite2D = node as Sprite2D
		if sprite_2d.texture != null:
			return sprite_2d.texture
	if node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
			return sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var visible_texture: Texture2D = _texture_for_visible_child(node)
	if visible_texture != null:
		return visible_texture
	for child in node.get_children():
		var texture: Texture2D = _texture_for_node(child)
		if texture != null:
			return texture
	return null


func _texture_for_visible_child(node: Node) -> Texture2D:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Sprite2D:
			var sprite_2d: Sprite2D = child as Sprite2D
			if sprite_2d.texture != null:
				return sprite_2d.texture
		if child is AnimatedSprite2D:
			var sprite: AnimatedSprite2D = child as AnimatedSprite2D
			if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
				return sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
		var texture: Texture2D = _texture_for_visible_child(child)
		if texture != null:
			return texture
	return null


func _find_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var sprite: Sprite2D = _find_sprite(child)
		if sprite != null:
			return sprite
	return null


func _footprint_has_blocking_placeable(anchor_cell: Vector2i, allowed: Placeable = null, extra_allowed: Array = []) -> bool:
	for placeable in _get_registered_placeables():
		if placeable == null or not is_instance_valid(placeable) or placeable == allowed or extra_allowed.has(placeable):
			continue
		if _selected_allows_belt_overlap() and _is_belt_placeable(placeable):
			continue
		if _footprints_intersect(_selected_footprint_cells(anchor_cell), placeable):
			return true
	return false


func _get_placeable_anchor_at_cell(cell: Vector2i) -> Placeable:
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return null
	if pg.has_machine_at(cell):
		var machine = pg._machines.get(cell, null)
		if machine != null and machine is Placeable and is_instance_valid(machine):
			return machine as Placeable
	if pg.has_pipe_at(cell):
		var pipe = pg.get_pipe_at(cell)
		if pipe != null and pipe is Placeable and is_instance_valid(pipe):
			return pipe as Placeable
	return null


func _get_placeable_at_footprint_cell(cell: Vector2i) -> Placeable:
	var machines: Array[Placeable] = []
	var pipes: Array[Placeable] = []
	for placeable in _get_registered_placeables():
		if placeable == null or not is_instance_valid(placeable):
			continue
		if not placeable.footprint_contains_cell(cell):
			continue
		if placeable.is_pipe:
			pipes.append(placeable)
		else:
			machines.append(placeable)
	if not machines.is_empty():
		return machines[machines.size() - 1]
	if not pipes.is_empty():
		return pipes[pipes.size() - 1]
	return null


func _support_cells_for_selected_machine(anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor_cell]
	if _ghost is Placeable and (_ghost as Placeable).footprint_height() >= 4:
		cells.append(anchor_cell + Vector2i(0, -2))
	return cells


func _support_cells_for_placeable(placeable: Placeable, anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor_cell]
	if placeable != null and placeable.footprint_height() >= 4:
		cells.append(anchor_cell + Vector2i(0, -2))
	return cells


func _support_pipes_for_machine(anchor_cell: Vector2i) -> Array:
	var pipes: Array = []
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return pipes
	for support_cell in _support_cells_for_selected_machine(anchor_cell):
		var pipe = pg.get_pipe_at(support_cell)
		if pipe != null and pipe is Placeable and is_instance_valid(pipe):
			pipes.append(pipe)
	return pipes


func _get_registered_placeables() -> Array[Placeable]:
	var result: Array[Placeable] = []
	var seen: Dictionary = {}
	var pg := get_node_or_null("/root/PowerGrid")
	if pg != null:
		for machine in pg._machines.values():
			if machine != null and machine is Placeable and is_instance_valid(machine) and not seen.has(machine):
				result.append(machine as Placeable)
				seen[machine] = true
		for pipe in pg._pipes.values():
			if pipe != null and pipe is Placeable and is_instance_valid(pipe) and not seen.has(pipe):
				result.append(pipe as Placeable)
				seen[pipe] = true
	for node in _placed:
		if node != null and node is Placeable and is_instance_valid(node) and not seen.has(node):
			result.append(node as Placeable)
			seen[node] = true
	return result


func _set_pipe_inspect(active: bool) -> void:
	if _pipe_inspect_active == active:
		return
	_pipe_inspect_active = active
	for placeable in _get_registered_placeables():
		if placeable != null and is_instance_valid(placeable) and placeable is ElectricalPipe:
			(placeable as ElectricalPipe).set_inspect_visible(active)


func _footprints_intersect(cells: Array[Vector2i], placeable: Placeable) -> bool:
	for cell in cells:
		if placeable.footprint_contains_cell(cell):
			return true
	return false


func _selected_footprint_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	if _ghost is Placeable:
		return (_ghost as Placeable).footprint_cells(anchor_cell)
	return [anchor_cell]


func _selected_allows_belt_overlap() -> bool:
	return _ghost is Placeable and (_ghost as Placeable).allow_belt_overlap


func _is_belt_placeable(placeable: Placeable) -> bool:
	if placeable == null:
		return false
	for child in placeable.get_children():
		if child is Belt:
			return true
	return false


func _is_blocked(pos: Vector2) -> bool:
	var cell: Vector2i = _world_to_cell(pos)
	var pg := get_node_or_null("/root/PowerGrid")
	var exact_anchor_placeable := _get_placeable_anchor_at_cell(cell)

	# Miners can only be placed on Mineable areas
	if _selected_is_miner:
		if not _is_over_mineable(pos):
			return true

	if _selected_is_pipe:
		# Pipes: blocked if a pipe already exists at this cell
		if pg != null and pg.has_pipe_at(cell):
			return true
		if _footprint_has_blocking_placeable(cell, null):
			return true
	else:
		# Machines need electrical support. If the pipe is missing, place one automatically.
		if pg == null:
			return true
		if pg.has_machine_at(cell):
			var machine_at_anchor = pg._machines.get(cell, null)
			if not (_selected_allows_belt_overlap() and machine_at_anchor is Placeable and _is_belt_placeable(machine_at_anchor as Placeable)):
				return true
		var has_pipe: bool = pg.has_pipe_at(cell)
		if not has_pipe and _get_electrical_pipe_scene() == null:
			return true
		var allowed_pipes: Array = _support_pipes_for_machine(cell)
		if exact_anchor_placeable != null and not allowed_pipes.has(exact_anchor_placeable) and not (_selected_allows_belt_overlap() and _is_belt_placeable(exact_anchor_placeable)):
			return true
		if _footprint_has_blocking_placeable(cell, null, allowed_pipes):
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
		var hit_placeable: Placeable = _find_placeable_ancestor(collider)
		if hit_placeable == null:
			continue
		if _selected_allows_belt_overlap() and _is_belt_placeable(hit_placeable):
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
			var placeable: Placeable = _find_placeable_ancestor(collider)
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


func _connect_hotbar() -> void:
	if hotbar_ui_path != NodePath(""):
		_hotbar_ui = get_node_or_null(hotbar_ui_path) as HotbarUI
	if _hotbar_ui == null:
		var current_scene: Node = get_tree().current_scene
		if current_scene != null:
			_hotbar_ui = current_scene.find_child("HotbarUI", true, false) as HotbarUI
	if _hotbar_ui == null:
		_hotbar_ui = get_tree().root.find_child("HotbarUI", true, false) as HotbarUI
	if _hotbar_ui == null:
		return
	var selection_callable: Callable = Callable(self, "_on_hotbar_selection_changed")
	if not _hotbar_ui.hotbar_selection_changed.is_connected(selection_callable):
		_hotbar_ui.hotbar_selection_changed.connect(selection_callable)
	_on_hotbar_selection_changed(_hotbar_ui.selected_index, _hotbar_ui.get_selected_slot())


func _add_placeable_scenes_to_inventory() -> void:
	if not add_placeables_to_inventory_on_start or _inventory_holder == null:
		return
	for scene in placeable_scenes:
		if scene == null:
			continue
		var scene_path: String = scene.resource_path
		var item_type: String = _item_name_for_scene(scene)
		if item_type == "":
			continue
		if _inventory_holder.has_item(item_type, scene_path):
			continue
		var texture: Texture2D = _texture_for_scene(scene)
		var icon_path: String = _icon_path_for_texture(texture)
		_inventory_holder.add_item(item_type, starting_placeable_stack_size, texture, scene_path, icon_path)


func _on_hotbar_selection_changed(index: int, slot: Dictionary) -> void:
	_selected_inventory_slot_index = index
	_selected_inventory_label = String(slot.get("type", ""))
	if slot.is_empty():
		_select_inventory_scene(null, index, "")
		return
	var scene_path: String = String(slot.get("scene_path", ""))
	if scene_path.strip_edges() == "":
		_select_inventory_scene(null, index, _selected_inventory_label)
		return
	var resource: Resource = load(scene_path)
	if resource is PackedScene:
		_select_inventory_scene(resource as PackedScene, index, _selected_inventory_label)
	else:
		_select_inventory_scene(null, index, _selected_inventory_label)


func _select_hotbar_or_placeable(index: int) -> void:
	if _hotbar_ui != null:
		_hotbar_ui.select_slot(index)
		return
	_select_index(index)


func _select_inventory_scene(scene: PackedScene, slot_index: int, label: String) -> void:
	_left_held = false
	_last_place_cell = Vector2i(2147483647, 2147483647)
	_selected_inventory_slot_index = slot_index
	_selected_inventory_label = label
	selected_scene = scene
	if selected_scene == null:
		show_grid = false
		_update_item_label()
		_clear_ghost()
		return
	_cache_scene_properties()
	show_grid = true
	_update_item_label()
	_clear_ghost()


func _select_index(index: int) -> void:
	_left_held = false
	_last_place_cell = Vector2i(2147483647, 2147483647)
	_selected_inventory_slot_index = -1
	_selected_inventory_label = ""

	if index < 0:
		_selected_index = -1
		selected_scene = null
		show_grid = false
		_update_item_label()
		_clear_ghost()
		return

	if index >= placeable_scenes.size():
		return

	_selected_index = index
	selected_scene = placeable_scenes[index]
	_cache_scene_properties()
	show_grid = selected_scene != null
	_update_item_label()
	_clear_ghost()


func _cache_scene_properties() -> void:
	_selected_is_pipe = false
	_selected_is_miner = false
	_selected_ignore_pipe_dir = false
	if selected_scene == null:
		return
	var temp := selected_scene.instantiate()
	if temp is Placeable:
		_selected_is_pipe = (temp as Placeable).is_pipe
		_selected_is_miner = (temp as Placeable).is_miner
		_selected_ignore_pipe_dir = (temp as Placeable).ignore_pipe_direction
	temp.free()


func _update_item_label() -> void:
	if _item_label_ref == null:
		return

	if selected_scene == null:
		if _selected_inventory_label.strip_edges() != "":
			_item_label_ref.text = "Item: %s" % _selected_inventory_label
		else:
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
		_apply_direction_to_node(_ghost, _current_direction)


func _toggle_pipe_cross() -> void:
	if _ghost == null or not (_ghost is ElectricalPipe):
		return
	var pipe := _ghost as ElectricalPipe
	pipe.force_cross = true
	pipe.apply_direction_animation()


func _rotate_hovered_placeable() -> bool:
	var target: Placeable = _find_placeable_at_mouse()
	if target == null or not is_instance_valid(target) or target.ghost_mode:
		return false
	if target.is_pipe:
		return true
	var next_direction: int = _next_direction(target.direction)
	var cell: Vector2i = target.cell
	var pg: Node = get_node_or_null("/root/PowerGrid")
	_apply_direction_to_placeable(target, next_direction)
	if pg != null:
		var pipe: Node = pg.get_pipe_at(cell) as Node
		if pipe != null and pipe is ElectricalPipe:
			_adapt_pipe_for_machine_direction(cell, next_direction, target.ignore_pipe_direction)
		pg.mark_dirty()
	return true


func _directions_share_axis(a: int, b: int) -> bool:
	var a_horizontal: bool = a in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]
	var b_horizontal: bool = b in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]
	return a_horizontal == b_horizontal


func _pipe_has_perpendicular_neighbor(pipe: ElectricalPipe) -> bool:
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return false
	if pipe.direction in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]:
		for offset in [Vector2i(0, -2), Vector2i(0, 2)]:
			var neighbor = pg.get_pipe_at(pipe.cell + offset)
			if neighbor != null and neighbor is ElectricalPipe:
				var neighbor_pipe := neighbor as ElectricalPipe
				if neighbor_pipe.force_cross or neighbor_pipe.direction in [Placeable.Dir.UP, Placeable.Dir.DOWN]:
					return true
	else:
		for offset in [Vector2i(-3, 0), Vector2i(3, 0)]:
			var neighbor = pg.get_pipe_at(pipe.cell + offset)
			if neighbor != null and neighbor is ElectricalPipe:
				var neighbor_pipe := neighbor as ElectricalPipe
				if neighbor_pipe.force_cross or neighbor_pipe.direction in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]:
					return true
	return false


func _next_direction(direction: int) -> int:
	var order: Array[int] = [Placeable.Dir.UP, Placeable.Dir.RIGHT, Placeable.Dir.DOWN, Placeable.Dir.LEFT]
	var idx: int = order.find(direction)
	if idx < 0:
		return Placeable.Dir.RIGHT
	return order[(idx + 1) % order.size()]


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


func _apply_direction_to_node(node: Node, direction: int) -> void:
	if node is Placeable:
		_apply_direction_to_placeable(node as Placeable, direction)
	else:
		_set_animation_recursive(node, direction)


func _apply_direction_to_placeable(placeable: Placeable, direction: int) -> void:
	placeable.direction = direction
	placeable.apply_direction_animation()


func _refresh_hover() -> void:
	var hovered: Placeable = _find_placeable_at_mouse()
	if hovered == _hovered_placeable:
		_update_hover_direction_indicator(hovered)
		_update_hover_label(hovered)
		return
	if _hovered_placeable != null and is_instance_valid(_hovered_placeable):
		_hide_hover_direction_for(_hovered_placeable)
		if _hovered_placeable.power_state_changed.is_connected(_on_hovered_power_changed):
			_hovered_placeable.power_state_changed.disconnect(_on_hovered_power_changed)
	_hovered_placeable = hovered
	if _hovered_placeable != null:
		if not _hovered_placeable.power_state_changed.is_connected(_on_hovered_power_changed):
			_hovered_placeable.power_state_changed.connect(_on_hovered_power_changed)
	_update_hover_direction_indicator(_hovered_placeable)
	_update_hover_label(_hovered_placeable)


func _find_placeable_at_mouse() -> Placeable:
	var mouse_pos: Vector2 = get_global_mouse_position()
	var mouse_cell: Vector2i = _world_to_cell(mouse_pos)
	return _get_placeable_at_footprint_cell(mouse_cell)


func _on_hovered_power_changed(_is_powered: bool) -> void:
	if _hovered_placeable != null and is_instance_valid(_hovered_placeable):
		_update_hover_direction_indicator(_hovered_placeable)
		_update_hover_label(_hovered_placeable)


func _update_hover_label(_p: Placeable) -> void:
	if _hover_label_ref == null:
		return
	var hover_cell: Vector2i = _world_to_cell(get_global_mouse_position())
	_hover_label_ref.text = "Cell: (%d, %d)" % [hover_cell.x, hover_cell.y]


func _update_hover_direction_indicator(target: Placeable) -> void:
	if not hover_direction_enabled or target == null or not is_instance_valid(target) or target.ghost_mode:
		return
	_hide_hover_direction_for(target)
	var visible_sprite := _find_visible_animated_sprite(target)
	if visible_sprite == null:
		return
	var hover_node := visible_sprite.get_node_or_null(NodePath(String(hover_rect_node_name))) as CanvasItem
	if hover_node != null:
		hover_node.visible = true
	var arrow_node := visible_sprite.get_node_or_null(NodePath(String(hover_arrow_node_name))) as CanvasItem
	if arrow_node != null:
		arrow_node.visible = true


func _hide_hover_direction_for(target: Placeable) -> void:
	if target == null or not is_instance_valid(target):
		return
	for sprite in _find_animated_sprites(target):
		var hover_node := sprite.get_node_or_null(NodePath(String(hover_rect_node_name))) as CanvasItem
		if hover_node != null:
			hover_node.visible = false
		var arrow_node := sprite.get_node_or_null(NodePath(String(hover_arrow_node_name))) as CanvasItem
		if arrow_node != null:
			arrow_node.visible = false


func _find_visible_animated_sprite(node: Node) -> AnimatedSprite2D:
	for sprite in _find_animated_sprites(node):
		if sprite.visible:
			return sprite
	return null


func _find_animated_sprites(node: Node) -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	if node is AnimatedSprite2D:
		sprites.append(node as AnimatedSprite2D)
	for child in node.get_children():
		sprites.append_array(_find_animated_sprites(child))
	return sprites


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
