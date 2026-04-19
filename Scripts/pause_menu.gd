class_name PauseMenu
extends Control

signal pause_menu_opened
signal pause_menu_closed
signal resume_requested
signal quit_requested

const ACTION_TO_ROW: Dictionary = {
	"move_up": "MoveUp",
	"move_down": "MoveDown",
	"move_left": "MoveLeft",
	"move_right": "MoveRight",
	"inventory": "Inventory",
	"pause": "Pause",
	"debug_console": "DebugConsole",
	"placer_cancel": "PlacerCancel",
	"placer_rotate": "PlacerRotate",
	"placer_pipe_cross": "PlacerPipeCross",
	"placer_toggle_grid": "PlacerToggleGrid",
	"placer_inspect": "PlacerInspect",
	"hotbar_1": "Hotbar1",
	"hotbar_2": "Hotbar2",
	"hotbar_3": "Hotbar3",
	"hotbar_4": "Hotbar4",
	"hotbar_5": "Hotbar5",
	"hotbar_6": "Hotbar6",
}

@export var title: String = "PAUSED"
@export var open_sound: AudioStream
@export var close_sound: AudioStream
@export var pause_tree: bool = true
@export var duck_db: float = -24.0

@onready var _title_label: Label = get_node_or_null("Title") as Label
@onready var _resume_button: Button = get_node_or_null("Panel/Resume") as Button
@onready var _settings_button: Button = get_node_or_null("Panel/Settings") as Button
@onready var _quit_button: Button = get_node_or_null("Panel/Quit") as Button
@onready var _settings_panel: Panel = get_node_or_null("SettingsPanel") as Panel
@onready var _settings_close_button: Button = get_node_or_null("SettingsPanel/CloseButton") as Button
@onready var _settings_reset_button: Button = get_node_or_null("SettingsPanel/ResetButton") as Button
@onready var _content: VBoxContainer = get_node_or_null("SettingsPanel/Scroll/Content") as VBoxContainer

var _rebinding_action: String = ""
var _rebinding_button: Button
var _keybind_buttons: Dictionary = {}
var _hidden_siblings: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 3000
	z_as_relative = false
	visible = false

	if _title_label != null:
		_title_label.text = title

	if _resume_button != null:
		_resume_button.pressed.connect(_on_resume_pressed)
	if _settings_button != null:
		_settings_button.pressed.connect(_on_settings_pressed)
	if _quit_button != null:
		_quit_button.pressed.connect(_on_quit_pressed)

	_wire_settings()


func _unhandled_input(event: InputEvent) -> void:
	if _rebinding_action != "" and event is InputEventKey and event.pressed and not event.echo:
		_apply_rebind(event.keycode)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == GameSettings.get_key("pause"):
			if _settings_panel != null and _settings_panel.visible:
				_close_settings()
				get_viewport().set_input_as_handled()
				return
			toggle()
			get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if visible:
		return
	visible = true
	_hide_other_ui()
	if pause_tree:
		get_tree().paused = true
	SFX.duck_master(&"pause_menu", duck_db)
	_play_sound(open_sound)
	pause_menu_opened.emit()


func close() -> void:
	if not visible:
		return
	_close_settings()
	visible = false
	_restore_other_ui()
	if pause_tree:
		get_tree().paused = false
	SFX.unduck_master(&"pause_menu")
	_play_sound(close_sound)
	pause_menu_closed.emit()


func _hide_other_ui() -> void:
	_hidden_siblings.clear()
	var parent: Node = get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling == self:
			continue
		if sibling is Control and (sibling as Control).visible:
			var control: Control = sibling as Control
			_hidden_siblings.append(control)
			control.visible = false


func _restore_other_ui() -> void:
	for control in _hidden_siblings:
		if control != null and is_instance_valid(control):
			control.visible = true
	_hidden_siblings.clear()


