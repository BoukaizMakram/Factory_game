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
@export var electrical_place_sound: AudioStream = preload("res://SFX/raw/electrical placement.wav")
@export var removal_inventory_sound: AudioStream = preload("res://SFX/raw/inventory.wav")
@export var debug_placement: bool = true
@export var remove_hold_seconds_per_object: float = 0.2
@export var inventory_added_text_seconds: float = 1.0
@export_group("Hover Direction")
@export var hover_direction_enabled: bool = true
@export var hover_rect_node_name: StringName = &"Hover"
@export var hover_arrow_node_name: StringName = &"Arrow"

var _ghost: Node2D
var _ghost_shape: CollisionShape2D
var _placed: Array[Node2D] = []
var _left_held: bool = false
var _right_held: bool = false
var _right_hold_elapsed: float = 0.0
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
var _selected_allow_belt_overlap: bool = false
var _selected_footprint_width_cells: int = 1
var _selected_footprint_height_cells: int = 1
var _pipe_inspect_active: bool = false
var _inventory_holder: InventoryHolder
var _hotbar_ui: HotbarUI
var _selected_inventory_ref: Inventory
var _selected_inventory_slot_index: int = -1
var _selected_inventory_label: String = ""
var _ui_blocks_placement: bool = false
var _inventory_added_text: String = ""
var _inventory_added_text_timer: float = 0.0


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
	call_deferred("_disable_existing_placeable_mouse_controls")

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


func _process(delta: float) -> void:
	queue_redraw()
	if _inventory_added_text_timer > 0.0:
		_inventory_added_text_timer = maxf(0.0, _inventory_added_text_timer - delta)

	# Right-click hold deletes continuously, works even with no selection
	if _right_held:
		if _has_removable_at_mouse():
			_right_hold_elapsed += delta
			var remove_interval: float = maxf(0.01, remove_hold_seconds_per_object)
			if _right_hold_elapsed >= remove_interval:
				_right_hold_elapsed = 0.0
				_try_remove_at_mouse()
		else:
			_right_hold_elapsed = 0.0

	_refresh_hover()

	if selected_scene == null:
		_left_held = false
		_last_place_cell = Vector2i(2147483647, 2147483647)
		_clear_ghost()
		return

	if _ui_blocks_placement:
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

	_sync_left_hold_state()
	if _left_held:
		_try_place_at_mouse()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_debug_place("input left mouse down")
				if selected_scene != null and not _ui_blocks_placement:
					_left_held = true
					_try_place_at_mouse()
			else:
				_left_held = false
				_last_place_cell = Vector2i(2147483647, 2147483647)
		elif event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
			_right_held = false
			_right_hold_elapsed = 0.0
			_last_remove_cell = Vector2i(2147483647, 2147483647)
	elif event is InputEventKey:
		if event.keycode == GameSettings.get_key("placer_inspect"):
			_set_pipe_inspect(event.pressed)


func _sync_left_hold_state() -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_left_held = true
	else:
		_left_held = false
		_last_place_cell = Vector2i(2147483647, 2147483647)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and selected_scene and not _ui_blocks_placement:
			_debug_place("unhandled left mouse down")
			if not _left_held:
				_left_held = true
				_try_place_at_mouse()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_right_held = true
			_right_hold_elapsed = 0.0
			_last_remove_cell = Vector2i(2147483647, 2147483647)
	elif event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc == GameSettings.get_key("placer_cancel"):
			if selected_scene == null and not select_hovered_placeable_from_inventory():
				_select_index(-1)
			elif selected_scene != null:
				_select_index(-1)
			get_viewport().set_input_as_handled()
		elif kc == GameSettings.get_key("placer_rotate"):
			if selected_scene != null:
				if not _selected_is_pipe:
					_cycle_direction()
			elif not _rotate_hovered_placeable():
				_cycle_direction()
		elif kc == GameSettings.get_key("placer_pipe_cross"):
			_toggle_pipe_cross()
		elif kc == GameSettings.get_key("placer_toggle_grid"):
			show_grid = not show_grid
		else:
			var hotbar_index: int = _placer_hotbar_index_for_key(kc)
			if hotbar_index >= 0:
				if not _pick_hovered_into_hotbar(hotbar_index):
					_select_hotbar_or_placeable(hotbar_index)
				get_viewport().set_input_as_handled()


