class_name HotbarUI
extends Control

signal hotbar_slot_clicked(index: int, slot: Dictionary)
signal hotbar_selection_changed(index: int, slot: Dictionary)
signal hotbar_slot_hovered(index: int, slot: Dictionary)
signal hotbar_slot_unhovered(index: int)

@export var slot_count: int = 6
@export var inventory_holder_path: NodePath

var inventory: Inventory
var selected_index: int = -1
var _grid: GridContainer
var _slot_nodes: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	_grid = get_node_or_null("Grid") as GridContainer
	var holder: InventoryHolder = null
	if inventory_holder_path != NodePath(""):
		holder = get_node_or_null(inventory_holder_path) as InventoryHolder
	if holder == null:
		holder = _find_hotbar_inventory_holder()
	if holder != null:
		_bind_inventory(holder.get_inventory())
	elif inventory == null:
		inventory = Inventory.new(slot_count, Inventory.DEFAULT_STACK_SIZE)
	_rebuild_slots()
	_refresh()


func set_inventory(next_inventory: Inventory) -> void:
	_bind_inventory(next_inventory)
	_refresh()


func get_inventory() -> Inventory:
	return inventory


func is_mouse_over_slot() -> bool:
	if not visible:
		return false
	var mouse_position: Vector2 = get_global_mouse_position()
	for slot_button in _slot_nodes:
		if slot_button != null and slot_button.visible and slot_button.get_global_rect().has_point(mouse_position):
			return true
	return false


func get_selected_slot() -> Dictionary:
	return _slot_at(selected_index)


func select_slot(index: int) -> void:
	selected_index = int(clamp(index, 0, max(0, slot_count - 1)))
	_update_selected_visual()
	hotbar_selection_changed.emit(selected_index, _slot_at(selected_index))


func deselect_slot() -> void:
	selected_index = -1
	_update_selected_visual()
	hotbar_selection_changed.emit(selected_index, {})


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var index: int = _hotbar_index_for_key(event.keycode)
		if index >= 0 and index < slot_count:
			if selected_index == index:
				deselect_slot()
			else:
				select_slot(index)
			get_viewport().set_input_as_handled()


func _bind_inventory(next_inventory: Inventory) -> void:
	var refresh_callable: Callable = Callable(self, "_refresh")
	if inventory != null and inventory.is_connected(&"inventory_changed", refresh_callable):
		inventory.disconnect(&"inventory_changed", refresh_callable)
	inventory = next_inventory
	if inventory != null and not inventory.is_connected(&"inventory_changed", refresh_callable):
		inventory.connect(&"inventory_changed", refresh_callable)


func _find_hotbar_inventory_holder() -> InventoryHolder:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var holder: InventoryHolder = current_scene.find_child("HotbarInventory", true, false) as InventoryHolder
		if holder != null:
			return holder
	return get_tree().root.find_child("HotbarInventory", true, false) as InventoryHolder


func _rebuild_slots() -> void:
	_slot_nodes.clear()
	if _grid == null:
		push_warning("HotbarUI needs a Grid child.")
		return
	if _collect_existing_slots():
		_update_selected_visual()
		return
	var template: Button = _grid.get_node_or_null("SlotTemplate") as Button
	if template != null:
		template.visible = false
	push_warning("HotbarUI uses scene-authored slots. Add Slot0, Slot1, ... under Grid.")


func _collect_existing_slots() -> bool:
	for child in _grid.get_children():
		if child is Button and child.name.begins_with("Slot") and child.name != "SlotTemplate":
			var slot_button: Button = child as Button
			slot_button.mouse_filter = Control.MOUSE_FILTER_STOP
			var slot_index: int = _slot_index_from_name(slot_button.name)
			if slot_index < 0:
				slot_index = _slot_nodes.size()
			var slot_callable: Callable = Callable(self, "_on_slot_pressed").bind(slot_index)
			if not slot_button.pressed.is_connected(slot_callable):
				slot_button.pressed.connect(slot_callable)
			var hover_callable: Callable = Callable(self, "_on_slot_hovered").bind(slot_index)
			if not slot_button.mouse_entered.is_connected(hover_callable):
				slot_button.mouse_entered.connect(hover_callable)
			var unhover_callable: Callable = Callable(self, "_on_slot_unhovered").bind(slot_index)
			if not slot_button.mouse_exited.is_connected(unhover_callable):
				slot_button.mouse_exited.connect(unhover_callable)
			_slot_nodes.append(slot_button)
	return not _slot_nodes.is_empty()


