extends Node2D

@export var inventory_ui_path: NodePath = NodePath("CanvasLayer/InventoryUI")
@export var hotbar_ui_path: NodePath = NodePath("CanvasLayer/HotbarUI")

var _inventory_ui: InventoryUI
var _hotbar_ui: HotbarUI
var _grab_inventory: Inventory
var _grab_index: int = -1


func _ready() -> void:
	_inventory_ui = get_node_or_null(inventory_ui_path) as InventoryUI
	_hotbar_ui = get_node_or_null(hotbar_ui_path) as HotbarUI
	if _inventory_ui != null:
		var inventory_callable: Callable = Callable(self, "_on_inventory_slot_clicked")
		if not _inventory_ui.slot_clicked.is_connected(inventory_callable):
			_inventory_ui.slot_clicked.connect(inventory_callable)
	if _hotbar_ui != null:
		var hotbar_callable: Callable = Callable(self, "_on_hotbar_slot_clicked")
		if not _hotbar_ui.hotbar_slot_clicked.is_connected(hotbar_callable):
			_hotbar_ui.hotbar_slot_clicked.connect(hotbar_callable)


func _on_inventory_slot_clicked(index: int, _slot: Dictionary) -> void:
	if _inventory_ui == null:
		return
	_handle_slot_click(_inventory_ui.get_inventory(), index)


func _on_hotbar_slot_clicked(index: int, _slot: Dictionary) -> void:
	if _hotbar_ui == null:
		return
	_handle_slot_click(_hotbar_ui.get_inventory(), index)


func _handle_slot_click(target_inventory: Inventory, target_index: int) -> void:
	if target_inventory == null:
		_clear_grabbed_slot()
		return
	var target_slot: Dictionary = target_inventory.get_slot(target_index)
	if _grab_inventory == null:
		if target_slot.is_empty():
			_clear_grabbed_slot()
			return
		_grab_inventory = target_inventory
		_grab_index = target_index
		_update_grabbed_slot_visual()
		return
	if _grab_inventory == target_inventory and _grab_index == target_index:
		_clear_grabbed_slot()
		return
	if _grab_inventory == target_inventory:
		_grab_inventory.swap_slots(_grab_index, target_index)
	else:
		var grabbed_slot: Dictionary = _grab_inventory.get_slot(_grab_index)
		_grab_inventory.set_slot_data(_grab_index, target_slot)
		target_inventory.set_slot_data(target_index, grabbed_slot)
	_clear_grabbed_slot()


func _clear_grabbed_slot() -> void:
	_grab_inventory = null
	_grab_index = -1
	_update_grabbed_slot_visual()


func _update_grabbed_slot_visual() -> void:
	if _inventory_ui == null:
		return
	if _grab_inventory == _inventory_ui.get_inventory():
		_inventory_ui.set_selected_slot(_grab_index)
	else:
		_inventory_ui.set_selected_slot(-1)