func _placer_hotbar_index_for_key(keycode: int) -> int:
	for i in range(6):
		if keycode == GameSettings.get_key("hotbar_%d" % (i + 1)):
			return i
	return -1


func has_active_selection() -> bool:
	return selected_scene != null


func _pick_hovered_into_hotbar(index: int) -> bool:
	if _hovered_placeable == null or not is_instance_valid(_hovered_placeable):
		return false
	if _hotbar_ui == null:
		return false
	var hotbar_inventory: Inventory = _hotbar_ui.get_inventory()
	if hotbar_inventory == null:
		return false
	var scene_path: String = _scene_path_for_placeable(_hovered_placeable)
	if scene_path.strip_edges() == "":
		return false
	var item_type: String = _hovered_placeable.item_name.strip_edges()
	if item_type == "":
		item_type = _hovered_placeable.name.strip_edges()
	if item_type == "":
		item_type = "Placeable"
	var texture: Texture2D = _texture_for_node(_hovered_placeable)
	var icon_path: String = _icon_path_for_texture(texture)
	hotbar_inventory.set_slot(index, item_type, starting_placeable_stack_size, texture, scene_path, icon_path)
	_hotbar_ui.select_slot(index)
	return true


func select_hovered_placeable_from_inventory() -> bool:
	var target: Placeable = _hovered_placeable
	if target == null or not is_instance_valid(target) or target.ghost_mode:
		target = _find_placeable_at_mouse()
	if target == null or not is_instance_valid(target) or target.ghost_mode:
		return false
	var scene_path: String = _scene_path_for_placeable(target)
	if scene_path.strip_edges() == "":
		return false

	_connect_hotbar()
	if _hotbar_ui != null:
		var hotbar_inventory: Inventory = _hotbar_ui.get_inventory()
		var hotbar_index: int = _find_inventory_slot_with_scene(hotbar_inventory, scene_path)
		if hotbar_index >= 0:
			_hotbar_ui.select_slot(hotbar_index)
			_notify_ui_cursor_selection(hotbar_inventory, hotbar_index)
			return true

	_resolve_inventory_holder()
	if _inventory_holder == null:
		return false
	var inventory: Inventory = _inventory_holder.get_inventory()
	var inventory_index: int = _find_inventory_slot_with_scene(inventory, scene_path)
	if inventory_index < 0:
		DebugConsole.log("Pipette failed: %s is not in inventory." % target.item_name)
		return false
	select_inventory_slot_for_placement(inventory, inventory_index, inventory.get_slot(inventory_index))
	_notify_ui_cursor_selection(inventory, inventory_index)
	return true


func _find_inventory_slot_with_scene(inventory: Inventory, scene_path: String) -> int:
	if inventory == null or scene_path.strip_edges() == "":
		return -1
	var slots: Array[Dictionary] = inventory.get_slots()
	for i in range(slots.size()):
		var slot: Dictionary = slots[i] as Dictionary
		if slot.is_empty():
			continue
		if String(slot.get("scene_path", "")) == scene_path and int(slot.get("amount", 0)) > 0:
			return i
	return -1


func _notify_ui_cursor_selection(inventory: Inventory, index: int) -> void:
	var ui_node: Node = null
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		ui_node = current_scene.find_child("UI", true, false)
	if ui_node == null:
		ui_node = get_tree().root.find_child("UI", true, false)
	if ui_node != null and ui_node.has_method("select_inventory_slot_for_cursor"):
		ui_node.call("select_inventory_slot_for_cursor", inventory, index)


func _draw() -> void:
	_draw_remove_hold_progress()
	_draw_inventory_added_text()
	if not show_grid or _ui_blocks_placement:
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


