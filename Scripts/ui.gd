extends Node2D

@export var inventory_ui_path: NodePath = NodePath("CanvasLayer/InventoryUI")
@export var hotbar_ui_path: NodePath = NodePath("CanvasLayer/HotbarUI")
@export var hover_label_path: NodePath = NodePath("CursorLayer/HoverItemLabel")
@export var cursor_icon_path: NodePath = NodePath("CursorLayer/CursorItemIcon")
@export var placer_path: NodePath = NodePath("../Placer")
@export var placeable_move_sound: AudioStream = preload("res://SFX/raw/metal.mp3")

var _inventory_ui: InventoryUI
var _hotbar_ui: HotbarUI
var _hover_label: Label
var _cursor_icon: TextureRect
var _placer: Node
var _grab_inventory: Inventory
var _grab_index: int = -1
var _hovered_ui_slots: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_inventory_ui = get_node_or_null(inventory_ui_path) as InventoryUI
	_hotbar_ui = get_node_or_null(hotbar_ui_path) as HotbarUI
	_hover_label = get_node_or_null(hover_label_path) as Label
	_cursor_icon = get_node_or_null(cursor_icon_path) as TextureRect
	_resolve_placer()
	_connect_inventory_ui()
	_connect_hotbar_ui()
	_hide_hover_label()
	_update_grabbed_slot_visual()


func _process(_delta: float) -> void:
	if _inventory_ui != null and not _inventory_ui.visible:
		_clear_hovered_slot_prefix("inventory:")
	if _hotbar_ui != null and not _hotbar_ui.visible:
		_clear_hovered_slot_prefix("hotbar:")
	_sync_ui_blocks_placement_from_mouse()
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	if _hover_label != null and _hover_label.visible:
		_hover_label.position = mouse_position + Vector2(18.0, -34.0)
	if _cursor_icon != null and _cursor_icon.visible:
		_cursor_icon.position = mouse_position + Vector2(18.0, 18.0)
	_refresh_grabbed_slot_from_inventory()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_resolve_placer()
			var placer_has_selection: bool = _placer != null and _placer.has_method("has_active_selection") and bool(_placer.call("has_active_selection"))
			var empty_handed: bool = _grab_inventory == null and not placer_has_selection
			if empty_handed and _placer != null and _placer.has_method("select_hovered_placeable_from_inventory") and _placer.call("select_hovered_placeable_from_inventory"):
				get_viewport().set_input_as_handled()
				return
			clear_selection()
			get_viewport().set_input_as_handled()


func _connect_inventory_ui() -> void:
	if _inventory_ui == null:
		return
	var click_callable: Callable = Callable(self, "_on_inventory_slot_clicked")
	if not _inventory_ui.slot_clicked.is_connected(click_callable):
		_inventory_ui.slot_clicked.connect(click_callable)
	var open_callable: Callable = Callable(self, "_on_inventory_open_requested")
	if not _inventory_ui.inventory_open_requested.is_connected(open_callable):
		_inventory_ui.inventory_open_requested.connect(open_callable)
	var hover_callable: Callable = Callable(self, "_on_inventory_slot_hovered")
	if not _inventory_ui.slot_hovered.is_connected(hover_callable):
		_inventory_ui.slot_hovered.connect(hover_callable)
	var unhover_callable: Callable = Callable(self, "_on_inventory_slot_unhovered")
	if not _inventory_ui.slot_unhovered.is_connected(unhover_callable):
		_inventory_ui.slot_unhovered.connect(unhover_callable)


func _connect_hotbar_ui() -> void:
	if _hotbar_ui == null:
		return
	var click_callable: Callable = Callable(self, "_on_hotbar_slot_clicked")
	if not _hotbar_ui.hotbar_slot_clicked.is_connected(click_callable):
		_hotbar_ui.hotbar_slot_clicked.connect(click_callable)
	var selection_callable: Callable = Callable(self, "_on_hotbar_selection_changed")
	if not _hotbar_ui.hotbar_selection_changed.is_connected(selection_callable):
		_hotbar_ui.hotbar_selection_changed.connect(selection_callable)
	var hover_callable: Callable = Callable(self, "_on_hotbar_slot_hovered")
	if not _hotbar_ui.hotbar_slot_hovered.is_connected(hover_callable):
		_hotbar_ui.hotbar_slot_hovered.connect(hover_callable)
	var unhover_callable: Callable = Callable(self, "_on_hotbar_slot_unhovered")
	if not _hotbar_ui.hotbar_slot_unhovered.is_connected(unhover_callable):
		_hotbar_ui.hotbar_slot_unhovered.connect(unhover_callable)


