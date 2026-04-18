class_name InventoryUI
extends Control

signal slot_clicked(index: int, slot: Dictionary)

@export var title: String = "INVENTORY"
@export var columns: int = 6
@export var rows: int = 6
@export var slot_size: Vector2 = Vector2(96, 96)
@export var slot_gap: int = 28
@export var max_stack_size: int = 100
@export var close_key: int = KEY_I
@export var seed_preview_items: bool = false
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var inventory_holder_path: NodePath

var inventory: Inventory
var _panel: Panel
var _grid: GridContainer
var _title_label: Label
var _close_button: Button
var _slot_nodes: Array[Button] = []
var _selected_slot_index: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
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
		if event.keycode == close_key:
			toggle()


func open_inventory(next_inventory: Inventory = null, next_title: String = "") -> void:
	if next_inventory != null:
		_bind_inventory(next_inventory)
	if next_title != "":
		title = next_title
	_title_label.text = title
	visible = true
	_refresh()
	_play_sound(open_sound)


func get_inventory() -> Inventory:
	return inventory


func set_selected_slot(index: int) -> void:
	_selected_slot_index = index
	_update_selected_visual()


func close() -> void:
	if not visible:
		return
	visible = false
	_play_sound(close_sound)


func toggle() -> void:
	if visible:
		close()
	else:
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

	_grid = _panel.get_node_or_null("Grid") as GridContainer
	if _grid == null:
		push_warning("InventoryUI Panel needs a Grid child.")
		return

	_rebuild_slots()


func _rebuild_slots() -> void:
	_slot_nodes.clear()
	if _collect_existing_slots():
		return
	var template: Button = _grid.get_node_or_null("SlotTemplate") as Button
	if template == null:
		push_warning("InventoryUI Grid needs a SlotTemplate Button.")
		return
	template.visible = false
	for child in _grid.get_children():
		if child != template:
			child.queue_free()
	for i in range(max(1, columns * rows)):
		var slot_button: Button = template.duplicate() as Button
		if slot_button == null:
			continue
		slot_button.name = "Slot%d" % i
		slot_button.visible = true
		slot_button.mouse_filter = Control.MOUSE_FILTER_STOP
		slot_button.focus_mode = Control.FOCUS_NONE
		slot_button.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(slot_button)

		var icon: TextureRect = slot_button.get_node_or_null("Icon") as TextureRect
		if icon != null:
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var amount_label: Label = slot_button.get_node_or_null("Amount") as Label
		if amount_label != null:
			amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var selected_marker: CanvasItem = slot_button.get_node_or_null("Selected") as CanvasItem
		if selected_marker != null:
			selected_marker.visible = i == _selected_slot_index

		_slot_nodes.append(slot_button)


func _collect_existing_slots() -> bool:
	for child in _grid.get_children():
		if child is Button and child.name.begins_with("Slot") and child.name != "SlotTemplate":
			var slot_button: Button = child as Button
			var slot_index: int = _slot_index_from_name(slot_button.name)
			if slot_index < 0:
				slot_index = _slot_nodes.size()
			var slot_callable: Callable = Callable(self, "_on_slot_pressed").bind(slot_index)
			if not slot_button.pressed.is_connected(slot_callable):
				slot_button.pressed.connect(slot_callable)
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
	print("Inventory slot %d: %s" % [index, _debug_slot_text(slot)])
	slot_clicked.emit(index, slot)


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
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"Master"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)
