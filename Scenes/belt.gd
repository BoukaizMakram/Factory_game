class_name Belt
extends Node2D

const CELL_SIZE: int = 64
const TICK_INTERVAL: float = 0.05
const ITEM_SPEED_PX: float = 64.0
const MAX_ITEMS: int = 5
const MIN_SPACING: float = 0.2
const META_KEY: StringName = &"belt_items"
const VISUALS_META_KEY: StringName = &"belt_item_visuals"
const FALLBACK_ITEM_START: Vector2 = Vector2(-97, -21)
const FALLBACK_ITEM_END: Vector2 = Vector2(95, -21)
const PROCESSING_RAW: String = "RAW"
const PROCESSING_CRUSHED: String = "CRUSHED"
const PURITY_BAD: String = "bad"
const PURITY_GOOD: String = "good"
const PURITY_HIGH: String = "high"

@export var framerate_min: float = 5.0
@export var framerate_max: float = 24.0
@export var item_speed_x: float = 64.0
@export var item_speed_y: float = 64.0
@export var transport_enabled: bool = true
@export var show_item_visuals: bool = true
@export var hold_raw_items_until_processed: bool = false
@export var item_capacity: int = MAX_ITEMS

static var _belts_by_cell: Dictionary = {}
static var _belt_anchors_by_cell: Dictionary = {}

var _tick_timer: float = 0.0


func _ready() -> void:
	call_deferred("_try_register")


func _try_register() -> void:
	var pl: Placeable = _get_placeable()
	if pl == null or pl.ghost_mode:
		return
	if not transport_enabled:
		return
	pl.refresh_cell_from_position()
	_unregister_belt(pl)
	_belt_anchors_by_cell[pl.cell] = pl
	for cell in _footprint_cells(pl):
		_belts_by_cell[cell] = pl
	if not pl.has_meta(META_KEY):
		pl.set_meta(META_KEY, [])
	_refresh_pipe_order_in_footprint(pl)


func _exit_tree() -> void:
	var pl: Placeable = _get_placeable()
	if pl == null:
		return
	var footprint_cells: Array[Vector2i] = _footprint_cells(pl)
	_unregister_belt(pl)
	_refresh_pipe_order_at_cells(footprint_cells)


func _process(delta: float) -> void:
	var pl: Placeable = _get_placeable()
	if pl == null or pl.ghost_mode:
		return
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	var dt: float = _tick_timer
	_tick_timer = 0.0
	if pl.powered:
		_tick(pl, dt)
		_update_belt_animation_speed(pl, true)
	else:
		_update_belt_animation_speed(pl, false)
	_update_item_visuals(pl)
	_update_label(pl)


func _tick(pl: Placeable, dt: float) -> void:
	var items: Array = pl.get_meta(META_KEY, [])
	if items.is_empty():
		return

	var speed_px: float = _current_item_speed_px_per_second(pl)
	for i in range(items.size()):
		var item: Dictionary = items[i] as Dictionary
		if hold_raw_items_until_processed and is_raw_item(item):
			continue
		var cap: float = 1.0
		if i > 0:
			cap = float(items[i - 1]["progress"]) - MIN_SPACING
		var item_start: Vector2 = item.get("start_position", _get_item_path_start(pl.direction))
		var item_end: Vector2 = _get_item_path_end(pl.direction)
		var path_length: float = maxf(item_start.distance_to(item_end), 1.0)
		var step: float = (speed_px * dt) / path_length
		var new_p: float = min(float(item["progress"]) + step, cap)
		if new_p < 0.0:
			new_p = 0.0
		item["progress"] = new_p

	if float(items[0]["progress"]) < 1.0:
		return
	var next_pl: Placeable = _find_next_belt(pl)
	if next_pl == null:
		return
	var visited: Dictionary = {}
	visited[pl] = true
	if _push_item_rec(next_pl.cell, items[0], visited, pl, true):
		items.pop_front()


static func _has_room(pl: Placeable, items: Array) -> bool:
	if items.size() >= _capacity_for_placeable(pl):
		return false
	if items.is_empty():
		return true
	var last: Dictionary = items[items.size() - 1] as Dictionary
	return float(last["progress"]) >= MIN_SPACING


