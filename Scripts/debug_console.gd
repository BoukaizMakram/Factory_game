class_name DebugConsole
extends Control

static var _instance: DebugConsole
static var _backlog: PackedStringArray = PackedStringArray()

@export var log_path: NodePath = NodePath("Panel/Log")
@export var command_path: NodePath = NodePath("Panel/Command")

var _log: RichTextLabel
var _command_input: LineEdit


static func log(message: String) -> void:
	if _instance != null and is_instance_valid(_instance):
		_instance.add_line(message)
		return
	_backlog.append(message)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_instance = self
	_log = get_node_or_null(log_path) as RichTextLabel
	_command_input = get_node_or_null(command_path) as LineEdit
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _command_input != null:
		var submit_callable: Callable = Callable(self, "_on_command_submitted")
		if not _command_input.text_submitted.is_connected(submit_callable):
			_command_input.text_submitted.connect(submit_callable)
	for line in _backlog:
		add_line(line)
	_backlog.clear()
	add_line("Debug console ready. Type help.")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == GameSettings.get_key("debug_console"):
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	call_deferred("_sync_command_focus")


func _sync_command_focus() -> void:
	if _command_input == null or not is_instance_valid(_command_input):
		return
	if not _command_input.is_inside_tree():
		return
	if visible:
		_command_input.grab_focus()
	else:
		_command_input.release_focus()


func add_line(message: String) -> void:
	var line: String = str(message)
	print(line)
	if _log == null:
		return
	_log.append_text(line + "\n")
	_log.scroll_to_line(_log.get_line_count())


func _on_command_submitted(command_text: String) -> void:
	if _command_input != null:
		_command_input.clear()
	var command: String = command_text.strip_edges()
	if command == "":
		return
	add_line("> " + command)
	_run_command(command)


func _run_command(command: String) -> void:
	var parts: PackedStringArray = command.to_lower().split(" ", false)
	if parts.is_empty():
		return
	match parts[0]:
		"help":
			add_line("Commands: help, clear, watts, watts on, watts off, watts toggle")
		"clear":
			if _log != null:
				_log.clear()
		"watts", "watt", "power":
			_run_watts_command(parts)
		_:
			add_line("Unknown command: " + command)


func _run_watts_command(parts: PackedStringArray) -> void:
	var enabled: bool = not ElectricalPipe.power_labels_visible
	if parts.size() >= 2:
		match parts[1]:
			"on", "show", "1", "true":
				enabled = true
			"off", "hide", "0", "false":
				enabled = false
			"toggle":
				enabled = not ElectricalPipe.power_labels_visible
			_:
				add_line("Usage: watts on | watts off | watts toggle")
				return
	ElectricalPipe.power_labels_visible = enabled
	var changed: int = 0
	for pipe in get_tree().get_nodes_in_group("pipe"):
		if pipe != null and is_instance_valid(pipe) and pipe.has_method("set_power_label_visible"):
			pipe.set_power_label_visible(enabled)
			changed += 1
	add_line("Electrical watt labels: %s (%d pipes)" % ["ON" if enabled else "OFF", changed])
