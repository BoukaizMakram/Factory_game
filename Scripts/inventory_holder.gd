class_name InventoryHolder
extends Node

@export var slot_count: int = 36
@export var max_stack_size: int = Inventory.DEFAULT_STACK_SIZE

var inventory: Inventory


func _ready() -> void:
	if inventory == null:
		inventory = Inventory.new(slot_count, max_stack_size)
	else:
		inventory.setup(slot_count, max_stack_size)


func add_item(item_type: String, amount: int, texture: Texture2D = null, scene_path: String = "", icon_path: String = "") -> int:
	_ensure_inventory()
	return inventory.add_item(item_type, amount, texture, scene_path, icon_path)


func remove_item(item_type: String, amount: int) -> int:
	_ensure_inventory()
	return inventory.remove_item(item_type, amount)


func has_item(item_type: String, scene_path: String = "") -> bool:
	_ensure_inventory()
	return inventory.has_item(item_type, scene_path)


func get_inventory() -> Inventory:
	_ensure_inventory()
	return inventory


func _ensure_inventory() -> void:
	if inventory == null:
		inventory = Inventory.new(slot_count, max_stack_size)
