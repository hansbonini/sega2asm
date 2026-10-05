extends Control
## Lists every asset in res://data/manifest.json with its ROM address, shows
## the image (tile sheet preview, tilemap render or palette) and plays PCM data.

var _list := ItemList.new()
var _view := TextureRect.new()
var _info := Label.new()
var _player := AudioStreamPlayer.new()
var _assets: Array = []


func _ready() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	_list.custom_minimum_size = Vector2(360, 0)
	split.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	right.add_child(_info)
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(_view)
	add_child(_player)

	var doc = JSON.parse_string(FileAccess.get_file_as_string("res://data/manifest.json"))
	_assets = doc["assets"]
	for a in _assets:
		_list.add_item("%s  [%s]  $%06X" % [a["name"], a["kind"], int(a["rom_start"])])
	_list.item_selected.connect(_on_selected)


func _on_selected(index: int) -> void:
	var a: Dictionary = _assets[index]
	var files: Dictionary = a["files"]
	_info.text = "%s\n%s   ROM $%06X-$%06X   %d bytes   %s\n%s" % [
		a["name"], a["kind"], int(a["rom_start"]), int(a["rom_end"]), int(a["size"]),
		a.get("compression", ""), a.get("description", "")]
	_view.texture = null
	for key in ["render", "preview", "texture"]:
		if files.has(key):
			_view.texture = load(files[key])
			break
	_player.stop()
	if files.has("wav"):
		_player.stream = load(files["wav"])
		_player.play()
