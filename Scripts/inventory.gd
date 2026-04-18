class_name Inventory
extends Resource

signal inventory_changed

const DEFAULT_STACK_SIZE: int = 100

@export var slot_count: int = 36
@export var max_stack_size: int = DEFAULT_STACK_SIZE

var _slots: Array[Dictionary] = []


func _init(count: int = 36, stack_size: int = DEFAULT_STACK_SIZE) -> void:
	slot_count = max(1, count)
	max_stack_size = max(1, stack_size)
	_resize_slots()


func setup(count: int, stack_size: int = DEFAULT_STACK_SIZE) -> void:
	slot_count = max(1, count)
	max_stack_size = max(1, stack_size)
	_resize_slots()
	inventory_changed.emit()


func get_slots() -> Array[Dictionary]:
	_resize_slots()
	return _slots


func get_slot(index: int) -> Dictionary:
	_resize_slots()
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index]


func set_slot(index: int, item_type: String, amount: int, texture: Texture2D = null, scene_path: String = "", icon_path: String = "") -> void:
	_resize_slots()
	if index < 0 or index >= _slots.size():
		return
	if amount <= 0 or item_type.strip_edges() == "":
		_slots[index] = {}
	else:
		var slot: Dictionary = {
			"type": item_type,
			"amount": min(amount, max_stack_size),
			"texture": texture,
		}
		if scene_path.strip_edges() != "":
			slot["scene_path"] = scene_path
		if icon_path.strip_edges() != "":
			slot["icon_path"] = icon_path
		_slots[index] = slot
	inventory_changed.emit()


func set_slot_data(index: int, slot: Dictionary) -> void:
	_resize_slots()
	if index < 0 or index >= _slots.size():
		return
	_slots[index] = slot.duplicate()
	inventory_changed.emit()


func swap_slots(first_index: int, second_index: int) -> void:
	_resize_slots()
	if first_index < 0 or first_index >= _slots.size():
		return
	if second_index < 0 or second_index >= _slots.size():
		return
	if first_index == second_index:
		return
	var first_slot: Dictionary = _slots[first_index]
	_slots[first_index] = _slots[second_index]
	_slots[second_index] = first_slot
	inventory_changed.emit()


func remove_from_slot(index: int, amount: int) -> int:
	_resize_slots()
	var remaining: int = max(0, amount)
	if index < 0 or index >= _slots.size() or remaining <= 0:
		return remaining
	var slot: Dictionary = _slots[index]
	if slot.is_empty():
		return remaining
	var current_amount: int = int(slot.get("amount", 0))
	var removed: int = min(current_amount, remaining)
	current_amount -= removed
	remaining -= removed
	if current_amount <= 0:
		_slots[index] = {}
	else:
		slot["amount"] = current_amount
		_slots[index] = slot
	inventory_changed.emit()
	return remaining


func add_item(item_type: String, amount: int, texture: Texture2D = null, scene_path: String = "", icon_path: String = "") -> int:
	_resize_slots()
	var remaining: int = max(0, amount)
	if item_type.strip_edges() == "" or remaining <= 0:
		return remaining

	for i in range(_slots.size()):
		if remaining <= 0:
			break
		var slot: Dictionary = _slots[i]
		if not _slot_matches_item(slot, item_type, scene_path):
			continue
		var current_amount: int = int(slot.get("amount", 0))
		var space: int = max_stack_size - current_amount
		if space <= 0:
			continue
		var added: int = min(space, remaining)
		slot["amount"] = current_amount + added
		if texture != null:
			slot["texture"] = texture
		if scene_path.strip_edges() != "":
			slot["scene_path"] = scene_path
		if icon_path.strip_edges() != "":
			slot["icon_path"] = icon_path
		_slots[i] = slot
		remaining -= added

	for i in range(_slots.size()):
		if remaining <= 0:
			break
		if not _slots[i].is_empty():
			continue
		var added: int = min(max_stack_size, remaining)
		var slot: Dictionary = {
			"type": item_type,
			"amount": added,
			"texture": texture,
		}
		if scene_path.strip_edges() != "":
			slot["scene_path"] = scene_path
		if icon_path.strip_edges() != "":
			slot["icon_path"] = icon_path
		_slots[i] = slot
		remaining -= added

	inventory_changed.emit()
	return remaining


func has_item(item_type: String, scene_path: String = "") -> bool:
	_resize_slots()
	for slot in _slots:
		if _slot_matches_item(slot, item_type, scene_path):
			return true
	return false


func remove_item(item_type: String, amount: int) -> int:
	_resize_slots()
	var remaining: int = max(0, amount)
	if item_type.strip_edges() == "" or remaining <= 0:
		return remaining

	for i in range(_slots.size() - 1, -1, -1):
		if remaining <= 0:
			break
		var slot: Dictionary = _slots[i]
		if slot.is_empty() or String(slot.get("type", "")) != item_type:
			continue
		var current_amount: int = int(slot.get("amount", 0))
		var removed: int = min(current_amount, remaining)
		current_amount -= removed
		remaining -= removed
		if current_amount <= 0:
			_slots[i] = {}
		else:
			slot["amount"] = current_amount
			_slots[i] = slot

	inventory_changed.emit()
	return remaining


func clear() -> void:
	_resize_slots()
	for i in range(_slots.size()):
		_slots[i] = {}
	inventory_changed.emit()


func _resize_slots() -> void:
	while _slots.size() < slot_count:
		_slots.append({})
	while _slots.size() > slot_count:
		_slots.pop_back()


func _slot_matches_item(slot: Dictionary, item_type: String, scene_path: String = "") -> bool:
	if slot.is_empty():
		return false
	if String(slot.get("type", "")) != item_type:
		return false
	return String(slot.get("scene_path", "")) == scene_path
