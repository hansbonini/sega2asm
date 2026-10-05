class_name ISSWeather
extends Sprite2D
## The plane A weather overlay of ISS Deluxe (snow or rain), tiled over the
## stadium map from its origin like the game's plane A, which scrolls with
## the pitch. Frames advance at the game's 60 Hz rate; fine weather has no
## overlay. Keep it above the players: every plane A cell has priority set.

const DIR := "res://assets/iss/weather/"

static var _doc: Dictionary = {}

@export_range(0, 7) var stadium: int = 0:
	set(value):
		stadium = value
		_reload()

## g_weather: 0 snow, 1 fine, 2 rain.
@export_enum("Snow", "Fine", "Rain") var weather: int = 1:
	set(value):
		weather = value
		_reload()

## Area to cover in map pixels (the stadium size).
@export var area := Vector2i(2720, 832):
	set(value):
		area = value
		region_rect = Rect2(Vector2.ZERO, area)

var _frames: Array[Texture2D] = []
var _ticks := 1
var _time := 0.0


func _ready() -> void:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "weather.json"))
	centered = false
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	region_enabled = true
	region_rect = Rect2(Vector2.ZERO, area)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	material = mat
	_reload()


func _reload() -> void:
	if not is_inside_tree() or _doc.is_empty():
		return
	var w: Dictionary = _doc["weathers"][weather]
	_frames.clear()
	for p: String in w.get("frames", []) if w.get("frames") != null else []:
		_frames.append(load(p))
	_ticks = maxi(1, int(w["frame_ticks"]))
	visible = not _frames.is_empty()
	var pal := "res://assets/iss/stadiums/stadium%d_%s.pal.png" % [stadium, ISSPitch.WEATHERS[weather]]
	(material as ShaderMaterial).set_shader_parameter("palette", load(pal))
	_show()


func _process(delta: float) -> void:
	_time += delta
	_show()


func _show() -> void:
	if _frames.is_empty():
		return
	texture = _frames[int(_time * 60.0 / _ticks) % _frames.size()]
