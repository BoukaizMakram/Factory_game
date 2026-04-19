class_name Placeable
extends Node2D

enum Dir { UP, RIGHT, DOWN, LEFT }

const CELL_SIZE: int = 64

@export var display_size_px: float = 64.0
@export var item_name: String = ""
@export var watts_produced: float = 0.0
@export var watts_consumed: float = 0.0
@export var direction: int = Dir.RIGHT
@export var cell_span: int = 0
@export var footprint_width_cells: int = 3
@export var footprint_height_cells: int = 2
@export var is_miner: bool = false
@export var ignore_pipe_direction: bool = false
@export var allow_belt_overlap: bool = false
@export var animation_min_fps: float = 5.0
@export var animation_max_fps: float = 24.0

var is_pipe: bool = false

var cell: Vector2i = Vector2i.ZERO
var powered: bool = false
var ghost_mode: bool = false
var _power_ratio: float = 1.0

signal power_state_changed(is_powered: bool)

const DIR_VECTORS: Dictionary = {
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}


static func direction_name(d: int) -> String:
	match d:
		Dir.UP:
			return "up"
		Dir.DOWN:
			return "down"
		Dir.LEFT:
			return "left"
		Dir.RIGHT:
			return "right"
	return "default"


const ANIM_FALLBACKS: Dictionary = {
	Dir.LEFT: ["left", "default"],
	Dir.RIGHT: ["right", "default"],
	Dir.UP: ["up", "Rotated"],
	Dir.DOWN: ["down", "Rotated"],
}

const DIRECTION_ORDER: Array[int] = [Dir.UP, Dir.RIGHT, Dir.DOWN, Dir.LEFT]


static func opposite(d: int) -> int:
	match d:
		Dir.UP:
			return Dir.DOWN
		Dir.DOWN:
			return Dir.UP
		Dir.LEFT:
			return Dir.RIGHT
		Dir.RIGHT:
			return Dir.LEFT
	return d


func direction_vector() -> Vector2i:
	return DIR_VECTORS.get(direction, Vector2i.ZERO)


func opposite_direction() -> int:
	return opposite(direction)


func _ready() -> void:
	_resolve_cell_span()
	direction = normalize_direction_for_available(direction)
	if ghost_mode:
		apply_direction_animation()
		return
	add_to_group("placeable")
	apply_direction_animation()
	# Machines that consume power start stopped until powered
	if watts_consumed > 0.0 and not is_pipe:
		_set_animation_playing(self, false)
	call_deferred("_register_with_grid")


func _resolve_cell_span() -> void:
	if cell_span > 0:
		return
	var derived: int = int(round(display_size_px / float(CELL_SIZE)))
	cell_span = max(1, derived)


func effective_span() -> int:
	return max(1, cell_span)


func footprint_width() -> int:
	return max(1, footprint_width_cells)


func footprint_height() -> int:
	return max(1, footprint_height_cells)


func footprint_cells(anchor_cell: Vector2i = cell) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var width: int = footprint_width()
	var height: int = footprint_height()
	var left: int = anchor_cell.x - int(floor(width / 2.0))
	var top: int = anchor_cell.y - (height - 1)
	for y in range(top, top + height):
		for x in range(left, left + width):
			cells.append(Vector2i(x, y))
	return cells


func footprint_contains_cell(check_cell: Vector2i, anchor_cell: Vector2i = cell) -> bool:
	return footprint_cells(anchor_cell).has(check_cell)


func _exit_tree() -> void:
	if ghost_mode:
		return
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg:
		if is_pipe:
			pg.unregister_pipe(self)
		else:
			pg.unregister_machine(self)


func _register_with_grid() -> void:
	if not is_inside_tree() or ghost_mode:
		return
	refresh_cell_from_position()
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg:
		if is_pipe:
			pg.register_pipe(self)
		else:
			pg.register_machine(self)


func refresh_cell_from_position() -> void:
	cell = Vector2i(floor(global_position.x / float(CELL_SIZE)), floor(global_position.y / float(CELL_SIZE)))


func set_direction(d: int) -> void:
	d = normalize_direction_for_available(d)
	if d == direction:
		return
	direction = d
	apply_direction_animation()
	if ghost_mode:
		return
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg:
		pg.mark_dirty()


## power_ratio: how much of the machine's needed watts are available (0.0 to 1.0+)
func set_powered(p: bool, power_ratio: float = 1.0) -> void:
	powered = p
	_power_ratio = power_ratio
	_update_power_tint()
	_update_animation_playback()
	power_state_changed.emit(powered)


