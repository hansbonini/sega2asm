class_name ISSPlayerSprite
extends Sprite2D
## An ISS Deluxe player drawn from the exported animation frames.
##
## Frames are CRAM-index images (line * 16 + colour). The palette texture holds
## the kit on line 0, skin/hair on line 2 and the shadow colour on line 3, so a
## different kit is just a different palette row (set_kit).

const DIR := "res://assets/iss/players/"

static var _anims: Dictionary = {}
static var _kits: Array = []
static var _base_palette: Image

@export var action: int = 0
@export_range(0, 63) var facing: int = 0
@export var frames_per_second: float = 8.0
@export var team: int = 0
@export var second_kit: bool = false

## Driven by set_pose() (the match engine) instead of its own clock.
var manual := false

## The player's own look (ISSPlayerLook): his head by shirt number, his hair
## style and his team's kit tiles, instead of the exported frames' generic
## ones. Off until set_look().
var look := false
var look_number := 1
var look_hair := 0
var look_second_tiles := false

var _frame := 0
var _time := 0.0


static func _ensure() -> void:
	if _anims.is_empty():
		_anims = JSON.parse_string(FileAccess.get_file_as_string(DIR + "animations.json"))
		_kits = JSON.parse_string(FileAccess.get_file_as_string(DIR + "kits.json"))["teams"]
		_base_palette = (load(DIR + "palette_match.pal.png") as Texture2D).get_image()


func _ready() -> void:
	_ensure()
	centered = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://md/md_indexed.gdshader")
	mat.set_shader_parameter("shadow_highlight", true) # shadows are line 3 colour 15
	material = mat
	set_kit(team, second_kit)
	_show()


## Recolour the player with a team's first or second kit.
func set_kit(team_index: int, use_second: bool) -> void:
	team = team_index
	second_kit = use_second
	set_kit_words(_kits[team]["second_kit" if use_second else "first_kit"])


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
	var img := _base_palette.duplicate() as Image
	for i in mini(16, kit.size()):
		img.set_pixel(i, 0, MDPalette.cram_to_color(int(kit[i])))
	(material as ShaderMaterial).set_shader_parameter("palette", ImageTexture.create_from_image(img))


## Draw this player as player_draw does for him: shirt number (1-20, the
## head), hair style, and the team's first or second kit tiles.
func set_look(team_index: int, second_tiles: bool, number: int, hair: int) -> void:
	team = team_index
	look = true
	look_second_tiles = second_tiles
	look_number = number
	look_hair = hair
	_ensure()
	_show()


func play(new_action: int) -> void:
	if new_action != action:
		action = new_action
		_frame = 0
		_show()


func action_count() -> int:
	return (_anims["actions"] as Array).size()


## Show frame `frame` of `new_action` facing `new_facing`; looping actions
## wrap, the others hold their last frame.
func set_pose(new_action: int, frame: int, new_facing: int, loop: bool) -> void:
	_ensure()
	manual = true
	action = new_action
	facing = new_facing
	var n := frame_count(new_action, ISSProjection.direction(new_facing))
	_frame = frame % n if loop else mini(frame, n - 1)
	_show()


static func frame_count(act: int, dir: int) -> int:
	var seq: Array = _anims["actions"][act]["directions"][dir]
	return maxi(1, seq.size())


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
	var addr: String = seq[_frame % seq.size()]
	if look:
		var t: Array = ISSPlayerLook.frame(addr, dir >= 5, team, look_second_tiles, look_number, look_hair)
		texture = t[0]
		offset = t[1]
		return
	var f: Dictionary = _anims["frames"][addr]
	var r: Dictionary = f["left" if dir >= 5 else "right"]
	texture = load(r["png"])
	offset = Vector2(-int(r["origin_x"]), -int(r["origin_y"]))