func _on_inventory_slot_clicked(index: int, _slot: Dictionary) -> void:
	if _inventory_ui == null:
		return
	_handle_slot_click(_inventory_ui.get_inventory(), index)


func _on_inventory_open_requested() -> void:
	clear_selection()


func _on_hotbar_slot_clicked(index: int, _slot: Dictionary) -> void:
	if _hotbar_ui == null:
		return
	var hotbar_inventory: Inventory = _hotbar_ui.get_inventory()
	var clicked_selected_slot: bool = _grab_inventory == hotbar_inventory and _grab_index == index
	_handle_slot_click(_hotbar_ui.get_inventory(), index)
	if clicked_selected_slot:
		_hotbar_ui.deselect_slot()
	else:
		_hotbar_ui.select_slot(index)


func _on_hotbar_selection_changed(index: int, slot: Dictionary) -> void:
	if _hotbar_ui == null:
		return
	var hotbar_inventory: Inventory = _hotbar_ui.get_inventory()
	if slot.is_empty():
		if _grab_inventory == hotbar_inventory:
			_clear_grabbed_slot()
		return
	_select_grabbed_slot(hotbar_inventory, index)


func _on_inventory_slot_hovered(_index: int, slot: Dictionary) -> void:
	_set_ui_slot_hovered("inventory:%d" % _index, true)
	_show_hover_label(slot)


func _on_hotbar_slot_hovered(_index: int, slot: Dictionary) -> void:
	_set_ui_slot_hovered("hotbar:%d" % _index, true)
	_show_hover_label(slot)


func _on_inventory_slot_unhovered(_index: int) -> void:
	_set_ui_slot_hovered("inventory:%d" % _index, false)
	_hide_hover_label()


func _on_hotbar_slot_unhovered(_index: int) -> void:
	_set_ui_slot_hovered("hotbar:%d" % _index, false)
	_hide_hover_label()


func _handle_slot_click(target_inventory: Inventory, target_index: int) -> void:
	if target_inventory == null:
		_clear_grabbed_slot()
		return
	var target_slot: Dictionary = target_inventory.get_slot(target_index)
	if _grab_inventory == null:
		if target_slot.is_empty():
			_clear_grabbed_slot()
			return
		_select_grabbed_slot(target_inventory, target_index)
		return
	if _grab_inventory == target_inventory and _grab_index == target_index:
		_clear_grabbed_slot()
		return
	var grabbed_slot: Dictionary = _grab_inventory.get_slot(_grab_index)
	var moved_placeable: bool = _slot_is_placeable(grabbed_slot) or _slot_is_placeable(target_slot)
	if _grab_inventory == target_inventory:
		_grab_inventory.swap_slots(_grab_index, target_index)
	else:
		_grab_inventory.set_slot_data(_grab_index, target_slot)
		target_inventory.set_slot_data(target_index, grabbed_slot)
	if moved_placeable:
		_play_sound(placeable_move_sound)
	_clear_grabbed_slot()


func _select_grabbed_slot(source_inventory: Inventory, source_index: int) -> void:
	_grab_inventory = source_inventory
	_grab_index = source_index
	_update_grabbed_slot_visual()
	_send_selection_to_placer()


func select_inventory_slot_for_cursor(source_inventory: Inventory, source_index: int) -> void:
	if source_inventory == null or source_index < 0 or source_index >= source_inventory.get_slots().size():
		_clear_grabbed_slot()
		return
	var slot: Dictionary = source_inventory.get_slot(source_index)
	if slot.is_empty():
		_clear_grabbed_slot()
		return
	_select_grabbed_slot(source_inventory, source_index)


func _clear_grabbed_slot() -> void:
	_grab_inventory = null
	_grab_index = -1
	_update_grabbed_slot_visual()
	if _placer != null and _placer.has_method("clear_inventory_selection"):
		_placer.call("clear_inventory_selection")