static func _has_room_at_start(pl: Placeable, items: Array, start_global_position = null) -> bool:
	if items.size() >= _capacity_for_placeable(pl):
		return false
	if items.is_empty():
		return true
	if not (start_global_position is Vector2):
		return _has_room(pl, items)
	var start_local: Vector2 = pl.to_local(start_global_position)
	for item in items:
		var item_start: Vector2 = item.get("start_position", _get_item_path_start(pl.direction))
		var item_pos: Vector2 = item_start.lerp(_get_item_path_end(pl.direction), clampf(float(item.get("progress", 0.0)), 0.0, 1.0))
		if item_pos.distance_to(start_local) < float(CELL_SIZE) * MIN_SPACING:
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
	if p is AnimatedSprite2D and p.get_parent() is Placeable:
		return p.get_parent() as Placeable
	return null


func _current_item_speed_px_per_second(pl: Placeable) -> float:
	var target_speed: float = item_speed_y
	if pl.direction == Placeable.Dir.LEFT or pl.direction == Placeable.Dir.RIGHT:
		target_speed = item_speed_x
	var max_speed: float = maxf(target_speed, 0.0)
	var ratio: float = clampf(float(pl.get("_power_ratio")), 0.0, 1.0)
	return max_speed * ratio


func _update_belt_animation_speed(pl: Placeable, playing: bool) -> void:
	for child in pl.get_children():
		if child is AnimatedSprite2D:
			var sprite: AnimatedSprite2D = child as AnimatedSprite2D
			if not sprite.visible:
				_pause_sprite(sprite)
				continue
			if playing:
				_apply_animation_speed(sprite, pl)
				_resume_sprite(sprite)
			else:
				sprite.speed_scale = 1.0
				_pause_sprite(sprite)


func _apply_animation_speed(sprite: AnimatedSprite2D, pl: Placeable) -> void:
	if sprite.sprite_frames == null:
		return
	var min_fps: float = maxf(framerate_min, 0.0)
	var max_fps: float = maxf(framerate_max, min_fps)
	var ratio: float = clampf(float(pl.get("_power_ratio")), 0.0, 1.0)
	var target_fps: float = lerp(min_fps, max_fps, ratio)
	var base_fps: float = sprite.sprite_frames.get_animation_speed(sprite.animation)
	if base_fps <= 0.0:
		base_fps = maxf(max_fps, 0.001)
	sprite.speed_scale = target_fps / base_fps


func _resume_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if not sprite.is_playing():
		sprite.play()


func _pause_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if sprite.is_playing():
		sprite.pause()


func _update_item_visuals(pl: Placeable) -> void:
	if not show_item_visuals:
		_clear_item_visuals(pl)
		return
	var template: BeltItem = _resolve_item_template(pl)
	if template == null:
		return

	template.visible = false
	var items: Array = pl.get_meta(META_KEY, [])
	var visuals: Array = _get_or_create_visuals(pl)
	if not visuals.is_empty():
		var first_visual: Node = visuals[0] as Node
		if first_visual != null and is_instance_valid(first_visual) and first_visual.get_parent() != pl:
			for visual_node in visuals:
				if is_instance_valid(visual_node):
					visual_node.queue_free()
			visuals.clear()

	while visuals.size() < items.size():
		var clone: BeltItem = template.duplicate() as BeltItem
		if clone == null:
			break
		clone.name = "%sRuntime%d" % [template.name, visuals.size()]
		clone.visible = true
		pl.add_child(clone)
		visuals.append(clone)

	while visuals.size() > items.size():
		var extra: Node = visuals.pop_back() as Node
		if is_instance_valid(extra):
			extra.queue_free()

	for i in range(visuals.size()):
		var visual: BeltItem = visuals[i] as BeltItem
		if visual == null or not is_instance_valid(visual):
			continue
		var item: Dictionary = items[i] as Dictionary
		visual.texture = _get_texture_for_item(pl, template, item)
		visual.position = _get_item_position(pl, item)
		visual.visible = true


func _resolve_item_template(pl: Placeable) -> BeltItem:
	for c in pl.get_children():
		if c is BeltItem:
			return c as BeltItem
		if c is AnimatedSprite2D:
			for child in c.get_children():
				if child is BeltItem:
					return child as BeltItem
	return null


