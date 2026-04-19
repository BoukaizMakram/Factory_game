extends Node

signal settings_changed

const CONFIG_PATH: String = "user://settings.cfg"

const DEFAULT_KEYBINDS: Dictionary = {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"inventory": KEY_E,
	"pause": KEY_ESCAPE,
	"debug_console": KEY_F1,
	"placer_cancel": KEY_Q,
	"placer_rotate": KEY_R,
	"placer_pipe_cross": KEY_T,
	"placer_toggle_grid": KEY_G,
	"placer_inspect": KEY_ALT,
	"hotbar_1": KEY_1,
	"hotbar_2": KEY_2,
	"hotbar_3": KEY_3,
	"hotbar_4": KEY_4,
	"hotbar_5": KEY_5,
	"hotbar_6": KEY_6,
}

const KEYBIND_LABELS: Dictionary = {
	"move_up": "Move Up",
	"move_down": "Move Down",
	"move_left": "Move Left",
	"move_right": "Move Right",
	"inventory": "Inventory",
	"pause": "Pause",
	"debug_console": "Debug Console",
	"placer_cancel": "Cancel Placement",
	"placer_rotate": "Rotate",
	"placer_pipe_cross": "Pipe Crossing",
	"placer_toggle_grid": "Toggle Grid",
	"placer_inspect": "Inspect Pipes",
	"hotbar_1": "Hotbar 1",
	"hotbar_2": "Hotbar 2",
	"hotbar_3": "Hotbar 3",
	"hotbar_4": "Hotbar 4",
	"hotbar_5": "Hotbar 5",
	"hotbar_6": "Hotbar 6",
}

const COMMON_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

var master_volume: float = 1.0
var sfx_volume: float = 1.0
var music_volume: float = 1.0
var window_mode: int = WindowMode.WINDOWED
var resolution: Vector2i = Vector2i(1920, 1080)
var vsync: bool = true
var keybinds: Dictionary = DEFAULT_KEYBINDS.duplicate(true)

var _loaded_from_disk: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	SFX.refresh_master_volume()
	_apply_bus_volume(&"SFX", sfx_volume)
	_apply_bus_volume(&"Music", music_volume)
	if _loaded_from_disk:
		apply_window()
		apply_vsync()


func get_key(action: String) -> int:
	return int(keybinds.get(action, DEFAULT_KEYBINDS.get(action, KEY_NONE)))


func set_key(action: String, keycode: int) -> void:
	keybinds[action] = keycode
	settings_changed.emit()
	save_settings()


func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 1.0)
	SFX.refresh_master_volume()
	settings_changed.emit()


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volume(&"SFX", sfx_volume)
	settings_changed.emit()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	_apply_bus_volume(&"Music", music_volume)
	settings_changed.emit()


func set_window_mode(mode: int) -> void:
	window_mode = clampi(mode, 0, WindowMode.BORDERLESS)
	apply_window()
	settings_changed.emit()


func set_resolution(res: Vector2i) -> void:
	resolution = res
	apply_window()
	settings_changed.emit()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	apply_vsync()
	settings_changed.emit()


func apply_all() -> void:
	SFX.refresh_master_volume()
	_apply_bus_volume(&"SFX", sfx_volume)
	_apply_bus_volume(&"Music", music_volume)
	apply_window()
	apply_vsync()


func apply_window() -> void:
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
			DisplayServer.window_set_position(Vector2i.ZERO)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(resolution)
			var screen_size: Vector2i = DisplayServer.screen_get_size()
			var centered: Vector2i = (screen_size - resolution) / 2
			DisplayServer.window_set_position(centered)


func apply_vsync() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "resolution", resolution)
	cfg.set_value("video", "vsync", vsync)
	for action in keybinds:
		cfg.set_value("keybinds", action, int(keybinds[action]))
	cfg.save(CONFIG_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	_loaded_from_disk = true
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	window_mode = int(cfg.get_value("video", "window_mode", window_mode))
	resolution = cfg.get_value("video", "resolution", resolution)
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	for action in DEFAULT_KEYBINDS:
		keybinds[action] = int(cfg.get_value("keybinds", action, DEFAULT_KEYBINDS[action]))


func reset_to_defaults() -> void:
	master_volume = 1.0
	sfx_volume = 1.0
	music_volume = 1.0
	window_mode = WindowMode.WINDOWED
	resolution = Vector2i(1920, 1080)
	vsync = true
	keybinds = DEFAULT_KEYBINDS.duplicate(true)
	apply_all()
	save_settings()
	settings_changed.emit()


func _apply_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = -80.0 if linear <= 0.001 else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, linear <= 0.001)
