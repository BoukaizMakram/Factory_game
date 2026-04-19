class_name ElectricalPipe
extends Placeable

## Bitmask constants for neighbor connections
const UP_BIT := 1
const RIGHT_BIT := 2
const DOWN_BIT := 4
const LEFT_BIT := 8

## Maps bitmask value -> animation name.
## Add animations to the SpriteFrames as you create the art.
## Missing animations fall back to the closest match.
const MASK_TO_ANIM := {
	0: "isolated",
	UP_BIT: "end_up",
	RIGHT_BIT: "end_right",
	DOWN_BIT: "end_down",
	LEFT_BIT: "end_left",
	UP_BIT | DOWN_BIT: "vertical",
	LEFT_BIT | RIGHT_BIT: "horizontal",
	UP_BIT | RIGHT_BIT: "corner_ur",
	RIGHT_BIT | DOWN_BIT: "corner_dr",
	DOWN_BIT | LEFT_BIT: "corner_dl",
	LEFT_BIT | UP_BIT: "corner_ul",
	UP_BIT | RIGHT_BIT | DOWN_BIT: "t_right",
	RIGHT_BIT | DOWN_BIT | LEFT_BIT: "t_down",
	DOWN_BIT | LEFT_BIT | UP_BIT: "t_left",
	LEFT_BIT | UP_BIT | RIGHT_BIT: "t_up",
	UP_BIT | RIGHT_BIT | DOWN_BIT | LEFT_BIT: "cross",
}

## Fallback chain: if the exact animation doesn't exist, try these in order.
const FALLBACKS := {
	"isolated": ["horizontal", "right", "default"],
	"end_up": ["vertical", "up", "default"],
	"end_right": ["horizontal", "right", "default"],
	"end_down": ["vertical", "down", "default"],
	"end_left": ["horizontal", "left", "default"],
	"vertical": ["up", "default"],
	"horizontal": ["right", "default"],
	"corner_ur": ["right", "default"],
	"corner_dr": ["right", "default"],
	"corner_dl": ["left", "default"],
	"corner_ul": ["left", "default"],
	"t_right": ["right", "default"],
	"t_down": ["down", "default"],
	"t_left": ["left", "default"],
	"t_up": ["up", "default"],
	"cross": ["grid", "right", "default"],
}

const BIT_OFFSETS := {
	UP_BIT: Vector2i(0, -1),
	RIGHT_BIT: Vector2i(1, 0),
	DOWN_BIT: Vector2i(0, 1),
	LEFT_BIT: Vector2i(-1, 0),
}

const VISUAL_NOTIFY_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(2, 0),
	Vector2i(-2, 0),
	Vector2i(3, 0),
	Vector2i(-3, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(0, 2),
	Vector2i(0, -2),
]

const BASE_Z_INDEX: int = 1
const INSPECT_Z_INDEX: int = 100

@export var power_label: Label

static var inspect_mode: bool = false
static var power_labels_visible: bool = false

var connection_mask: int = 0
var has_power: bool = false
var network_watts: float = 0.0
var force_cross: bool = true


func _init() -> void:
	is_pipe = true


func _ready() -> void:
	_resolve_cell_span()
	if power_label != null:
		power_label.visible = power_labels_visible
	if ghost_mode:
		_update_pipe_sprite()
		return
	add_to_group("placeable")
	add_to_group("pipe")
	call_deferred("_register_with_grid")
	call_deferred("_post_place")


func _post_place() -> void:
	update_connections()
	_notify_neighbors()


func update_connections(notify_power_grid: bool = true) -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	connection_mask = 0
	for bit in BIT_OFFSETS:
		var neighbor_cell: Vector2i = cell + BIT_OFFSETS[bit]
		if pg.has_pipe_at(neighbor_cell):
			connection_mask |= bit
	# Cross mode: always show all 4 directions
	if force_cross:
		connection_mask = UP_BIT | RIGHT_BIT | DOWN_BIT | LEFT_BIT
	# No neighbors: keep the direction the player chose
	elif connection_mask == 0:
		match direction:
			Dir.UP, Dir.DOWN:
				connection_mask = UP_BIT | DOWN_BIT
			Dir.LEFT, Dir.RIGHT:
				connection_mask = LEFT_BIT | RIGHT_BIT
	_update_pipe_sprite()
	_update_visibility_order()
	if notify_power_grid:
		pg.mark_dirty()


func _notify_neighbors() -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	for offset in VISUAL_NOTIFY_OFFSETS:
		var neighbor_cell: Vector2i = cell + offset
		var neighbor = pg.get_pipe_at(neighbor_cell)
		if neighbor != null and neighbor.has_method("update_connections"):
			neighbor.update_connections()


func _exit_tree() -> void:
	if ghost_mode:
		return
	var notify_cells: Array[Vector2i] = _visual_notify_cells()
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg:
		pg.unregister_pipe(self)
	_notify_cells_on_remove(notify_cells)


