class_name ISSKeeperSprite
extends Sprite2D
## A goalkeeper drawn from the exported keeper frame set (tbl_keeper_anims,
## drawn by obj_set_frame_draw_draw): his own 37 actions in 16 directions,
## whole frames (no separate head or kit tiles) coloured by the team's kit
## palette on line 0 (the keeper's colours are 1-3).

const DIR := "res://assets/iss/keeper/"
const KITS := "res://assets/iss/players/kits.json"

static var _anims: Dictionary = {}
static var _kits: Array = []
static var _base_palette: Image

@export var action: int = 0
@export_range(0, 63) var facing: int = 0
@export var frames_per_second: float = 8.0
@export var team: int = 0
@export var second_kit: bool = false

var manual := false

var _frame := 0
var _time := 0.0


static func _ensure() -> void:
	if _anims.is_empty():
		_anims = JSON.parse_string(FileAccess.get_file_as_string(DIR + "animations.json"))
		_kits = JSON.parse_string(FileAccess.get_file_as_string(KITS))["teams"]
		_base_palette = (load("res://assets/iss/players/palette_match.pal.png") as Texture2D).get_image()


func _ready() -> void:
	_ensure()
	centered = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("shadow_highlight", true)
	material = mat
	set_kit(team, second_kit)
	_show()


## The team's first or second kit palette on line 0.
func set_kit(team_index: int, use_second: bool) -> void:
	team = team_index
	second_kit = use_second
	var kit: Array = _kits[team]["second_kit" if use_second else "first_kit"]
	set_kit_words(kit)


## The whole palette from 64 CRAM words (the front end's figures use the
## screen's own CRAM, fades included); the kit from line kit_line (an away
## side's figure has line 1, obj_attr $A0).
func set_palette_cram(cram: PackedInt32Array, kit_line := 0) -> void:
	if material == null:
		return
	var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for i in 64:
		var src := i if i >= 16 else kit_line * 16 + i
		img.set_pixel(i & 15, i >> 4, MDPalette.cram_to_color(cram[src]))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


## A kit palette given as 16 CRAM words (the team colours screen's own kit).
func set_kit_words(kit: Array) -> void:
	if _base_palette == null:
		return
	var img := _base_palette.duplicate() as Image
	for i in mini(16, kit.size()):
		img.set_pixel(i, 0, MDPalette.cram_to_color(int(kit[i])))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


## Direction 0-15 of a facing 0-63 (obj_set_frame_draw_draw).
static func direction(f: int) -> int:
	return ((f + 2) & 0x3C) >> 2


static func frame_count(act: int, dir: int) -> int:
	var seq: Array = _anims["actions"][act]["directions"][dir]
	return maxi(1, seq.size())


func action_count() -> int:
	return (_anims["actions"] as Array).size()


func set_pose(new_action: int, frame: int, new_facing: int, loop: bool) -> void:
	_ensure()
	manual = true
	action = clampi(new_action, 0, action_count() - 1)
	facing = new_facing
	var n := frame_count(action, direction(new_facing))
	_frame = frame % n if loop else mini(frame, n - 1)
	_show()


func _process(delta: float) -> void:
	if manual:
		return
	_time += delta
	if _time >= 1.0 / frames_per_second:
		_time = 0.0
		_frame += 1
		_show()


func _show() -> void:
	if _anims.is_empty():
		return
	var dir := direction(facing)
	var seq: Array = _anims["actions"][action]["directions"][dir]
	if seq.is_empty():
		return
	var f: Dictionary = _anims["frames"][seq[_frame % seq.size()]]
	var r: Dictionary = f["left" if dir >= 8 else "right"]
	texture = load(r["png"])
	offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