func _draw_remove_hold_progress() -> void:
	if not _right_held or not _has_removable_at_mouse():
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	var zoom_scale: float = 1.0 / (cam.zoom.x if cam else 1.0)
	var interval: float = maxf(0.01, remove_hold_seconds_per_object)
	var progress: float = clampf(_right_hold_elapsed / interval, 0.0, 1.0)
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	var size: Vector2 = Vector2(48.0, 7.0) * zoom_scale
	var offset: Vector2 = Vector2(16.0, 20.0) * zoom_scale
	var rect: Rect2 = Rect2(mouse_local + offset, size)
	var fill_rect: Rect2 = Rect2(rect.position, Vector2(rect.size.x * progress, rect.size.y))
	draw_rect(rect, Color(0.02, 0.02, 0.025, 0.8), true)
	draw_rect(fill_rect, Color(1.0, 0.25, 0.18, 0.95), true)
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.85), false, maxf(1.0, zoom_scale))


func _draw_inventory_added_text() -> void:
	if _inventory_added_text_timer <= 0.0 or _inventory_added_text.strip_edges() == "":
		return
	var theme_font: Font = ThemeDB.fallback_font
	if theme_font == null:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	var zoom_scale: float = 1.0 / (cam.zoom.x if cam else 1.0)
	var font_size: int = max(10, int(round(15.0 * zoom_scale)))
	var alpha: float = clampf(_inventory_added_text_timer / maxf(0.01, inventory_added_text_seconds), 0.0, 1.0)
	var text: String = "+ %s" % _inventory_added_text
	var text_size: Vector2 = theme_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var mouse_local: Vector2 = to_local(get_global_mouse_position())
	var offset: Vector2 = Vector2(16.0, -18.0) * zoom_scale
	var pos: Vector2 = mouse_local + offset
	var padding: Vector2 = Vector2(7.0, 5.0) * zoom_scale
	var bg_rect: Rect2 = Rect2(pos + Vector2(-padding.x, -text_size.y - padding.y), text_size + padding * 2.0)
	draw_rect(bg_rect, Color(0.02, 0.02, 0.025, 0.75 * alpha), true)
	draw_string(theme_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(1.0, 1.0, 1.0, alpha))


func _spawn_ghost() -> void:
	_ghost = selected_scene.instantiate()
	if _ghost is Placeable:
		var p: Placeable = _ghost as Placeable
		_current_direction = p.normalize_direction_for_available(_current_direction)
		p.ghost_mode = true
		if p is ElectricalPipe:
			(p as ElectricalPipe).force_cross = true
		_apply_direction_to_placeable(p, _current_direction)
	_disable_physics(_ghost)
	_disable_mouse_input_controls(_ghost)
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


func _disable_mouse_input_controls(node: Node) -> void:
	if node is Control:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_disable_mouse_input_controls(child)


func _disable_existing_placeable_mouse_controls() -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return
	_disable_placeable_mouse_controls_recursive(current_scene)


func _disable_placeable_mouse_controls_recursive(node: Node) -> void:
	if node is Placeable:
		_disable_mouse_input_controls(node)
	for child in node.get_children():
		_disable_placeable_mouse_controls_recursive(child)


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
	_disable_mouse_input_controls(obj)
	parent.add_child(obj)
	_apply_direction_to_node(obj, _current_direction)
	obj.global_position = pos
	obj.y_sort_enabled = true
	_apply_display_scale(obj)
	_placed.append(obj)
	_play_place_sound(pos, obj)


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
	var pipe: Node = pg.get_pipe_at(cell) as Node
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
			var existing_pipe: Node = pg.get_pipe_at(support_cell) as Node
			if existing_pipe != null and existing_pipe is ElectricalPipe:
				_adapt_pipe_for_machine_direction(support_cell, _current_direction, true)
	if pg != null:
		pg.mark_dirty()
	_play_place_sound(_cell_to_world(cell), existing)
	return true


func _can_update_same_object_at_cell(cell: Vector2i) -> bool:
	if _selected_is_pipe:
		return false
	var existing := _get_same_object_at_anchor_cell(cell)
	return existing != null and _same_object_needs_direction_update(existing, cell)


