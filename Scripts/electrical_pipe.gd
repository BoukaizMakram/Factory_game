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

@export var power_label: Label

var connection_mask: int = 0
var has_power: bool = false
var network_watts: float = 0.0
var force_cross: bool = false


func _init() -> void:
	is_pipe = true


func _ready() -> void:
	_resolve_cell_span()
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


func update_connections() -> void:
	var pg := get_node_or_null("/root/PowerGrid")
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


func _notify_neighbors() -> void:
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	for bit in BIT_OFFSETS:
		var neighbor_cell: Vector2i = cell + BIT_OFFSETS[bit]
		var neighbor = pg.get_pipe_at(neighbor_cell)
		if neighbor != null and neighbor.has_method("update_connections"):
			neighbor.update_connections()


func _exit_tree() -> void:
	if ghost_mode:
		return
	var pg := get_node_or_null("/root/PowerGrid")
	if pg:
		pg.unregister_pipe(self)
	# Tell neighbors to update after we're gone (deferred so grid state is current)
	call_deferred("_notify_neighbors_on_remove")


func _notify_neighbors_on_remove() -> void:
	var pg := get_node_or_null("/root/PowerGrid")
	if pg == null:
		return
	for bit in BIT_OFFSETS:
		var neighbor_cell: Vector2i = cell + BIT_OFFSETS[bit]
		var neighbor = pg.get_pipe_at(neighbor_cell)
		if neighbor != null and neighbor.has_method("update_connections"):
			neighbor.update_connections()


func _update_pipe_sprite() -> void:
	var target_anim: String = MASK_TO_ANIM.get(connection_mask, "isolated")
	# Try matching child AnimatedSprite2D by name first
	var found_match: bool = false
	for c in get_children():
		if c is AnimatedSprite2D:
			var name_lower: String = c.name.to_lower()
			if name_lower == target_anim:
				c.visible = true
				c.play()
				found_match = true
			else:
				# Also check fallbacks
				var is_fallback: bool = false
				var fallback_list: Array = FALLBACKS.get(target_anim, [])
				for fb in fallback_list:
					if name_lower == fb:
						is_fallback = true
						break
				if is_fallback and not found_match:
					c.visible = true
					c.play()
					found_match = true
				else:
					c.visible = false
					c.stop()
	# Fallback: use old animation-based approach if no named children matched
	if not found_match:
		_apply_pipe_anim(self, target_anim)


func _apply_pipe_anim(node: Node, anim_name: String) -> void:
	if node is AnimatedSprite2D:
		var sprite := node as AnimatedSprite2D
		if sprite.sprite_frames != null:
			if sprite.sprite_frames.has_animation(anim_name):
				sprite.play(anim_name)
				return
			var fallback_list: Array = FALLBACKS.get(anim_name, ["default"])
			for fb in fallback_list:
				if sprite.sprite_frames.has_animation(fb):
					sprite.play(fb)
					return
	for c in node.get_children():
		_apply_pipe_anim(c, anim_name)


## Called by PowerGrid after rebuild to set power state on this pipe
func set_pipe_powered(is_powered: bool, produced: float = 0.0, consumed: float = 0.0) -> void:
	has_power = is_powered
	network_watts = produced - consumed
	if power_label != null:
		var left: float = maxf(produced - consumed, 0.0)
		power_label.text = "Used: " + str(consumed) + "W\nLeft: " + str(left) + "W"
		power_label.visible = true


## Returns all cells this pipe provides power to (itself + 3 cells along its axis)
func get_powered_cells() -> Array:
	var cells: Array = [cell]
	var is_horizontal: bool = (connection_mask & (LEFT_BIT | RIGHT_BIT)) != 0
	var is_vertical: bool = (connection_mask & (UP_BIT | DOWN_BIT)) != 0

	if is_horizontal:
		for i in range(1, 4):
			cells.append(cell + Vector2i(i, 0))
			cells.append(cell + Vector2i(-i, 0))
	if is_vertical:
		for i in range(1, 4):
			cells.append(cell + Vector2i(0, i))
			cells.append(cell + Vector2i(0, -i))

	# If isolated (no connections), spread in both directions
	if not is_horizontal and not is_vertical:
		for i in range(1, 4):
			cells.append(cell + Vector2i(i, 0))
			cells.append(cell + Vector2i(-i, 0))
			cells.append(cell + Vector2i(0, i))
			cells.append(cell + Vector2i(0, -i))

	return cells


## Override: ghost pipes show direction preview, placed pipes use connection mask
func apply_direction_animation() -> void:
	if ghost_mode:
		if force_cross:
			connection_mask = UP_BIT | RIGHT_BIT | DOWN_BIT | LEFT_BIT
		else:
			match direction:
				Dir.UP, Dir.DOWN:
					connection_mask = UP_BIT | DOWN_BIT
				Dir.LEFT, Dir.RIGHT:
					connection_mask = LEFT_BIT | RIGHT_BIT
	_update_pipe_sprite()
