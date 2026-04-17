extends Node

signal networks_updated(network_count: int)

const NEIGHBOR_OFFSETS: Array = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var _pipes: Dictionary = {}      # cell -> ElectricalPipe
var _machines: Dictionary = {}   # cell -> Placeable (non-pipe)
var _dirty: bool = true


func _process(_delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()


func mark_dirty() -> void:
	_dirty = true


# ── Pipe registration ────────────────────────────────────────────────

func register_pipe(pipe: Placeable) -> void:
	if pipe == null:
		return
	_pipes[pipe.cell] = pipe
	mark_dirty()


func unregister_pipe(pipe: Placeable) -> void:
	if pipe == null:
		return
	if _pipes.get(pipe.cell, null) == pipe:
		_pipes.erase(pipe.cell)
	else:
		for k in _pipes.keys():
			if _pipes[k] == pipe:
				_pipes.erase(k)
				break
	mark_dirty()


func has_pipe_at(cell: Vector2i) -> bool:
	return _pipes.has(cell) and is_instance_valid(_pipes[cell])


func get_pipe_at(cell: Vector2i):
	if _pipes.has(cell) and is_instance_valid(_pipes[cell]):
		return _pipes[cell]
	return null


# ── Machine registration ─────────────────────────────────────────────

func register_machine(machine: Placeable) -> void:
	if machine == null:
		return
	_machines[machine.cell] = machine
	mark_dirty()


func unregister_machine(machine: Placeable) -> void:
	if machine == null:
		return
	if _machines.get(machine.cell, null) == machine:
		_machines.erase(machine.cell)
	else:
		for k in _machines.keys():
			if _machines[k] == machine:
				_machines.erase(k)
				break
	mark_dirty()


func has_machine_at(cell: Vector2i) -> bool:
	return _machines.has(cell) and is_instance_valid(_machines[cell])


# ── Queries ───────────────────────────────────────────────────────────

func totals() -> Dictionary:
	var produced: float = 0.0
	var consumed: float = 0.0
	for m in _machines.values():
		if not is_instance_valid(m):
			continue
		produced += m.watts_produced
		consumed += m.watts_consumed
	return {"produced": produced, "consumed": consumed}


# ── Network rebuild ───────────────────────────────────────────────────

func _rebuild() -> void:
	# Clean invalid entries
	for k in _pipes.keys():
		if not is_instance_valid(_pipes[k]):
			_pipes.erase(k)
	for k in _machines.keys():
		if not is_instance_valid(_machines[k]):
			_machines.erase(k)

	var visited: Dictionary = {}  # pipe cell -> true
	var handled_machines: Dictionary = {}  # machine cell -> true
	var network_count: int = 0

	for start_cell in _pipes.keys():
		if visited.has(start_cell):
			continue

		# Step 1: Flood-fill + ±3 propagation to find this network's pipes
		var network_pipes: Dictionary = {}  # cell -> true
		var stack: Array = [start_cell]
		while stack.size() > 0:
			var c: Vector2i = stack.pop_back()
			if network_pipes.has(c):
				continue
			if not _pipes.has(c):
				continue
			network_pipes[c] = true
			# Direct neighbors
			for offset in NEIGHBOR_OFFSETS:
				var nc: Vector2i = c + offset
				if not network_pipes.has(nc) and _pipes.has(nc):
					stack.append(nc)
			# ±3 range along axis
			var extended: Array = _pipes[c].get_powered_cells()
			for pc in extended:
				if not network_pipes.has(pc) and _pipes.has(pc):
					stack.append(pc)

		# Mark all as visited so other networks don't re-process them
		for c in network_pipes.keys():
			visited[c] = true

		# Step 2: Find machines reachable from this network's pipes
		var network_machines: Dictionary = {}  # cell -> machine
		for pipe_cell in network_pipes.keys():
			if not _pipes.has(pipe_cell):
				continue
			# Machine on exact pipe cell
			if _machines.has(pipe_cell) and is_instance_valid(_machines[pipe_cell]):
				network_machines[pipe_cell] = _machines[pipe_cell]
			# Adjacent machines
			for offset in NEIGHBOR_OFFSETS:
				var adj: Vector2i = pipe_cell + offset
				if _machines.has(adj) and is_instance_valid(_machines[adj]):
					network_machines[adj] = _machines[adj]
			# Machines within ±3 range
			var ext: Array = _pipes[pipe_cell].get_powered_cells()
			for pc in ext:
				if _machines.has(pc) and is_instance_valid(_machines[pc]):
					network_machines[pc] = _machines[pc]

		# Step 3: Calculate this network's totals
		var produced: float = 0.0
		var consumed: float = 0.0
		for m in network_machines.values():
			produced += m.watts_produced
			consumed += m.watts_consumed

		var net_power: float = produced - consumed
		var has_power: bool = net_power >= 0.5
		var ratio: float = 0.0
		if consumed > 0.0 and has_power:
			ratio = clampf(produced / consumed, 0.0, 1.0)
		elif has_power:
			ratio = 1.0

		# Step 4: Apply to this network's pipes
		for cell in network_pipes.keys():
			if _pipes.has(cell) and is_instance_valid(_pipes[cell]):
				if has_power:
					_pipes[cell].set_pipe_powered(true, produced, consumed)
				else:
					_pipes[cell].set_pipe_powered(false)

		# Step 5: Apply to this network's machines
		for cell in network_machines.keys():
			handled_machines[cell] = true
			if has_power:
				network_machines[cell].set_powered(true, ratio)
			else:
				network_machines[cell].set_powered(false, 0.0)

		network_count += 1

	# Machines not on any network -> unpowered
	for cell in _machines.keys():
		if not handled_machines.has(cell) and is_instance_valid(_machines[cell]):
			_machines[cell].set_powered(false, 0.0)

	networks_updated.emit(network_count)