func _same_object_needs_direction_update(existing: Placeable, cell: Vector2i) -> bool:
	if existing.direction != _current_direction:
		return true
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null or existing is ElectricalPipe:
		return false
	var pipe: Node = pg.get_pipe_at(cell) as Node
	if pipe == null or not (pipe is ElectricalPipe):
		return false
	var electrical_pipe := pipe as ElectricalPipe
	if electrical_pipe.force_cross:
		return false
	if not _directions_share_axis(electrical_pipe.direction, _current_direction):
		return true
	return electrical_pipe.direction != _current_direction


func _get_same_object_at_anchor_cell(cell: Vector2i) -> Placeable:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return null
	var existing: Placeable = null
	if _selected_is_pipe:
		var pipe: Node = pg.get_pipe_at(cell) as Node
		if pipe != null and pipe is Placeable:
			existing = pipe as Placeable
	elif pg.has_machine_at(cell):
		var machine: Placeable = pg._machines.get(cell, null) as Placeable
		if machine != null:
			existing = machine
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


func _play_place_sound(at_position: Vector2 = Vector2.INF, placed_node: Node = null) -> void:
	var sound: AudioStream = _placement_sound_for(placed_node)
	if sound == null:
		return
	var world_pos: Vector2 = at_position if at_position != Vector2.INF else _mouse_world_position()
	var sfx := SFX.play_oneshot_2d(self, sound, world_pos, 0.0)
	if sfx != null:
		sfx.bus = &"Master"


func _placement_sound_for(placed_node: Node) -> AudioStream:
	if _uses_electrical_place_sound(placed_node) and electrical_place_sound != null:
		return electrical_place_sound
	return place_sound


func _uses_electrical_place_sound(placed_node: Node) -> bool:
	if placed_node == null:
		return false
	if placed_node is ElectricalPipe:
		return true
	var placeable: Placeable = placed_node as Placeable
	if placeable == null:
		return false
	var item_name_lower: String = placeable.item_name.to_lower()
	var node_name_lower: String = placeable.name.to_lower()
	return item_name_lower.contains("solar") or node_name_lower.contains("solar")


func _mouse_world_position() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	var camera: Camera2D = viewport.get_camera_2d()
	if camera == null:
		return viewport.get_mouse_position()
	return camera.get_global_mouse_position()


func _try_place_at_mouse() -> void:
	if selected_scene == null:
		_debug_place("place skipped: no selected scene")
		return
	if _ui_blocks_placement:
		_debug_place("place skipped: UI slot blocks placement")
		return
	if _selected_inventory_slot_index >= 0 and not _selected_inventory_has_placeable():
		_debug_place("place skipped: selected inventory slot has no placeable scene")
		return
	if _ghost == null:
		_spawn_ghost()

	var cell: Vector2i = _current_placement_cell()
	if cell == _last_place_cell:
		_debug_place("place skipped: same held cell")
		return

	var pos: Vector2 = _cell_to_world(cell)
	if _update_same_object_at_cell(cell):
		_debug_place("place updated same object")
		_last_place_cell = cell
		return
	if _is_blocked(pos):
		_debug_place("place blocked: %s" % _placement_block_reason(pos))
		return

	if _selected_allows_belt_overlap():
		_remove_belts_in_selected_footprint(cell)
	_place(pos)
	_consume_selected_inventory_item()
	_last_place_cell = cell
	_debug_place("place success")


func _current_placement_cell() -> Vector2i:
	if _ghost != null and is_instance_valid(_ghost):
		return _world_to_cell(_ghost.global_position)
	return _world_to_cell(get_global_mouse_position())


func _debug_place(message: String) -> void:
	if not debug_placement:
		return
	var mouse_cell: Vector2i = _world_to_cell(get_global_mouse_position())
	var ghost_cell: Vector2i = Vector2i(2147483647, 2147483647)
	if _ghost != null and is_instance_valid(_ghost):
		ghost_cell = _world_to_cell(_ghost.global_position)
	var selected_name: String = "None"
	if selected_scene != null:
		selected_name = _get_scene_display_name(selected_scene)
	var cells: Array[Vector2i] = _selected_footprint_cells(ghost_cell if ghost_cell.x != 2147483647 else mouse_cell)
	DebugConsole.log("PLACE DEBUG: %s | selected=%s mouse_cell=%s ghost_cell=%s ui_block=%s inv_slot=%d footprint=%s reason=%s" % [
		message,
		selected_name,
		str(mouse_cell),
		str(ghost_cell),
		str(_ui_blocks_placement),
		_selected_inventory_slot_index,
		_format_cells(cells),
		_placement_block_reason(_cell_to_world(ghost_cell if ghost_cell.x != 2147483647 else mouse_cell)),
	])


