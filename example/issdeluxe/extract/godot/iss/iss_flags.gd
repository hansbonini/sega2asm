class_name ISSFlags
extends Node2D
## The six pitch flags of a stadium (flag_draw, $02D50C): the four corners
## and both ends of the halfway line, taken from the stadium's pitch_bounds,
## waving through 4 frames every 6 video frames like flag_animate.

const DIR := "res://assets/iss/flags/"
const PALETTE := "res://assets/iss/players/palette_match.pal.png"

static var _doc: Dictionary = {}

@export_range(0, 7) var stadium: int = 0:
	set(value):
		stadium = value
		_rebuild()

var _flags: Array[Sprite2D] = []
var _time := 0.0


func _ready() -> void:
	if _doc.is_empty():
		_doc = JSON.parse_string(FileAccess.get_file_as_string(DIR + "flags.json"))
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or _doc.is_empty():
		return
	for f in _flags:
		f.queue_free()
	_flags.clear()
	var stadiums = JSON.parse_string(FileAccess.get_file_as_string("res://assets/iss/stadiums/stadiums.json"))
	var b: Dictionary = stadiums["stadiums"][stadium]["pitch_bounds"]
	var middle := (int(b["left"]) + int(b["right"])) / 2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("palette", load(PALETTE))
	mat.set_shader_parameter("shadow_highlight", true)
	for x in [b["left"], middle, b["right"]]:
		for y in [b["top"], b["bottom"]]:
			var s := Sprite2D.new()
			s.centered = false
			s.material = mat
			var pitch := Vector2(int(x), int(y))
			s.position = ISSProjection.to_map(pitch)
			s.z_index = int(pitch.y)
			add_child(s)
			_flags.append(s)
	_show()


func _process(delta: float) -> void:
	_time += delta
	_show()


func _show() -> void:
	var frames: Array = _doc["actions"][0]
	var ticks := int(_doc["frame_ticks"])
	var r: Dictionary = frames[int(_time * 60.0 / ticks) % frames.size()]
	for s in _flags:
		s.texture = load(r["png"])
		s.offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
