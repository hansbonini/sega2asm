@tool
class_name ISSPitch
extends TileMapLayer
## A stadium built from the exported 16x16 metatile atlas and map
## (assets/iss/stadiums), matching the game's pitch scroller ($01DD88).

const DIR := "res://assets/iss/stadiums/"
## Indexed by g_weather ($FF162E): 0 snow, 1 fine (the default), 2 rain.
const WEATHERS := ["snow", "fine", "rain"]

@export_range(0, 7) var stadium: int = 0:
	set(value):
		stadium = value
		if is_inside_tree():
			rebuild()

@export_enum("Snow", "Fine", "Rain") var weather: int = 1:
	set(value):
		weather = value
		if is_inside_tree():
			rebuild()


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	clear()
	var atlas: Texture2D = load(DIR + "stadium%d_%s_metatiles.png" % [stadium, WEATHERS[weather]])
	var doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "stadium%d_map.json" % stadium))
	if atlas == null or doc == null:
		push_warning("ISSPitch: run the ISS extractor first")
		return
	var cols := atlas.get_width() / 16
	var rows := atlas.get_height() / 16
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = Vector2i(16, 16)
	for i in cols * rows:
		src.create_tile(Vector2i(i % cols, i / cols))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	ts.add_source(src, 0)
	tile_set = ts
	var width := int(doc["width"])
	var cells: Array = doc["metatiles"]
	for i in cells.size():
		var m := int(cells[i])
		set_cell(Vector2i(i % width, i / width), 0, Vector2i(m % cols, m / cols))


## Size of the stadium in pixels.
func pixel_size() -> Vector2i:
	var doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "stadium%d_map.json" % stadium))
	return Vector2i(int(doc["width"]) * 16, int(doc["height"]) * 16)