func _format_cells(cells: Array[Vector2i]) -> String:
	var parts: PackedStringArray = []
	for cell in cells:
		parts.append("(%d,%d)" % [cell.x, cell.y])
	return "[" + ", ".join(parts) + "]"


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


func _try_remove_at_mouse() -> bool:
	var pos: Vector2 = get_global_mouse_position()
	if not _has_removable_at(pos):
		return false
	_last_remove_cell = _world_to_cell(pos)
	return _remove_at(pos)


func _remove_at(pos: Vector2) -> bool:
	var cell: Vector2i = _world_to_cell(pos)
	var placeables: Array[Placeable] = _get_registered_placeables()
	# First pass: remove a machine (non-pipe) at this cell
	for i in range(placeables.size() - 1, -1, -1):
		var node: Placeable = placeables[i]
		if node != null and is_instance_valid(node) and not node.is_pipe:
			if node.footprint_contains_cell(cell):
				if not _add_placeable_to_inventory(node):
					return false
				_forget_and_free_placeable(node)
				return true
	# Second pass: remove a pipe if no machine was found
	for i in range(placeables.size() - 1, -1, -1):
		var node: Placeable = placeables[i]
		if node != null and is_instance_valid(node) and node.footprint_contains_cell(cell):
			if not _add_placeable_to_inventory(node):
				return false
			_forget_and_free_placeable(node)
			return true
	if _remove_loose_item_at(pos):
		return true
	return false


func _has_removable_at_mouse() -> bool:
	return _has_removable_at(get_global_mouse_position())


func _has_removable_at(pos: Vector2) -> bool:
	if _ui_blocks_placement:
		return false
	var cell: Vector2i = _world_to_cell(pos)
	for placeable in _get_registered_placeables():
		if placeable != null and is_instance_valid(placeable) and placeable.footprint_contains_cell(cell):
			return true
	return _find_loose_item_at(pos) != null


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
	if _selected_inventory_slot_index < 0:
		return false
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
	var scene_path: String = ""
	var selected_slot: Dictionary = inventory.get_slot(_selected_inventory_slot_index)
	if not selected_slot.is_empty():
		scene_path = String(selected_slot.get("scene_path", ""))
	inventory.remove_from_slot(_selected_inventory_slot_index, 1)
	var slot: Dictionary = inventory.get_slot(_selected_inventory_slot_index)
	if slot.is_empty():
		if scene_path.strip_edges() == "" or not _select_next_inventory_stack_for_scene(scene_path, inventory):
			_selected_inventory_ref = null
			_select_inventory_scene(null, -1, "")
	else:
		select_inventory_slot_for_placement(inventory, _selected_inventory_slot_index, slot)


func _select_next_inventory_stack_for_scene(scene_path: String, preferred_inventory: Inventory) -> bool:
	if scene_path.strip_edges() == "":
		return false
	if _select_inventory_stack_in_inventory(preferred_inventory, scene_path):
		return true
	_connect_hotbar()
	if _hotbar_ui != null and _select_inventory_stack_in_inventory(_hotbar_ui.get_inventory(), scene_path):
		return true
	_resolve_inventory_holder()
	if _inventory_holder != null and _select_inventory_stack_in_inventory(_inventory_holder.get_inventory(), scene_path):
		return true
	return false


func _select_inventory_stack_in_inventory(inventory: Inventory, scene_path: String) -> bool:
	if inventory == null:
		return false
	var slot_index: int = _find_inventory_slot_with_scene(inventory, scene_path)
	if slot_index < 0:
		return false
	if _hotbar_ui != null and inventory == _hotbar_ui.get_inventory():
		_hotbar_ui.select_slot(slot_index)
	else:
		select_inventory_slot_for_placement(inventory, slot_index, inventory.get_slot(slot_index))
		_notify_ui_cursor_selection(inventory, slot_index)
	return true