func _wire_settings() -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = false

	if _settings_close_button != null:
		_settings_close_button.pressed.connect(_close_settings)
	if _settings_reset_button != null:
		_settings_reset_button.pressed.connect(_on_reset_pressed)

	_wire_volume_row("MasterRow", GameSettings.master_volume, Callable(GameSettings, "set_master_volume"))
	_wire_volume_row("SFXRow", GameSettings.sfx_volume, Callable(GameSettings, "set_sfx_volume"))
	_wire_volume_row("MusicRow", GameSettings.music_volume, Callable(GameSettings, "set_music_volume"))

	_wire_window_mode_row()
	_wire_resolution_row()
	_wire_vsync_row()

	for action in GameSettings.DEFAULT_KEYBINDS:
		_wire_keybind_row(action)


func _wire_volume_row(row_name: String, initial: float, setter: Callable) -> void:
	if _content == null:
		return
	var slider: HSlider = _content.get_node_or_null("%s/Slider" % row_name) as HSlider
	var value_label: Label = _content.get_node_or_null("%s/Value" % row_name) as Label
	if slider == null:
		return
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	if value_label != null:
		value_label.text = "%d%%" % int(round(initial * 100.0))
	slider.value_changed.connect(func(v: float) -> void:
		setter.call(v)
		if value_label != null:
			value_label.text = "%d%%" % int(round(v * 100.0))
	)
	slider.drag_ended.connect(func(_changed: bool) -> void:
		GameSettings.save_settings()
	)


func _wire_window_mode_row() -> void:
	if _content == null:
		return
	var option: OptionButton = _content.get_node_or_null("WindowModeRow/Option") as OptionButton
	if option == null:
		return
	option.clear()
	option.add_item("Windowed", GameSettings.WindowMode.WINDOWED)
	option.add_item("Fullscreen", GameSettings.WindowMode.FULLSCREEN)
	option.add_item("Borderless", GameSettings.WindowMode.BORDERLESS)
	option.selected = GameSettings.window_mode
	option.item_selected.connect(func(idx: int) -> void:
		GameSettings.set_window_mode(idx)
		GameSettings.save_settings()
	)


func _wire_resolution_row() -> void:
	if _content == null:
		return
	var option: OptionButton = _content.get_node_or_null("ResolutionRow/Option") as OptionButton
	if option == null:
		return
	option.clear()
	var selected_idx: int = -1
	for i in range(GameSettings.COMMON_RESOLUTIONS.size()):
		var res: Vector2i = GameSettings.COMMON_RESOLUTIONS[i]
		option.add_item("%d x %d" % [res.x, res.y], i)
		if res == GameSettings.resolution:
			selected_idx = i
	if selected_idx < 0:
		option.add_item("%d x %d (current)" % [GameSettings.resolution.x, GameSettings.resolution.y], GameSettings.COMMON_RESOLUTIONS.size())
		selected_idx = GameSettings.COMMON_RESOLUTIONS.size()
	option.selected = selected_idx
	option.item_selected.connect(func(idx: int) -> void:
		if idx < GameSettings.COMMON_RESOLUTIONS.size():
			GameSettings.set_resolution(GameSettings.COMMON_RESOLUTIONS[idx])
			GameSettings.save_settings()
	)


func _wire_vsync_row() -> void:
	if _content == null:
		return
	var check: CheckBox = _content.get_node_or_null("VSyncRow/Check") as CheckBox
	if check == null:
		return
	check.button_pressed = GameSettings.vsync
	check.toggled.connect(func(pressed: bool) -> void:
		GameSettings.set_vsync(pressed)
		GameSettings.save_settings()
	)