func _notify_cells_on_remove(notify_cells: Array) -> void:
	var pg: Node = get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	for neighbor_cell in notify_cells:
		var neighbor = pg.get_pipe_at(neighbor_cell)
		if neighbor != null and neighbor.has_method("update_connections"):
			neighbor.update_connections()


func _visual_notify_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in VISUAL_NOTIFY_OFFSETS:
		cells.append(cell + offset)
	return cells


func _update_visibility_order() -> void:
	if ghost_mode:
		return
	z_as_relative = false
	if inspect_mode:
		z_index = INSPECT_Z_INDEX
		return
	z_index = BASE_Z_INDEX
	var belt: Placeable = Belt.get_belt_at(cell)
	if belt != null and belt.z_index >= z_index:
		z_index = belt.z_index + 1


func set_inspect_visible(enabled: bool) -> void:
	inspect_mode = enabled
	_update_visibility_order()


func _update_pipe_sprite() -> void:
	var target_anim: String = "cross"
	var sprite_name: String = _resolve_sprite_name(target_anim)
	# Try matching child AnimatedSprite2D by name first
	var found_match: bool = false
	for c in get_children():
		if c is AnimatedSprite2D:
			var name_lower: String = c.name.to_lower()
			if name_lower == sprite_name:
				c.visible = true
				_update_sprite_playback(c as AnimatedSprite2D)
				found_match = true
			else:
				c.visible = false
				c.stop()
	# Fallback: use old animation-based approach if no named children matched
	if not found_match:
		_apply_pipe_anim(self, target_anim)


func _resolve_sprite_name(target_anim: String) -> String:
	if _has_child_sprite(target_anim):
		return target_anim
	for fallback in FALLBACKS.get(target_anim, []):
		if _has_child_sprite(fallback):
			return fallback
	return target_anim


func _has_child_sprite(sprite_name: String) -> bool:
	for c in get_children():
		if c is AnimatedSprite2D and c.name.to_lower() == sprite_name:
			return true
	return false


func _apply_pipe_anim(node: Node, anim_name: String) -> void:
	if node is AnimatedSprite2D:
		var sprite: AnimatedSprite2D = node as AnimatedSprite2D
		if sprite.sprite_frames != null:
			if sprite.sprite_frames.has_animation(anim_name):
				sprite.animation = anim_name
				_update_sprite_playback(sprite)
				return
			var fallback_list: Array = FALLBACKS.get(anim_name, ["default"])
			for fb in fallback_list:
				if sprite.sprite_frames.has_animation(fb):
					sprite.animation = fb
					_update_sprite_playback(sprite)
					return
	for c in node.get_children():
		_apply_pipe_anim(c, anim_name)


func _update_visible_sprite_playback() -> void:
	for c in get_children():
		if c is AnimatedSprite2D and c.visible:
			_update_sprite_playback(c as AnimatedSprite2D)


func _update_sprite_playback(sprite: AnimatedSprite2D) -> void:
	if sprite == null:
		return
	if ghost_mode or has_power:
		sprite.play()
	else:
		sprite.stop()


## Called by PowerGrid after rebuild to set power state on this pipe
func set_pipe_powered(is_powered: bool, produced: float = 0.0, consumed: float = 0.0) -> void:
	has_power = is_powered
	network_watts = produced - consumed
	_update_visible_sprite_playback()
	if power_label != null:
		power_label.text = "Network: " + str(produced) + "W\nNeeded: " + str(consumed) + "W"
		power_label.visible = power_labels_visible


func set_power_label_visible(enabled: bool) -> void:
	power_labels_visible = enabled
	if power_label != null:
		power_label.visible = enabled


## Returns all cells this pipe provides power to.
## Horizontal reach is 3 cells each way; vertical reach is 2 cells each way.
func get_powered_cells() -> Array:
	var cells: Array = [cell]
	var is_horizontal: bool = (connection_mask & (LEFT_BIT | RIGHT_BIT)) != 0
	var is_vertical: bool = (connection_mask & (UP_BIT | DOWN_BIT)) != 0

	if is_horizontal:
		for i in range(1, 4):
			cells.append(cell + Vector2i(i, 0))
			cells.append(cell + Vector2i(-i, 0))
	if is_vertical:
		for i in range(1, 3):
			cells.append(cell + Vector2i(0, i))
			cells.append(cell + Vector2i(0, -i))

	# If isolated (no connections), spread in both directions
	if not is_horizontal and not is_vertical:
		for i in range(1, 4):
			cells.append(cell + Vector2i(i, 0))
			cells.append(cell + Vector2i(-i, 0))
		for i in range(1, 3):
			cells.append(cell + Vector2i(0, i))
			cells.append(cell + Vector2i(0, -i))

	return cells


## Override: ghost pipes show direction preview, placed pipes use connection mask
func apply_direction_animation() -> void:
	if ghost_mode:
		connection_mask = UP_BIT | RIGHT_BIT | DOWN_BIT | LEFT_BIT
	_update_pipe_sprite()
