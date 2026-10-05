@tool
class_name MDTilemap
extends Node2D
## Rebuilds a Mega Drive plane from a tilemap JSON exported by `sega2asm godot`.
##
## Every nametable word (priority, palette line, v/h flip, tile) becomes a cell
## in one of two TileMapLayers: "Low" and "High" (priority bit set, drawn above
## sprites like on the VDP). The tile set has one atlas source per palette line
## (source id = line) and alternative tiles 1/2/3 for h-flip / v-flip / both.

@export_file("*.json") var tilemap_json: String = "":
	set(value):
		tilemap_json = value
		if is_inside_tree():
			rebuild()


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if tilemap_json.is_empty():
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(tilemap_json))
	if doc == null or not doc.has("atlases"):
		push_warning("MDTilemap: %s has no atlases (tiles or palette unknown)" % tilemap_json)
		return
	var tile_set := build_tileset(doc)
	var low := TileMapLayer.new()
	low.name = "Low"
	low.tile_set = tile_set
	add_child(low)
	var high := TileMapLayer.new()
	high.name = "High"
	high.tile_set = tile_set
	high.z_index = 2
	add_child(high)

	var width := int(doc["width"])
	var base := int(doc.get("tile_base", 0))
	var cols := int(doc["atlas_columns"])
	var count := int(doc["tile_count"])
	var words: Array = doc["words"]
	for i in words.size():
		var word := int(words[i])
		var tile := (word & 0x7FF) - base
		if tile < 0 or tile >= count:
			continue
		var line := (word >> 13) & 3
		var alt := (1 if word & 0x800 else 0) | (2 if word & 0x1000 else 0)
		var layer := high if word & 0x8000 else low
		layer.set_cell(Vector2i(i % width, i / width), line, Vector2i(tile % cols, tile / cols), alt)


static func build_tileset(doc: Dictionary) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(8, 8)
	var cols := int(doc["atlas_columns"])
	var count := int(doc["tile_count"])
	var atlases: Array = doc["atlases"]
	for line in atlases.size():
		var src := TileSetAtlasSource.new()
		src.texture = load(atlases[line])
		src.texture_region_size = Vector2i(8, 8)
		for t in count:
			var coords := Vector2i(t % cols, t / cols)
			src.create_tile(coords)
			for alt in [1, 2, 3]:
				src.create_alternative_tile(coords, alt)
				var data := src.get_tile_data(coords, alt)
				data.flip_h = (alt & 1) != 0
				data.flip_v = (alt & 2) != 0
		tile_set.add_source(src, line)
	return tile_set