func _selected_inventory() -> Inventory:
	if _selected_inventory_ref != null:
		return _selected_inventory_ref
	if _hotbar_ui != null and _hotbar_ui.get_inventory() != null:
		return _hotbar_ui.get_inventory()
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
		DebugConsole.log("Inventory pickup failed: placeable is null.")
		return false
	_resolve_inventory_holder()
	if _inventory_holder == null:
		DebugConsole.log("Inventory pickup failed for %s: inventory_holder_path is not connected." % placeable.name)
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
	DebugConsole.log("Inventory pickup placeable: type=%s remaining=%d scene_path=%s icon_path=%s has_texture=%s" % [
		item_type,
		remaining,
		scene_path,
		icon_path,
		str(texture != null),
	])
	var added: bool = remaining == 0
	if added:
		_show_inventory_added_text(item_type)
		_play_removal_inventory_sound(placeable.global_position)
	return added


func _remove_loose_item_at(pos: Vector2) -> bool:
	var loose_item: Node2D = _find_loose_item_at(pos)
	if loose_item == null:
		DebugConsole.log("Inventory pickup failed: no loose item at mouse.")
		return false
	_resolve_inventory_holder()
	if _inventory_holder == null:
		DebugConsole.log("Inventory pickup failed for %s: inventory_holder_path is not connected." % loose_item.name)
		return false
	var item_type: String = _item_type_for_loose_item(loose_item)
	var texture: Texture2D = _texture_for_node(loose_item)
	var icon_path: String = _icon_path_for_texture(texture)
	var remaining: int = _inventory_holder.add_item(item_type, 1, texture, "", icon_path)
	DebugConsole.log("Inventory pickup loose item: type=%s remaining=%d icon_path=%s has_texture=%s" % [
		item_type,
		remaining,
		icon_path,
		str(texture != null),
	])
	if remaining != 0:
		return false
	loose_item.queue_free()
	_show_inventory_added_text(item_type)
	_play_removal_inventory_sound(pos)
	return true


func _play_removal_inventory_sound(at_position: Vector2) -> void:
	if removal_inventory_sound == null:
		return
	var sfx := SFX.play_oneshot_2d(self, removal_inventory_sound, at_position, 0.0)
	if sfx != null:
		sfx.bus = &"Master"


func _show_inventory_added_text(item_type: String) -> void:
	_inventory_added_text = item_type.strip_edges()
	if _inventory_added_text == "":
		_inventory_added_text = "Item"
	_inventory_added_text_timer = maxf(0.05, inventory_added_text_seconds)


func _find_loose_item_at(pos: Vector2) -> Node2D:
	var cell: Vector2i = _world_to_cell(pos)
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return null
	return _find_loose_item_in_cell(current_scene, cell)


func _find_loose_item_in_cell(node: Node, cell: Vector2i) -> Node2D:
	if node is Node2D and _is_loose_item_candidate(node) and _node_touches_cell(node as Node2D, cell):
		return node as Node2D
	for child in node.get_children():
		var found: Node2D = _find_loose_item_in_cell(child, cell)
		if found != null:
			return found
	return null


func _is_loose_item_candidate(node: Node) -> bool:
	if _find_placeable_ancestor(node) != null:
		return false
	if _has_mineable_marker_in_ancestors(node):
		return false
	return node.name.to_lower().contains("ore")


func _has_mineable_marker_in_ancestors(node: Node) -> bool:
	var current: Node = node
	var current_scene: Node = get_tree().current_scene
	while current != null and current != current_scene:
		if current.find_child("Mineable", true, false) != null:
			return true
		current = current.get_parent()
	return false


