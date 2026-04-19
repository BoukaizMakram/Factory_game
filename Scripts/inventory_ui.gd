class_name InventoryUI
extends Control

signal slot_clicked(index: int, slot: Dictionary)
signal slot_hovered(index: int, slot: Dictionary)
signal slot_unhovered(index: int)
signal inventory_open_requested

@export var title: String = "INVENTORY"
@export var columns: int = 6
@export var rows: int = 4
@export var slot_size: Vector2 = Vector2(96, 96)
@export var slot_gap: int = 28
@export var max_stack_size: int = 100
@export var close_key: int = KEY_E
@export var seed_preview_items: bool = false
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var placeable_move_sound: AudioStream = preload("res://SFX/raw/metal.mp3")
@export var duck_db: float = -8.0
@export var inventory_holder_path: NodePath

var inventory: Inventory
var _panel: Panel
var _grid: GridContainer
var _title_label: Label
var _close_button: Button
var _slot_nodes: Array[Button] = []
var _selected_slot_index: int = -1
var _hovered_slot_index: int = -1
var _hotbar_ui_ref: HotbarUI


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 2000
	z_as_relative = false
	visible = false
	_build_ui()
	var holder: InventoryHolder = null
	if inventory_holder_path != NodePath(""):
		holder = get_node_or_null(inventory_holder_path) as InventoryHolder
	if holder == null:
		holder = _find_player_inventory_holder()
	if holder != null:
		inventory = holder.get_inventory()
	elif inventory == null:
		inventory = Inventory.new(columns * rows, max_stack_size)
	if seed_preview_items:
		_seed_preview_inventory()
	_bind_inventory(inventory)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == GameSettings.get_key("inventory"):
			toggle()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == GameSettings.get_key("pause"):
			close()
			get_viewport().set_input_as_handled()
			return
		if _hovered_slot_index < 0 or inventory == null:
			return
		var hotbar_index: int = _hotbar_index_for_key(event.keycode)
		if hotbar_index >= 0:
			_assign_hovered_to_hotbar(hotbar_index)
			get_viewport().set_input_as_handled()


func _hotbar_index_for_key(keycode: int) -> int:
	for i in range(6):
		if keycode == GameSettings.get_key("hotbar_%d" % (i + 1)):
			return i
	return -1


func _assign_hovered_to_hotbar(hotbar_index: int) -> void:
	if inventory == null or _hovered_slot_index < 0:
		return
	var slot: Dictionary = inventory.get_slot(_hovered_slot_index).duplicate()
	if slot.is_empty():
		return
	var hotbar: HotbarUI = _find_hotbar_ui()
	if hotbar == null:
		return
	var hotbar_inventory: Inventory = hotbar.get_inventory()
	if hotbar_inventory == null:
		return
	var hotbar_slot: Dictionary = hotbar_inventory.get_slot(hotbar_index).duplicate()
	inventory.set_slot_data(_hovered_slot_index, hotbar_slot)
	hotbar_inventory.set_slot_data(hotbar_index, slot)
	if _slot_is_placeable(slot) or _slot_is_placeable(hotbar_slot):
		_play_sound(placeable_move_sound)


func _find_hotbar_ui() -> HotbarUI:
	if _hotbar_ui_ref != null and is_instance_valid(_hotbar_ui_ref):
		return _hotbar_ui_ref
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		_hotbar_ui_ref = current_scene.find_child("HotbarUI", true, false) as HotbarUI
		if _hotbar_ui_ref != null:
			return _hotbar_ui_ref
	_hotbar_ui_ref = get_tree().root.find_child("HotbarUI", true, false) as HotbarUI
	return _hotbar_ui_ref


func open_inventory(next_inventory: Inventory = null, next_title: String = "") -> void:
	if next_inventory != null:
		_bind_inventory(next_inventory)
	if next_title != "":
		title = next_title
	_title_label.text = title
	visible = true
	_refresh()
	SFX.duck_master(&"inventory", duck_db)
	_play_sound(open_sound)


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


func set_selected_slot(index: int) -> void:
	_selected_slot_index = index
	_update_selected_visual()


func close() -> void:
	if not visible:
		return
	visible = false
	SFX.unduck_master(&"inventory")
	_play_sound(close_sound)