func _get_item_position(pl: Placeable, item: Dictionary) -> Vector2:
	var progress: float = float(item.get("progress", 0.0))
	var item_start: Vector2 = item.get("start_position", _get_item_path_start(pl.direction))
	return item_start.lerp(_get_item_path_end(pl.direction), clampf(progress, 0.0, 1.0))


func _get_or_create_visuals(pl: Placeable) -> Array:
	if not pl.has_meta(VISUALS_META_KEY):
		pl.set_meta(VISUALS_META_KEY, [])
	return pl.get_meta(VISUALS_META_KEY, [])


func _clear_item_visuals(pl: Placeable) -> void:
	var visuals: Array = pl.get_meta(VISUALS_META_KEY, [])
	for visual_node in visuals:
		if is_instance_valid(visual_node):
			visual_node.queue_free()
	visuals.clear()
	if pl.has_meta(VISUALS_META_KEY):
		pl.set_meta(VISUALS_META_KEY, visuals)
	var template: BeltItem = _resolve_item_template(pl)
	if template != null:
		template.visible = false


func _update_label(pl: Placeable) -> void:
	var label: Label = _resolve_label(pl)
	if label == null:
		return
	var items: Array = pl.get_meta(META_KEY, [])
	var lines: Array = []
	for it in items:
		lines.append("%s %s %d%%" % [_type_name(it.get("type", "")), String(it.get("processing", PROCESSING_RAW)), int(float(it["progress"]) * 100.0)])
	lines.append("(%d/%d)" % [items.size(), _capacity_for_placeable(pl)])
	lines.append("next belt: " + _next_belt_label(pl))
	label.text = "\n".join(lines)


func _next_belt_label(pl: Placeable) -> String:
	var next_pl: Placeable = _find_next_belt(pl)
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
	for check_cell in _next_belt_candidate_cells(pl):
		var cand: Placeable = _belt_anchors_by_cell.get(check_cell, null) as Placeable
		if cand != null and cand != pl and is_instance_valid(cand):
			return cand
	return null


static func _unregister_belt(pl: Placeable) -> void:
	for cell in _belt_anchors_by_cell.keys():
		if _belt_anchors_by_cell[cell] == pl:
			_belt_anchors_by_cell.erase(cell)
	for cell in _belts_by_cell.keys():
		if _belts_by_cell[cell] == pl:
			_belts_by_cell.erase(cell)


static func _footprint_cells(pl: Placeable) -> Array[Vector2i]:
	var anchor_cell: Vector2i = Vector2i(
		floor(pl.global_position.x / float(CELL_SIZE)),
		floor(pl.global_position.y / float(CELL_SIZE))
	)
	return pl.footprint_cells(anchor_cell)


static func _refresh_pipe_order_in_footprint(pl: Placeable) -> void:
	_refresh_pipe_order_at_cells(_footprint_cells(pl))


static func _refresh_pipe_order_at_cells(cells: Array[Vector2i]) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pg: Node = tree.root.get_node_or_null("PowerGrid")
	if pg == null:
		return
	for check_cell in cells:
		var pipe: Node = pg.get_pipe_at(check_cell) as Node
		if pipe != null and pipe.has_method("_update_visibility_order"):
			pipe._update_visibility_order()


static func _next_belt_candidate_cells(pl: Placeable) -> Array[Vector2i]:
	var cell: Vector2i = pl.cell
	match pl.direction:
		Placeable.Dir.UP:
			return [
				cell + Vector2i(0, -2),
				cell + Vector2i(1, -2),
				cell + Vector2i(-1, -2),
			]
		Placeable.Dir.DOWN:
			return [
				cell + Vector2i(0, 2),
				cell + Vector2i(1, 2),
				cell + Vector2i(-1, 2),
			]
		Placeable.Dir.LEFT:
			return [
				cell + Vector2i(-3, 0),
				cell + Vector2i(-3, -1),
				cell + Vector2i(-3, 1),
			]
		Placeable.Dir.RIGHT:
			return [
				cell + Vector2i(3, 0),
				cell + Vector2i(3, -1),
				cell + Vector2i(3, 1),
			]
	return []


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
	for c in pl.get_children():
		if c is Label:
			return c as Label
		if c.name == "Control":
			var label: Node = c.get_node_or_null("Label")
			if label is Label:
				return label as Label
	return null


