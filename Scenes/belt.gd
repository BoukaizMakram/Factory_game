class_name Belt
extends Node2D

const CELL_SIZE: int = 64
const TICK_INTERVAL: float = 0.1
const ITEM_SPEED_PX: float = 64.0
const MIN_SPACING: float = 0.4
const META_KEY: StringName = &"belt_items"

@export var items_label: Label

static var _belts_by_cell: Dictionary = {}

var _tick_timer: float = 0.0


func _ready() -> void:
	call_deferred("_try_register")


func _try_register() -> void:
	var pl := _get_placeable()
	if pl == null or pl.ghost_mode:
		return
	pl.refresh_cell_from_position()
	_belts_by_cell[pl.cell] = pl
	if not pl.has_meta(META_KEY):
		pl.set_meta(META_KEY, [])


func _exit_tree() -> void:
	var pl := _get_placeable()
	if pl == null:
		return
	if _belts_by_cell.get(pl.cell, null) == pl:
		_belts_by_cell.erase(pl.cell)


func _process(delta: float) -> void:
	if not visible:
		return
	var pl := _get_placeable()
	if pl == null or pl.ghost_mode:
		return
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	var dt: float = _tick_timer
	_tick_timer = 0.0
	_tick(pl, dt)
	_update_label(pl)


func _tick(pl: Placeable, _dt: float) -> void:
	var items: Array = pl.get_meta(META_KEY, [])
	if items.is_empty():
		return

	var next_pl: Placeable = _find_next_belt(pl)
	if next_pl == null:
		return

	var to_remove: Array = []
	for item in items:
		var visited: Dictionary = {}
		visited[pl] = true
		if _push_item_rec(next_pl.cell, item["type"], visited):
			to_remove.append(item)
		else:
			break
	for t in to_remove:
		items.erase(t)


static func _has_room(items: Array) -> bool:
	for it in items:
		if float(it["progress"]) < MIN_SPACING:
			return false
	return true


func _dir_vec(d: int) -> Vector2i:
	match d:
		Placeable.Dir.UP:
			return Vector2i(0, -1)
		Placeable.Dir.DOWN:
			return Vector2i(0, 1)
		Placeable.Dir.LEFT:
			return Vector2i(-1, 0)
		Placeable.Dir.RIGHT:
			return Vector2i(1, 0)
	return Vector2i(1, 0)


func _get_placeable() -> Placeable:
	var p: Node = get_parent()
	if p is Placeable:
		return p as Placeable
	return null


func _update_label(pl: Placeable) -> void:
	var label: Label = _resolve_label(pl)
	if label == null:
		return
	var items: Array = pl.get_meta(META_KEY, [])
	var counts: Dictionary = {}
	for it in items:
		var key_name: String = _type_name(it["type"])
		counts[key_name] = counts.get(key_name, 0) + 1
	var lines: Array = []
	for k in counts:
		lines.append("%s: %d" % [k, counts[k]])
	lines.append("next belt: " + _next_belt_label(pl))
	label.text = "\n".join(lines)


func _next_belt_label(pl: Placeable) -> String:
	var next_pl := _find_next_belt(pl)
	if next_pl == null:
		return "N/A"
	return _dir_name(pl.direction)


func _find_next_belt(pl: Placeable) -> Placeable:
	return _find_next_belt_static(pl)


static func _dir_vec_static(d: int) -> Vector2i:
	match d:
		Placeable.Dir.UP:
			return Vector2i(0, -1)
		Placeable.Dir.DOWN:
			return Vector2i(0, 1)
		Placeable.Dir.LEFT:
			return Vector2i(-1, 0)
		Placeable.Dir.RIGHT:
			return Vector2i(1, 0)
	return Vector2i(1, 0)


static func _find_next_belt_static(pl: Placeable) -> Placeable:
	var dir: Vector2i = _dir_vec_static(pl.direction)
	for i in range(1, 4):
		var check_cell: Vector2i = pl.cell + dir * i
		var cand = _belts_by_cell.get(check_cell, null)
		if cand != null and is_instance_valid(cand):
			return cand
	return null


static func _dir_name(d: int) -> String:
	match d:
		Placeable.Dir.UP:
			return "up"
		Placeable.Dir.DOWN:
			return "down"
		Placeable.Dir.LEFT:
			return "left"
		Placeable.Dir.RIGHT:
			return "right"
	return "?"


func _resolve_label(pl: Placeable) -> Label:
	if items_label != null and is_instance_valid(items_label):
		return items_label
	for c in pl.get_children():
		if c is Label:
			return c as Label
	return null


static func _type_name(t) -> String:
	if t is String:
		return t
	if t is StringName:
		return String(t)
	if t is PackedScene:
		var path := (t as PackedScene).resource_path
		if path != "":
			return path.get_file().get_basename()
	return str(t)


# ── Public static API ────────────────────────────────────────────────

static func has_belt_at(cell: Vector2i) -> bool:
	var pl = _belts_by_cell.get(cell, null)
	return pl != null and is_instance_valid(pl)


static func has_room_at_entry(cell: Vector2i) -> bool:
	var pl = _belts_by_cell.get(cell, null)
	if pl == null or not is_instance_valid(pl):
		return false
	return _has_room(pl.get_meta(META_KEY, []))


static func push_item(cell: Vector2i, type_key) -> bool:
	return _push_item_rec(cell, type_key, {})


static func _push_item_rec(cell: Vector2i, type_key, visited: Dictionary) -> bool:
	var pl = _belts_by_cell.get(cell, null)
	if pl == null or not is_instance_valid(pl):
		return false
	if visited.has(pl):
		return false
	visited[pl] = true
	if not pl.has_meta(META_KEY):
		pl.set_meta(META_KEY, [])
	var items: Array = pl.get_meta(META_KEY)
	var next_pl: Placeable = _find_next_belt_static(pl)
	if next_pl != null:
		if _push_item_rec(next_pl.cell, type_key, visited):
			return true
	if not _has_room(items):
		return false
	items.append({"type": type_key, "progress": 0.0})
	return true


static func get_items(cell: Vector2i) -> Array:
	var pl = _belts_by_cell.get(cell, null)
	if pl == null or not is_instance_valid(pl):
		return []
	return pl.get_meta(META_KEY, [])
