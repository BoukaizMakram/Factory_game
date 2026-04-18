class_name BeltItem
extends Sprite2D

const ORE_MAPPING_SCENE_PATH: String = "res://Scenes/belt.tscn"

@export var ore_types: Array[String] = []
@export var ore_sprites: Array[Texture2D] = []
@export var raw_ore_type: String = "dirty"

static var _ore_texture_cache: Dictionary = {}


func get_texture_for_type(type_key) -> Texture2D:
	var mapped_texture: Texture2D = find_texture_for_type(type_key)
	if mapped_texture != null:
		return mapped_texture
	return texture


func get_texture_for_item(item: Dictionary) -> Texture2D:
	if String(item.get("processing", "RAW")).to_upper() == "RAW" or String(item.get("visual", "raw")).to_lower() == "raw":
		return get_texture_for_type(raw_ore_type)
	return get_texture_for_type(item.get("type", ""))


func find_texture_for_type(type_key) -> Texture2D:
	var type_name: String = _normalize_type_name(type_key)
	for i in range(min(ore_types.size(), ore_sprites.size())):
		if _normalize_type_name(ore_types[i]) == type_name and ore_sprites[i] != null:
			return ore_sprites[i]
	return null


static func get_mapped_texture(type_key) -> Texture2D:
	_ensure_ore_texture_cache()
	return _ore_texture_cache.get(_normalize_type_name(type_key), null)


static func _ensure_ore_texture_cache() -> void:
	if not _ore_texture_cache.is_empty():
		return
	var scene: PackedScene = load(ORE_MAPPING_SCENE_PATH) as PackedScene
	if scene == null:
		return
	var root: Node = scene.instantiate()
	if root == null:
		return
	_collect_ore_textures(root)
	root.free()


static func _collect_ore_textures(node: Node) -> void:
	if node is BeltItem:
		var item: BeltItem = node as BeltItem
		for i in range(min(item.ore_types.size(), item.ore_sprites.size())):
			var type_name: String = _normalize_type_name(item.ore_types[i])
			if type_name != "" and item.ore_sprites[i] != null and not _ore_texture_cache.has(type_name):
				_ore_texture_cache[type_name] = item.ore_sprites[i]
	for child in node.get_children():
		_collect_ore_textures(child)


static func _normalize_type_name(type_key) -> String:
	if type_key is String:
		return (type_key as String).strip_edges().to_lower()
	if type_key is StringName:
		return String(type_key).strip_edges().to_lower()
	if type_key is PackedScene:
		var path: String = (type_key as PackedScene).resource_path
		if path != "":
			return path.get_file().get_basename().strip_edges().to_lower()
	return str(type_key).strip_edges().to_lower()