static func _type_name(t) -> String:
	if t is String:
		return t
	if t is StringName:
		return String(t)
	if t is PackedScene:
		var path: String = (t as PackedScene).resource_path
		if path != "":
			return path.get_file().get_basename()
	return str(t)


# ── Public static API ────────────────────────────────────────────────

static func has_belt_at(cell: Vector2i) -> bool:
	var pl: Placeable = _belts_by_cell.get(cell, null) as Placeable
	return pl != null and is_instance_valid(pl)


static func get_belt_at(cell: Vector2i) -> Placeable:
	var pl: Placeable = _belts_by_cell.get(cell, null) as Placeable
	if pl != null and is_instance_valid(pl):
		return pl as Placeable
	return null


static func has_room_at_entry(cell: Vector2i, start_global_position = null) -> bool:
	var pl: Placeable = _belts_by_cell.get(cell, null) as Placeable
	if pl == null or not is_instance_valid(pl):
		return false
	return _has_room_at_start(pl, pl.get_meta(META_KEY, []), start_global_position)


static func push_item(cell: Vector2i, type_key, start_global_position = null) -> bool:
	return _push_item_rec(cell, type_key, {}, null, false, start_global_position)


static func get_ore_texture(type_key) -> Texture2D:
	for pl in _belts_by_cell.values():
		if pl != null and is_instance_valid(pl):
			var texture: Texture2D = _find_texture_in_belt_items(pl, type_key)
			if texture != null:
				return texture
	return BeltItem.get_mapped_texture(type_key)


static func _push_item_rec(cell: Vector2i, item_data, _visited: Dictionary, from_pl: Placeable = null, require_visual: bool = false, start_global_position = null) -> bool:
	var pl: Placeable = _belts_by_cell.get(cell, null) as Placeable
	if pl == null or not is_instance_valid(pl):
		return false
	if not pl.has_meta(META_KEY):
		pl.set_meta(META_KEY, [])
	var items: Array = pl.get_meta(META_KEY)
	if not _has_room_at_start(pl, items, start_global_position):
		return false
	var item: Dictionary = _normalize_item_data(item_data)
	item["progress"] = 0.0
	item["start_position"] = _get_entry_start_position(pl, from_pl, start_global_position)
	items.append(item)
	_notify_item_received(pl, item)
	if require_visual and _shows_item_visuals(pl) and not _refresh_item_visuals_static(pl):
		items.pop_back()
		return false
	return true


static func _normalize_item_data(item_data) -> Dictionary:
	if item_data is Dictionary:
		var item: Dictionary = (item_data as Dictionary).duplicate(true)
		if not item.has("type"):
			item["type"] = ""
		if not item.has("purity"):
			item["purity"] = _random_purity()
		if not item.has("processing"):
			item["processing"] = PROCESSING_RAW
		if not item.has("visual"):
			item["visual"] = "raw" if String(item["processing"]).to_upper() == PROCESSING_RAW else "ore"
		return item
	return {
		"type": _type_name(item_data),
		"purity": _random_purity(),
		"processing": PROCESSING_RAW,
		"visual": "raw",
	}


static func _random_purity() -> String:
	var roll: float = randf()
	if roll < 0.80:
		return PURITY_BAD
	if roll < 0.95:
		return PURITY_GOOD
	return PURITY_HIGH


static func crush_item(item: Dictionary) -> void:
	item["processing"] = PROCESSING_CRUSHED
	item["visual"] = "ore"


static func is_raw_item(item: Dictionary) -> bool:
	return String(item.get("processing", PROCESSING_RAW)).to_upper() == PROCESSING_RAW


static func _get_entry_start_position(pl: Placeable, from_pl: Placeable = null, start_global_position = null) -> Vector2:
	if start_global_position is Vector2:
		return pl.to_local(start_global_position)
	if from_pl == null:
		return _get_item_path_start(pl.direction)
	var previous_end_global: Vector2 = from_pl.to_global(_get_item_path_end(from_pl.direction))
	return pl.to_local(previous_end_global)