func _slot_index_from_name(slot_name: String) -> int:
	var digits: String = ""
	for i in range(slot_name.length()):
		var character: String = slot_name.substr(i, 1)
		if character.is_valid_int():
			digits += character
	if digits == "":
		return -1
	return int(digits)


func _refresh() -> void:
	if inventory == null:
		return
	if _slot_nodes.size() != slot_count:
		_rebuild_slots()
	var slots: Array[Dictionary] = inventory.get_slots()
	for i in range(_slot_nodes.size()):
		var slot: Dictionary = {}
		if i < slots.size():
			slot = slots[i] as Dictionary
		var slot_button: Button = _slot_nodes[i]
		var icon: TextureRect = slot_button.get_node_or_null("Icon") as TextureRect
		var amount_label: Label = slot_button.get_node_or_null("Amount") as Label
		if slot.is_empty():
			if icon != null:
				icon.texture = null
			if amount_label != null:
				amount_label.text = ""
			continue
		if icon != null:
			icon.texture = _texture_for_slot(slot)
		if amount_label != null:
			amount_label.text = str(int(slot.get("amount", 0)))
	_update_selected_visual()
	hotbar_selection_changed.emit(selected_index, _slot_at(selected_index))


func _update_selected_visual() -> void:
	for i in range(_slot_nodes.size()):
		var selected_marker: CanvasItem = _slot_nodes[i].get_node_or_null("Selected") as CanvasItem
		if selected_marker != null:
			selected_marker.visible = i == selected_index


func _on_slot_pressed(index: int) -> void:
	var slot: Dictionary = _slot_at(index)
	DebugConsole.log("Hotbar slot %d: %s" % [index, _debug_slot_text(slot)])
	hotbar_slot_clicked.emit(index, slot)


func _on_slot_hovered(index: int) -> void:
	hotbar_slot_hovered.emit(index, _slot_at(index))


func _on_slot_unhovered(index: int) -> void:
	hotbar_slot_unhovered.emit(index)


func _texture_for_slot(slot: Dictionary) -> Texture2D:
	var texture: Texture2D = slot.get("texture", null) as Texture2D
	if texture != null:
		return texture
	var icon_path: String = String(slot.get("icon_path", ""))
	if icon_path.strip_edges() != "":
		var icon: Resource = load(icon_path)
		if icon is Texture2D:
			return icon as Texture2D
	var scene_path: String = String(slot.get("scene_path", ""))
	if scene_path.strip_edges() != "":
		var scene_texture: Texture2D = _texture_for_scene_path(scene_path)
		if scene_texture != null:
			return scene_texture
	return Belt.get_ore_texture(String(slot.get("type", "")))


func _debug_slot_text(slot: Dictionary) -> String:
	if slot.is_empty():
		return "EMPTY"
	return "type=%s amount=%d scene_path=%s icon_path=%s has_texture=%s" % [
		String(slot.get("type", "")),
		int(slot.get("amount", 0)),
		String(slot.get("scene_path", "")),
		String(slot.get("icon_path", "")),
		str(slot.get("texture", null) != null),
	]


func _texture_for_scene_path(scene_path: String) -> Texture2D:
	var resource: Resource = load(scene_path)
	if not resource is PackedScene:
		return null
	var scene: PackedScene = resource as PackedScene
	var instance: Node = scene.instantiate()
	var texture: Texture2D = _texture_for_node(instance)
	instance.free()
	return texture


func _texture_for_node(node: Node) -> Texture2D:
	if node is Sprite2D:
		var sprite_2d: Sprite2D = node as Sprite2D
		if sprite_2d.texture != null:
			return sprite_2d.texture
	if node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(sprite.animation):
			return sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		var texture: Texture2D = _texture_for_node(child)
		if texture != null:
			return texture
	return null


func _slot_at(index: int) -> Dictionary:
	if inventory == null:
		return {}
	if index < 0 or index >= inventory.get_slots().size():
		return {}
	return inventory.get_slot(index)


func _hotbar_index_for_key(keycode: int) -> int:
	for i in range(6):
		if keycode == GameSettings.get_key("hotbar_%d" % (i + 1)):
			return i
	return -1
