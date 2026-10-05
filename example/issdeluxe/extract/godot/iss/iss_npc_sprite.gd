class_name ISSNPCSprite
extends Sprite2D
## A non-player character of ISS Deluxe (npc_draw, $033034): referee,
## linesman, medic, stretcher or the dog. `action` indexes
## assets/iss/npc/animations.json (see its action_names). The officials' kit
## is palette line 2 colours 0-7; `kit` picks one of the four variants.

const DIR := "res://assets/iss/npc/"
const PALETTE := "res://assets/iss/players/palette_match.pal.png"

static var _anims: Dictionary = {}
static var _kits: Array = []
static var _base_palette: Image

@export var action: int = 0
@export_range(0, 63) var facing: int = 0
@export var frames_per_second: float = 8.0
@export_range(0, 3) var kit: int = 0

## Driven by set_pose() instead of its own clock.
var manual := false

var _frame := 0
var _time := 0.0


func _ready() -> void:
	if _anims.is_empty():
		_anims = JSON.parse_string(FileAccess.get_file_as_string(DIR + "animations.json"))
		_kits = JSON.parse_string(FileAccess.get_file_as_string(DIR + "kits.json"))["variants"]
		_base_palette = (load(PALETTE) as Texture2D).get_image()
	centered = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("shadow_highlight", true) # shadows are line 3 colour 15
	material = mat
	set_kit(kit)
	_show()


## Recolour the officials' kit (variant 0-3, as chosen by $FF164A).
func set_kit(variant: int) -> void:
	kit = variant
	var img := _base_palette.duplicate() as Image
	var words: Array = _kits[variant]
	for i in words.size():
		img.set_pixel(i, 2, MDPalette.cram_to_color(int(words[i])))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


## The whole palette from 64 CRAM words (the cinematics' own colours,
## fades included).
func set_palette_cram(cram: PackedInt32Array, _line := 2) -> void:
	if material == null:
		return
	var img := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for i in 64:
		img.set_pixel(i & 15, i >> 4, MDPalette.cram_to_color(cram[i]))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


## Show frame `frame` of `new_action` facing `new_facing` (wrapping).
func set_pose(new_action: int, frame: int, new_facing: int) -> void:
	manual = true
	action = new_action
	facing = new_facing
	_frame = frame
	if is_inside_tree():
		_show()


func play(new_action: int) -> void:
	if new_action != action:
		action = new_action
		_frame = 0
		_show()


static func action_names() -> Array:
	return _anims.get("action_names", [])


func _process(delta: float) -> void:
	if manual:
		return
	_time += delta
	if _time >= 1.0 / frames_per_second:
		_time = 0.0
		_frame += 1
		_show()


func _show() -> void:
	var dir := ISSProjection.direction(facing)
	var seq: Array = _anims["actions"][action]["directions"][dir]
	if seq.is_empty():
		return
	var f: Dictionary = _anims["frames"][seq[_frame % seq.size()]]
	var r: Dictionary = f["left" if ((facing + 4) & 63) >= 0x28 else "right"]
	texture = load(r["png"])
	offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