func _wire_keybind_row(action: String) -> void:
	if _content == null:
		return
	var row_name: String = ACTION_TO_ROW.get(action, "")
	if row_name == "":
		return
	var key_button: Button = _content.get_node_or_null("%s/Key" % row_name) as Button
	var reset_button: Button = _content.get_node_or_null("%s/Reset" % row_name) as Button
	var label: Label = _content.get_node_or_null("%s/Label" % row_name) as Label
	if label != null:
		label.text = GameSettings.KEYBIND_LABELS.get(action, action)
	if key_button != null:
		_keybind_buttons[action] = key_button
		key_button.text = OS.get_keycode_string(GameSettings.get_key(action))
		key_button.pressed.connect(func() -> void:
			begin_rebind(action, key_button)
		)
	if reset_button != null:
		reset_button.pressed.connect(func() -> void:
			var default_key: int = int(GameSettings.DEFAULT_KEYBINDS.get(action, KEY_NONE))
			GameSettings.set_key(action, default_key)
			if key_button != null:
				key_button.text = OS.get_keycode_string(default_key)
		)


func _refresh_volume(row_name: String, value: float) -> void:
	if _content == null:
		return
	var slider: HSlider = _content.get_node_or_null("%s/Slider" % row_name) as HSlider
	if slider != null:
		slider.set_value_no_signal(value)
	var value_label: Label = _content.get_node_or_null("%s/Value" % row_name) as Label
	if value_label != null:
		value_label.text = "%d%%" % int(round(value * 100.0))


func _refresh_settings_ui() -> void:
	if _content == null:
		return
	_refresh_volume("MasterRow", GameSettings.master_volume)
	_refresh_volume("SFXRow", GameSettings.sfx_volume)
	_refresh_volume("MusicRow", GameSettings.music_volume)

	var window_option: OptionButton = _content.get_node_or_null("WindowModeRow/Option") as OptionButton
	if window_option != null:
		window_option.selected = GameSettings.window_mode
	var res_option: OptionButton = _content.get_node_or_null("ResolutionRow/Option") as OptionButton
	if res_option != null:
		var idx: int = -1
		for i in range(GameSettings.COMMON_RESOLUTIONS.size()):
			if GameSettings.COMMON_RESOLUTIONS[i] == GameSettings.resolution:
				idx = i
				break
		if idx >= 0:
			res_option.selected = idx
	var vsync_check: CheckBox = _content.get_node_or_null("VSyncRow/Check") as CheckBox
	if vsync_check != null:
		vsync_check.set_pressed_no_signal(GameSettings.vsync)

	for action in _keybind_buttons:
		var btn: Button = _keybind_buttons[action]
		if btn != null and is_instance_valid(btn):
			btn.text = OS.get_keycode_string(GameSettings.get_key(action))


func _on_resume_pressed() -> void:
	resume_requested.emit()
	close()


func _on_quit_pressed() -> void:
	quit_requested.emit()
	get_tree().paused = false
	SFX.unduck_master(&"pause_menu")
	get_tree().quit()


func _on_settings_pressed() -> void:
	if _settings_panel == null:
		return
	_refresh_settings_ui()
	_settings_panel.visible = true


func _close_settings() -> void:
	if _settings_panel == null:
		return
	_cancel_rebind()
	_settings_panel.visible = false


func _on_reset_pressed() -> void:
	GameSettings.reset_to_defaults()
	_refresh_settings_ui()


func begin_rebind(action: String, source_button: Button) -> void:
	_cancel_rebind()
	_rebinding_action = action
	_rebinding_button = source_button
	if _rebinding_button != null:
		_rebinding_button.text = "Press any key..."


func _cancel_rebind() -> void:
	if _rebinding_button != null and _rebinding_action != "":
		_rebinding_button.text = OS.get_keycode_string(GameSettings.get_key(_rebinding_action))
	_rebinding_action = ""
	_rebinding_button = null


func _apply_rebind(keycode: int) -> void:
	if keycode == KEY_ESCAPE:
		_cancel_rebind()
		return
	var action: String = _rebinding_action
	var button: Button = _rebinding_button
	_rebinding_action = ""
	_rebinding_button = null
	GameSettings.set_key(action, keycode)
	if button != null:
		button.text = OS.get_keycode_string(keycode)


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = SFX.play_oneshot(self, stream, 0.0)
	if player != null:
		player.bus = &"Master"