func apply_direction_animation() -> void:
	direction = normalize_direction_for_available(direction)
	var dir_name: String = direction_name(direction)
	var found_match: bool = false
	var has_direction_children: bool = _has_direction_child_sprite(self)
	for c in get_children():
		if c is AnimatedSprite2D:
			var name_lower: String = c.name.to_lower()
			if name_lower == dir_name:
				c.visible = true
				_resume_sprite(c as AnimatedSprite2D)
				found_match = true
			elif has_direction_children and _direction_from_name(name_lower) >= 0:
				c.visible = false
				_pause_sprite(c as AnimatedSprite2D)
	if not found_match:
		_apply_anim_for_direction(self, direction)


func normalize_direction_for_available(d: int) -> int:
	var available: Array[int] = available_directions()
	if available.is_empty() or available.has(d):
		return d
	return available[0]


func next_available_direction(from_direction: int) -> int:
	var available: Array[int] = available_directions_ordered(DIRECTION_ORDER)
	if available.is_empty():
		return from_direction
	var start_idx: int = available.find(from_direction)
	if start_idx < 0:
		return available[0]
	return available[(start_idx + 1) % available.size()]


func available_directions_ordered(order: Array[int]) -> Array[int]:
	var available: Array[int] = available_directions()
	var ordered: Array[int] = []
	for d in order:
		if available.has(d):
			ordered.append(d)
	return ordered


func available_directions() -> Array[int]:
	var directions: Array[int] = []
	_collect_direction_child_sprites(self, directions)
	if not directions.is_empty():
		return directions
	_collect_direction_animations(self, directions)
	if not directions.is_empty():
		return directions
	return [direction]


static func _collect_direction_child_sprites(node: Node, out: Array[int]) -> void:
	if node is AnimatedSprite2D:
		var d: int = _direction_from_name(node.name.to_lower())
		if d >= 0 and not out.has(d):
			out.append(d)
	for child in node.get_children():
		_collect_direction_child_sprites(child, out)


static func _collect_direction_animations(node: Node, out: Array[int]) -> void:
	if node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D
		if sprite.sprite_frames != null:
			for d in DIRECTION_ORDER:
				if sprite.sprite_frames.has_animation(direction_name(d)) and not out.has(d):
					out.append(d)
	for child in node.get_children():
		_collect_direction_animations(child, out)


static func _has_direction_child_sprite(node: Node) -> bool:
	if node is AnimatedSprite2D and _direction_from_name(node.name.to_lower()) >= 0:
		return true
	for child in node.get_children():
		if _has_direction_child_sprite(child):
			return true
	return false


static func _direction_from_name(name_lower: String) -> int:
	match name_lower:
		"up":
			return Dir.UP
		"right":
			return Dir.RIGHT
		"down":
			return Dir.DOWN
		"left":
			return Dir.LEFT
	return -1


func _update_power_tint() -> void:
	if ghost_mode:
		return
	if watts_consumed <= 0.0:
		modulate = Color(1, 1, 1, 1)
		return
	modulate = Color(1, 1, 1, 1) if powered else Color(0.55, 0.55, 0.6, 1)


func _update_animation_playback() -> void:
	if ghost_mode or is_pipe:
		return
	if not powered:
		_set_animation_playing(self, false, 0.0)
		return
	_set_animation_playing(self, true, _power_ratio)


func _set_animation_playing(node: Node, playing: bool, ratio: float = 1.0) -> void:
	for c in node.get_children():
		if c is AnimatedSprite2D:
			var s: AnimatedSprite2D = c as AnimatedSprite2D
			if not s.visible or s.sprite_frames == null:
				continue
			if playing:
				var target_fps: float = lerp(animation_min_fps, animation_max_fps, clampf(ratio, 0.0, 1.0))
				var base_fps: float = s.sprite_frames.get_animation_speed(s.animation)
				if base_fps <= 0.0:
					base_fps = maxf(animation_max_fps, 0.001)
				s.speed_scale = target_fps / base_fps
				_resume_sprite(s)
			else:
				s.speed_scale = 1.0
				_pause_sprite(s)
		elif c.get_child_count() > 0:
			_set_animation_playing(c, playing, ratio)


static func _apply_anim_for_direction(node: Node, d: int) -> void:
	if node is AnimatedSprite2D:
		var s: AnimatedSprite2D = node as AnimatedSprite2D
		if s.sprite_frames:
			for anim_name in ANIM_FALLBACKS.get(d, ["default"]):
				if s.sprite_frames.has_animation(anim_name):
					if s.animation == anim_name:
						_resume_sprite(s)
					else:
						s.play(anim_name)
					break
	for c in node.get_children():
		_apply_anim_for_direction(c, d)


static func _resume_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if not sprite.is_playing():
		sprite.play()


static func _pause_sprite(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if sprite.is_playing():
		sprite.pause()