static func _resolve_item_template_static(pl: Placeable) -> BeltItem:
	for c in pl.get_children():
		if c is BeltItem:
			return c as BeltItem
		if c is AnimatedSprite2D:
			for child in c.get_children():
				if child is BeltItem:
					return child as BeltItem
	return null


static func _get_item_path_start(direction: int) -> Vector2:
	match direction:
		Placeable.Dir.UP:
			return Vector2(0, 51)
		Placeable.Dir.DOWN:
			return Vector2(0, -78)
		Placeable.Dir.LEFT:
			return Vector2(95, -21)
		Placeable.Dir.RIGHT:
			return Vector2(-97, -21)
	return FALLBACK_ITEM_START


static func _get_item_path_end(direction: int) -> Vector2:
	match direction:
		Placeable.Dir.UP:
			return Vector2(0, -78)
		Placeable.Dir.DOWN:
			return Vector2(0, 51)
		Placeable.Dir.LEFT:
			return Vector2(-97, -21)
		Placeable.Dir.RIGHT:
			return Vector2(95, -21)
	return FALLBACK_ITEM_END


static func _get_texture_for_type(pl: Placeable, template: BeltItem, type_key) -> Texture2D:
	var texture: Texture2D = _find_texture_in_belt_items(pl, type_key)
	if texture != null:
		return texture
	texture = BeltItem.get_mapped_texture(type_key)
	if texture != null:
		return texture
	return template.get_texture_for_type(type_key)


static func _get_texture_for_item(pl: Placeable, template: BeltItem, item: Dictionary) -> Texture2D:
	var texture: Texture2D = template.get_texture_for_item(item)
	if texture != null:
		return texture
	return _get_texture_for_type(pl, template, item.get("type", ""))


static func _find_texture_in_belt_items(pl: Placeable, type_key) -> Texture2D:
	for c in pl.get_children():
		if c is BeltItem:
			var root_item: BeltItem = c as BeltItem
			var root_texture: Texture2D = root_item.find_texture_for_type(type_key)
			if root_texture != null:
				return root_texture
		if c is AnimatedSprite2D:
			for child in c.get_children():
				if child is BeltItem:
					var item: BeltItem = child as BeltItem
					var texture: Texture2D = item.find_texture_for_type(type_key)
					if texture != null:
						return texture
	return null


static func _refresh_item_visuals_static(pl: Placeable) -> bool:
	var belt: Belt = _get_transport_logic(pl)
	if belt != null:
		belt._update_item_visuals(pl)
		belt._update_label(pl)
		if not belt.show_item_visuals:
			return true
		return _has_visual_for_each_item(pl)
	return false


static func _shows_item_visuals(pl: Placeable) -> bool:
	var belt: Belt = _get_transport_logic(pl)
	return belt == null or belt.show_item_visuals


static func _get_transport_logic(pl: Placeable) -> Belt:
	for child in pl.get_children():
		if child is Belt:
			return child as Belt
	return null


static func _capacity_for_placeable(pl: Placeable) -> int:
	var belt: Belt = _get_transport_logic(pl)
	if belt == null:
		return MAX_ITEMS
	return max(1, belt.item_capacity)


static func _notify_item_received(pl: Placeable, item: Dictionary) -> void:
	for child in pl.get_children():
		if child.has_method("on_transport_item_received"):
			child.on_transport_item_received(item)


static func _has_visual_for_each_item(pl: Placeable) -> bool:
	var items: Array = pl.get_meta(META_KEY, [])
	if items.is_empty():
		return true
	if not pl.has_meta(VISUALS_META_KEY):
		return false
	var visuals: Array = pl.get_meta(VISUALS_META_KEY, [])
	if visuals.size() < items.size():
		return false
	for visual_node in visuals:
		if not is_instance_valid(visual_node):
			return false
		var visual_item: CanvasItem = visual_node as CanvasItem
		if visual_item == null or not visual_item.visible:
			return false
	return true


static func get_items(cell: Vector2i) -> Array:
	var pl: Placeable = _belts_by_cell.get(cell, null) as Placeable
	if pl == null or not is_instance_valid(pl):
		return []
	return pl.get_meta(META_KEY, [])