func clear_selection() -> void:
	_clear_grabbed_slot()
	if _hotbar_ui != null:
		_hotbar_ui.deselect_slot()


func _refresh_grabbed_slot_from_inventory() -> void:
	if _grab_inventory == null:
		return
	var slot: Dictionary = _grab_inventory.get_slot(_grab_index)
	if slot.is_empty():
		_clear_grabbed_slot()
		return
	_update_cursor_icon(slot)


func _update_grabbed_slot_visual() -> void:
	if _inventory_ui != null:
		if _grab_inventory == _inventory_ui.get_inventory():
			_inventory_ui.set_selected_slot(_grab_index)
		else:
			_inventory_ui.set_selected_slot(-1)
	if _grab_inventory == null:
		if _cursor_icon != null:
			_cursor_icon.visible = false
			_cursor_icon.texture = null
		return
	var slot: Dictionary = _grab_inventory.get_slot(_grab_index)
	_update_cursor_icon(slot)


func _update_cursor_icon(slot: Dictionary) -> void:
	if _cursor_icon == null:
		return
	var texture: Texture2D = _texture_for_slot(slot)
	_cursor_icon.texture = texture
	_cursor_icon.visible = texture != null and not slot.is_empty()


func _send_selection_to_placer() -> void:
	_resolve_placer()
	if _placer == null or not _placer.has_method("select_inventory_slot_for_placement"):
		return
	if _grab_inventory == null:
		_placer.call("select_inventory_slot_for_placement", null, -1, {})
		return
	_placer.call("select_inventory_slot_for_placement", _grab_inventory, _grab_index, _grab_inventory.get_slot(_grab_index))


func _set_ui_slot_hovered(slot_key: String, hovered: bool) -> void:
	if hovered:
		_hovered_ui_slots[slot_key] = true
	else:
		_hovered_ui_slots.erase(slot_key)
	_update_ui_blocks_placement()


func _clear_hovered_slot_prefix(prefix: String) -> void:
	var changed: bool = false
	for slot_key in _hovered_ui_slots.keys():
		if String(slot_key).begins_with(prefix):
			_hovered_ui_slots.erase(slot_key)
			changed = true
	if changed:
		_update_ui_blocks_placement()


func _update_ui_blocks_placement() -> void:
	_resolve_placer()
	if _placer != null and _placer.has_method("set_ui_blocks_placement"):
		_placer.call("set_ui_blocks_placement", not _hovered_ui_slots.is_empty())


func _sync_ui_blocks_placement_from_mouse() -> void:
	var over_slot: bool = false
	if _inventory_ui != null and _inventory_ui.is_mouse_over_slot():
		over_slot = true
	if _hotbar_ui != null and _hotbar_ui.is_mouse_over_slot():
		over_slot = true
	_resolve_placer()
	if _placer != null and _placer.has_method("set_ui_blocks_placement"):
		_placer.call("set_ui_blocks_placement", over_slot)


func _show_hover_label(slot: Dictionary) -> void:
	if _hover_label == null:
		return
	if slot.is_empty():
		_hide_hover_label()
		return
	_hover_label.text = _slot_display_text(slot)
	_hover_label.visible = true


func _hide_hover_label() -> void:
	if _hover_label == null:
		return
	_hover_label.visible = false
	_hover_label.text = ""


func _slot_display_text(slot: Dictionary) -> String:
	var item_name: String = String(slot.get("type", "")).strip_edges()
	if item_name == "":
		var scene_path: String = String(slot.get("scene_path", "")).strip_edges()
		if scene_path != "":
			item_name = scene_path.get_file().get_basename()
	if item_name == "":
		item_name = "Item"
	var amount: int = int(slot.get("amount", 0))
	if amount > 1:
		return "%s x%d" % [item_name, amount]
	return item_name


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


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = SFX.play_oneshot(self, stream, 0.0)
	if player != null:
		player.bus = &"Master"


func _resolve_placer() -> void:
	if _placer != null and is_instance_valid(_placer):
		return
	if placer_path != NodePath(""):
		_placer = get_node_or_null(placer_path)
	if _placer != null:
		return
	var current_scene: Node = get_tree().current_scene
	if current_scene != null:
		_placer = current_scene.find_child("Placer", true, false)
	if _placer == null:
		_placer = get_tree().root.find_child("Placer", true, false)