func _node_touches_cell(node: Node2D, cell: Vector2i) -> bool:
	if _world_to_cell(node.global_position) == cell:
		return true
	for child in node.get_children():
		if child is Node2D and _node_touches_cell(child as Node2D, cell):
			return true
	return false


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
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return null
	if pg.has_machine_at(cell):
		var machine: Placeable = pg._machines.get(cell, null) as Placeable
		if machine != null and is_instance_valid(machine):
			return machine
	if pg.has_pipe_at(cell):
		var pipe: Placeable = pg.get_pipe_at(cell) as Placeable
		if pipe != null and pipe is Placeable and is_instance_valid(pipe):
			return pipe
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
	if _selected_footprint_height_cells >= 4:
		cells.append(anchor_cell + Vector2i(0, -2))
	return cells


func _support_cells_for_placeable(placeable: Placeable, anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [anchor_cell]
	if placeable != null and placeable.footprint_height() >= 4:
		cells.append(anchor_cell + Vector2i(0, -2))
	return cells


func _support_pipes_for_machine(anchor_cell: Vector2i) -> Array:
	var pipes: Array = []
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return pipes
	for support_cell in _support_cells_for_selected_machine(anchor_cell):
		var pipe: Placeable = pg.get_pipe_at(support_cell) as Placeable
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
	var cells: Array[Vector2i] = []
	var width: int = max(1, _selected_footprint_width_cells)
	var height: int = max(1, _selected_footprint_height_cells)
	var left: int = anchor_cell.x - int(floor(width / 2.0))
	var top: int = anchor_cell.y - (height - 1)
	for y in range(top, top + height):
		for x in range(left, left + width):
			cells.append(Vector2i(x, y))
	return cells


func _selected_allows_belt_overlap() -> bool:
	return _selected_allow_belt_overlap


func _is_belt_placeable(placeable: Placeable) -> bool:
	if placeable == null:
		return false
	for child in placeable.get_children():
		if child is Belt:
			return true
	return false


func _is_blocked(pos: Vector2) -> bool:
	var cell: Vector2i = _world_to_cell(pos)
	var pg: Node = get_node_or_null("/root/PowerGrid")
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
			var machine_at_anchor: Placeable = pg._machines.get(cell, null) as Placeable
			if not (machine_at_anchor != null and _selected_allows_belt_overlap() and _is_belt_placeable(machine_at_anchor)):
				return true
		var has_pipe: bool = pg.has_pipe_at(cell)
		if not has_pipe and _get_electrical_pipe_scene() == null:
			return true
		var allowed_pipes: Array = _support_pipes_for_machine(cell)
		if exact_anchor_placeable != null and not allowed_pipes.has(exact_anchor_placeable) and not (_selected_allows_belt_overlap() and _is_belt_placeable(exact_anchor_placeable)):
			return true
		if _footprint_has_blocking_placeable(cell, null, allowed_pipes):
			return true

	return false


func _placement_block_reason(pos: Vector2) -> String:
	var cell: Vector2i = _world_to_cell(pos)
	var pg: Node = get_node_or_null("/root/PowerGrid")
	var exact_anchor_placeable := _get_placeable_anchor_at_cell(cell)

	if selected_scene == null:
		return "no selected scene"
	if _ui_blocks_placement:
		return "UI slot blocks placement"
	if _selected_inventory_slot_index >= 0 and not _selected_inventory_has_placeable():
		return "inventory slot has no placeable scene"
	if _selected_is_miner and not _is_over_mineable(pos):
		return "miner is not over mineable area"

	if _selected_is_pipe:
		if pg != null and pg.has_pipe_at(cell):
			return "pipe already exists at anchor"
		if _footprint_has_blocking_placeable(cell, null):
			return "pipe footprint intersects placeable"
		return "OK"

	if pg == null:
		return "PowerGrid missing"
	if pg.has_machine_at(cell):
		var machine_at_anchor: Placeable = pg._machines.get(cell, null) as Placeable
		var replacing_belt: bool = machine_at_anchor != null and _selected_allows_belt_overlap() and _is_belt_placeable(machine_at_anchor)
		if not replacing_belt:
			return "machine already exists at anchor"
	var has_pipe: bool = pg.has_pipe_at(cell)
	if not has_pipe and _get_electrical_pipe_scene() == null:
		return "missing electrical pipe scene for auto pipe"
	var allowed_pipes: Array = _support_pipes_for_machine(cell)
	if exact_anchor_placeable != null:
		var anchor_is_allowed_belt: bool = _selected_allows_belt_overlap() and _is_belt_placeable(exact_anchor_placeable)
		if not allowed_pipes.has(exact_anchor_placeable) and not anchor_is_allowed_belt:
			return "anchor has blocking placeable %s" % exact_anchor_placeable.name
	var blocker: Placeable = _first_blocking_placeable(cell, allowed_pipes)
	if blocker != null:
		return "footprint blocked by %s at %s" % [blocker.name, str(blocker.cell)]
	return "OK"


func _first_blocking_placeable(anchor_cell: Vector2i, extra_allowed: Array = []) -> Placeable:
	for placeable in _get_registered_placeables():
		if placeable == null or not is_instance_valid(placeable) or extra_allowed.has(placeable):
			continue
		if _selected_allows_belt_overlap() and _is_belt_placeable(placeable):
			continue
		if _footprints_intersect(_selected_footprint_cells(anchor_cell), placeable):
			return placeable
	return null


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
	var source_inventory: Inventory = null
	if _hotbar_ui != null:
		source_inventory = _hotbar_ui.get_inventory()
	select_inventory_slot_for_placement(source_inventory, index, slot)


func select_inventory_slot_for_placement(source_inventory: Inventory, index: int, slot: Dictionary) -> void:
	_selected_inventory_ref = source_inventory
	_selected_inventory_slot_index = index
	_selected_inventory_label = String(slot.get("type", ""))
	if slot.is_empty():
		_selected_inventory_ref = null
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


func clear_inventory_selection() -> void:
	_selected_inventory_ref = null
	_select_inventory_scene(null, -1, "")


func set_ui_blocks_placement(blocked: bool) -> void:
	_ui_blocks_placement = blocked
	if _ui_blocks_placement:
		_left_held = false
		_last_place_cell = Vector2i(2147483647, 2147483647)
		_clear_ghost()


func _select_hotbar_or_placeable(index: int) -> void:
	if _hotbar_ui != null:
		if _selected_inventory_ref == _hotbar_ui.get_inventory() and _selected_inventory_slot_index == index:
			_hotbar_ui.deselect_slot()
			return
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
	_selected_inventory_ref = null
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
	_selected_allow_belt_overlap = false
	_selected_footprint_width_cells = 1
	_selected_footprint_height_cells = 1
	if selected_scene == null:
		return
	var temp := selected_scene.instantiate()
	if temp is Placeable:
		var temp_placeable: Placeable = temp as Placeable
		_selected_is_pipe = temp_placeable.is_pipe
		_selected_is_miner = temp_placeable.is_miner
		_selected_ignore_pipe_dir = temp_placeable.ignore_pipe_direction
		_selected_allow_belt_overlap = temp_placeable.allow_belt_overlap
		_selected_footprint_width_cells = temp_placeable.footprint_width()
		_selected_footprint_height_cells = temp_placeable.footprint_height()
		_current_direction = temp_placeable.normalize_direction_for_available(_current_direction)
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
		return
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
	var next_direction: int = target.next_available_direction(target.direction)
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
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return false
	if pipe.direction in [Placeable.Dir.LEFT, Placeable.Dir.RIGHT]:
		for offset in [Vector2i(0, -2), Vector2i(0, 2)]:
			var neighbor: Node = pg.get_pipe_at(pipe.cell + offset) as Node
			if neighbor != null and neighbor is ElectricalPipe:
				var neighbor_pipe := neighbor as ElectricalPipe
				if neighbor_pipe.force_cross or neighbor_pipe.direction in [Placeable.Dir.UP, Placeable.Dir.DOWN]:
					return true
	else:
		for offset in [Vector2i(-3, 0), Vector2i(3, 0)]:
			var neighbor: Node = pg.get_pipe_at(pipe.cell + offset) as Node
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
	if _ghost is Placeable:
		return (_ghost as Placeable).available_directions_ordered(order)
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
	placeable.direction = placeable.normalize_direction_for_available(direction)
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