func toggle() -> void:
	if visible:
		close()
	else:
		inventory_open_requested.emit()
		open_inventory()


func _bind_inventory(next_inventory: Inventory) -> void:
	var refresh_callable: Callable = Callable(self, "_refresh")
	if inventory != null and inventory.is_connected(&"inventory_changed", refresh_callable):
		inventory.disconnect(&"inventory_changed", refresh_callable)
	inventory = next_inventory
	if inventory != null and not inventory.is_connected(&"inventory_changed", refresh_callable):
		inventory.connect(&"inventory_changed", refresh_callable)


func _find_player_inventory_holder() -> InventoryHolder:
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		var holder: InventoryHolder = current_scene.find_child("PlayerInventory", true, false) as InventoryHolder
		if holder != null:
			return holder
	return get_tree().root.find_child("PlayerInventory", true, false) as InventoryHolder


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var backdrop: ColorRect = get_node_or_null("Backdrop") as ColorRect
	if backdrop != null:
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_title_label = get_node_or_null("Title") as Label
	if _title_label != null:
		_title_label.text = title

	_close_button = get_node_or_null("Close") as Button
	if _close_button != null:
		var close_callable: Callable = Callable(self, "close")
		if not _close_button.pressed.is_connected(close_callable):
			_close_button.pressed.connect(close_callable)

	_panel = get_node_or_null("Panel") as Panel
	if _panel == null:
		push_warning("InventoryUI needs a child Panel node.")
		return
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	_grid = _panel.get_node_or_null("Grid") as GridContainer
	if _grid == null:
		push_warning("InventoryUI Panel needs a Grid child.")
		return
	_grid.mouse_filter = Control.MOUSE_FILTER_PASS

	_rebuild_slots()


func _rebuild_slots() -> void:
	_slot_nodes.clear()
	if _collect_existing_slots():
		return
	var template: Button = _grid.get_node_or_null("SlotTemplate") as Button
	if template != null:
		template.visible = false
	push_warning("InventoryUI uses scene-authored slots. Add Slot0, Slot1, ... under Panel/Grid.")


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
	if inventory == null or _grid == null:
		return
	var slots: Array[Dictionary] = inventory.get_slots()
	if _slot_nodes.size() != columns * rows:
		_rebuild_slots()
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


func _update_selected_visual() -> void:
	for i in range(_slot_nodes.size()):
		var selected_marker: CanvasItem = _slot_nodes[i].get_node_or_null("Selected") as CanvasItem
		if selected_marker != null:
			selected_marker.visible = i == _selected_slot_index


func _on_slot_pressed(index: int) -> void:
	var slot: Dictionary = {}
	if inventory != null:
		slot = inventory.get_slot(index)
	DebugConsole.log("Inventory slot %d: %s" % [index, _debug_slot_text(slot)])
	slot_clicked.emit(index, slot)


func _on_slot_hovered(index: int) -> void:
	_hovered_slot_index = index
	var slot: Dictionary = {}
	if inventory != null:
		slot = inventory.get_slot(index)
	slot_hovered.emit(index, slot)


func _on_slot_unhovered(index: int) -> void:
	if _hovered_slot_index == index:
		_hovered_slot_index = -1
	slot_unhovered.emit(index)


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


func _slot_is_placeable(slot: Dictionary) -> bool:
	if slot.is_empty():
		return false
	return String(slot.get("scene_path", "")).strip_edges() != ""


func _seed_preview_inventory() -> void:
	if inventory == null:
		return
	var diamond_texture: Texture2D = Belt.get_ore_texture("diamond")
	var gold_texture: Texture2D = Belt.get_ore_texture("gold")
	var iron_texture: Texture2D = Belt.get_ore_texture("iron")
	for i in range(columns * rows):
		var item_type: String = "diamond"
		var texture: Texture2D = diamond_texture
		if i % 9 == 1 or i % 9 == 4:
			item_type = "gold"
			texture = gold_texture
		elif i % 7 == 2:
			item_type = "iron"
			texture = iron_texture
		inventory.set_slot(i, item_type, max_stack_size, texture)


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = SFX.play_oneshot(self, stream, 0.0)
	if player != null:
		player.bus = &"Master"
